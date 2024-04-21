# Commands

## Kind cluster

Create a kind cluster

```bash
time kind create cluster
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
