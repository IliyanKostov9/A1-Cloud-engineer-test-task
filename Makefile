#!/usr/bin/env make

SHELL := /bin/bash
.DEFAULT_GOAL := help

###########################
# VARIABLES
###########################

ifeq ($(OS),Windows_NT) # set Python , depending if user is in windows or linux
    PYTHON = python
else
    PYTHON = python3
endif

MARKER_CHOICES := placeholder1 placeholder2
MARKER := $(shell cat placeholder_value.txt 2>/dev/null || echo "Nothing")

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
mkfile_dir := $(dir $(mkfile_path))

GITGUARDIAN_NUM_COMMITS ?= 1

###########################
# HELP
###########################

.PHONY: help-marker
help-markers:  ## print valid placeholder
	@echo "Available marker:"s
	@echo "------------------"
	@echo "marker1"
	@echo "marker2"

.PHONY: help
help:  ## help to show available commands with info
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) |  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@make help-marker

#################
#
# Run the following lines for setting up your venv
# afterwards you must do a source .venv/bin/activate
#
##################

.PHONY: setup-venv
setup-venv: ## setup venv if needed
	${PYTHON} -m venv .venv
	. ${mkfile_dir}.venv/bin/activate

.PHONY: install-deps
install-deps: ## install python deps
	${PYTHON} -m pip install -r requirements.txt

#################
#
# Set parameters
#
##################

.PHONY: set-marker
set-marker: ## set placeholder
	@counter =0; \
	echo "Choose placeholders from ( 1 - $(words $(MARKER_CHOICES)) ):"; \
	echo "---------------------------"; \
	for value in $(MARKER_CHOICES); do \
		echo "$$((counter+=1)). $$value"; \
	done; \
	read -p "Enter choice " choice; \
	if [ -z "$$(echo $(MARKER_CHOICES) | cut -d ' ' -f $$choice)" ]; then \
		echo "Set to default $(MARKER)"; \
	else \
		# echo "You chose $$(echo $(MARKER_CHOICES) | cut -d ' ' -f $$choice).";\
		echo $$(echo $(MARKER_CHOICES) | cut -d ' ' -f $$choice) > marker_value.txt; \
	fi


##############
#
# Run k8s Crossplane
#
##############

.PHONY: kind-create
kind-create:  ## create kind cluster
	time kind create cluster
	kind get clusters
	kubectl config use-context kind-kind
	helm repo add crossplane-stable https://charts.crossplane.io/stable
	helm repo update
	helm install crossplane \
	--namespace crossplane-system \
	--create-namespace crossplane-stable/crossplane
	kubectl get pods -n crossplane-system
	kubectl get deployments -n crossplane-system
	kubectl get providers

.PHONY: install-azure-provider
install-azure-provider:  ## install azure provider
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
	kubectl get providers

#################
#
# Run pytests
#
##################

.PHONY: test
test: set-marker  ## run tests
	$(eval PYTEST_PATH = src/tests/$(MARKER)/)
	@echo "PYTEST_PATH = $(PYTEST_PATH)"
	@echo "MARKER = $(MARKER)"
	${PYTHON} -m pytest '${PYTEST_PATH}' -m ${MARKER}


.PHONY: secret-scan
secret-scan:  ## run secret scan with GitGuardian
	ggshield secret scan path ../../ --recursive

.PHONY: secret-scan-commit-range
secret-scan-commit-range:  ## run secret scan for git commit range with GitGuardian
	@read -p "Choose the number of commits starting from $(GITGUARDIAN_NUM_COMMITS): " num_commits; \
	if [ -z "$$num_commits" ]; then \
		num_commits="$(GITGUARDIAN_NUM_COMMITS)"; \
	else \
		num_commits="$$num_commits"; \
	fi; \
	echo "Command: ggshield secret scan commit-range HEAD~$$num_commits"
	ggshield secret scan commit-range "HEAD~$$num_commits"
