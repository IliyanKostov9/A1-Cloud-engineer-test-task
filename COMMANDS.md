# Commands

## Azure

Get subscription id

```bash
az account show --query id --output tsv
```

### Crossplane

List CRDs

```bash
 kubectl get crd
```

## Kind cluster

Create a kind cluster

```bash
time kind create cluster
```

List all clusters

```bash
kind get clusters
kubectl config use-context kind-kind

```

Create a cluster

```bash
kind create cluster
```

Delete a cluster:

```bash
kind delete cluster
```

## Crossplane

Add Crossplane to Helm repo

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

```

Install the Crossplane Helm chart

```bash
helm install crossplane \
--namespace crossplane-system \
--create-namespace crossplane-stable/crossplane

```

View installed Crossplane pods

```bash
kubectl get pods -n crossplane-system
kubectl get deployments -n crossplane-system
```

View all instaleld providers

```bash
kubectl get providers
```

View all CRDs

```bash
kubectl get crds
```


Install the Azure resource provider for VM, resource group and a virtual networking by using:

```bash

## For installing providers

cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-azure-network
spec:
  package: xpkg.upbound.io/upbound/provider-azure-network:v0.42.1
EOF

cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-azure-compute
spec:
  package: xpkg.upbound.io/upbound/provider-azure-compute:v0.42.1
EOF

```

These commands are esentially installing the k8s custom resource definitions CRD directly inside the cluster, in order for the cluster to be able to deploy resources on the Azure platform.

Verify the providers are installed by using:

```bash
kubectl get providers
```

In order for us to deploy anything in the Azure cloud platform, we first need to login from the Azure CLI by using:

```bash
az login
```

Right before starting deploying things, we need to create an authentication identity for the cluster, to be permitted to interact within our Azure subscription. There are 2 ways to do so:
1. SPN with password
2. SPN with cert

For the sake of following best practices, let's proceed with the certificate.
Use the command:

```bash

az ad sp create-for-rbac --sdk-auth \
--role Owner \
--scopes /subscriptions/$(az account show --query id --output tsv) \
--create-cert > azure_credentials.json

```

The azure_credentials.json file will be generated in your folder directory afterwards, that contains the basic SPN credentials, iincluding client_ID, secrent and tenant id, as well as the certificate beginning with ---BEND END

Before creating an SPN, you would need to base64 the certificate content

```bash
# extract the path of the generated PEM certificate
AZ_CLIENT_CERT_PEM_PATH="$(jq -r '.clientCertificate' azure_credentials.json)"

# convert PEM to PKCS12 using openssl tool
openssl pkcs12 -export \
               -out azure_sp_cert.pkcs12 \
               -in "${AZ_CLIENT_CERT_PEM_PATH}" \
               -inkey "${AZ_CLIENT_CERT_PEM_PATH}" \
               -passout pass:

# encode the certificate
base64 -i azure_sp_cert.pkcs12 | tr -d '\n' > azure_sp_cert_pkcs12_base64encoded

# replace clientCertificate field in azure_credentials.json with base64-encoded certificate content
jq --rawfile certcontent azure_sp_cert_pkcs12_base64encoded \
    '.clientCertificate=$certcontent' azure_credentials.json > azure_credentials_withcert.json
```

Finally, connect the kubectl to the Azure creds file along with the k8s secret:

```bash
kubectl create secret generic azure-secret -n crossplane-system --from-file=creds=./azure_credentials_withcert.json

```

The output of it should look something like:

```bash
secret/azure-secret created
```

Verify the secret was created by using:

```bash
kubectl describe secret azure-secret -n crossplane-system
```

And it should output:

```bash
Name:         azure-secret
Namespace:    crossplane-system
Labels:       <none>
Annotations:  <none>

Type:  Opaque

Data
====
creds:  3842 bytes
```

For centralizing all of our Crossplane resource config, we can use ProviderConfig. Let's use the command:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: azure.upbound.io/v1beta1
metadata:
  name: default
kind: ProviderConfig
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: azure-secret
      key: creds
EOF

```

For creating the custom API, we can start by defining naming conveniton for our group and group. Acorrding to the k8s docs, the naming convention for the group should be a domain name (e.g `package.example.com`) and a the version should eitheer contain alpha/beta for unstable version and without those for stable (e.g `v1alpha1`,`v1beta1`,`v1`).
That in result would make the apiVersion object `package.example.com/v1alpha1`.
As for the kind object, it should be an entity of the scope of the apiVersion domain, for example if the apiVersion is compute, the kind should be VirtualMachine `kind: VirtualMachine
`.
The `specs` object describes the user inputs, that he has to provide when calling the custom API like:

```yml
spec:
  location: "US"
```

XRD is responsible for installing the custom API to the cluster. The higher level of spec of XRD contains the info of the API like group,version,kind and schema.
XRD name must be a combination of plural + group.
The claimNames object is used for allowing users to access the API either at the cluster level of `VirtualMachine` or namespace via the Claim `VirtualMachineClaim`.

Now apply the XRD to create the API to the clust by using:

```bash
kubectl apply -f custom_resource_definition.yml
```

Output should look something like:

```bash
compositeresourcedefinition.apiextensions.crossplane.io/virtualmachines.compute.example.com created
```

View the XRDand resources

```bash
kubectl get xrd
kubectl api-resources | grep VirtualMachine
```

The compostion is created by taking user inputs and deploying XRD.

Finally let's deploy the Azure infra:

```bash
kubectl apply -f composition.yml
```

View the composition by using:

```bash

kubectl get composition
```

Finally we need to call the custom API resource and provide the location we want to deploy our Azure resources:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: compute.example.com/v1alpha1
kind: VirtualMachine
metadata:
  name: my-vm
spec:
  location: "EU"
EOF

```

View the deployed resource:

```bash
kubectl get VirtualMachine
```

Now we can create a claim to self-contain the XR.
Create a cluster:

```bash
kubectl create namespace crossplane-test
```

Output:

```bash
namespace/crossplane-test created
```

Then associate the claim namespace to the XR apiVersion:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: compute.example.com/v1alpha1
kind: VirtualMachineClaim
metadata:
  name: my-namespaced-vm
  namespace: crossplane-test
spec:
  location: "EU"
EOF

```

Output:

```bash
virtualmachineclaim.compute.example.com/my-namespaced-vm created
```

View the claim namespace:

```bash
kubectl get claim -n crossplane-test

# A namespace is creating it's own copy of composite
# View the composite

kubectl get composite
```

Delete the claim and the standalone composite

```bash
# Standalone composite
kubectl delete VirtualMachine my-vm
# Claim
kubectl delete claim -n crossplane-test my-namespaced-vm
```
