```makefile
SHELL := /bin/bash

ROOT := $(CURDIR)
KUBECTL ?= kubectl

# Kubespray configuration
KUBESPRAY_DIR ?= $(HOME)/kubespray
KUBESPRAY_INVENTORY_DIR ?= $(ROOT)/k8s-platform/kubespray/inventory/k8s-platform
KUBESPRAY_INVENTORY ?= $(KUBESPRAY_INVENTORY_DIR)/inventory.ini
KUBESPRAY_PLAYBOOK ?= $(KUBESPRAY_DIR)/cluster.yml
KUBESPRAY_ANSIBLE_PLAYBOOK ?= $(KUBESPRAY_DIR)/.venv/bin/ansible-playbook

# Node-tuning configuration
TUNING_DIR := $(ROOT)/kernel-tuning
TUNING_VENV := $(TUNING_DIR)/.venv
TUNING_ANSIBLE := $(TUNING_VENV)/bin/ansible-playbook
TUNING_INVENTORY := $(TUNING_DIR)/inventory.ini
TUNING_PLAYBOOK := $(TUNING_DIR)/playbooks/node-tuning.yml

# Kubernetes application
APP_OVERLAY := $(ROOT)/k8s/app/overlays/demo

.PHONY: help test failure-test validate-manifests terraform-validate \
        ansible-check kubespray-check kubespray-deploy \
        build deploy destroy recreate

help:
	@echo "Available targets:"
	@echo "  make test                 Run the platform acceptance tests"
	@echo "  make failure-test         Run the failure exercise"
	@echo "  make validate-manifests   Validate rendered Kubernetes manifests"
	@echo "  make terraform-validate   Validate Terraform configuration"
	@echo "  make ansible-check        Check node-tuning Ansible syntax"
	@echo "  make kubespray-check      Check Kubespray prerequisites"
	@echo "  make kubespray-deploy     Install/configure Kubernetes with Kubespray"
	@echo "  make build                Run configuration and prerequisite checks"
	@echo "  make deploy               Provision VMs, install Kubernetes, tune nodes, deploy app"
	@echo "  make destroy              Destroy the Terraform-managed VMs"
	@echo "  make recreate             Destroy and redeploy the platform"

test:
	@$(ROOT)/scripts/acceptance-test.sh

failure-test:
	@$(ROOT)/scripts/failure-test.sh

validate-manifests:
	@$(KUBECTL) kustomize "$(APP_OVERLAY)" > /tmp/k8s-platform-rendered.yaml
	@$(KUBECTL) apply --dry-run=client -f /tmp/k8s-platform-rendered.yaml >/dev/null
	@echo "PASS: Kubernetes manifests render and pass client-side validation"

terraform-validate:
	@cd "$(ROOT)/k8s-platform/terraform" && \
		terraform init -backend=false && \
		terraform validate

ansible-check:
	@test -x "$(TUNING_ANSIBLE)" || \
		(echo "ERROR: Node-tuning Ansible virtualenv not found: $(TUNING_VENV)"; \
		echo "Create the virtualenv and install the project's Ansible requirements first."; \
		exit 1)
	@test -f "$(TUNING_INVENTORY)" || \
		(echo "ERROR: Node-tuning inventory not found: $(TUNING_INVENTORY)"; exit 1)
	@test -f "$(TUNING_PLAYBOOK)" || \
		(echo "ERROR: Node-tuning playbook not found: $(TUNING_PLAYBOOK)"; exit 1)
	@source "$(TUNING_VENV)/bin/activate" && \
		"$(TUNING_ANSIBLE)" -i "$(TUNING_INVENTORY)" \
		"$(TUNING_PLAYBOOK)" --syntax-check

kubespray-check:
	@test -f "$(KUBESPRAY_PLAYBOOK)" || \
		(echo "ERROR: Kubespray checkout/playbook not found: $(KUBESPRAY_PLAYBOOK)"; \
		echo "Clone Kubespray and install its Python requirements before deploying."; \
		exit 1)
	@test -f "$(KUBESPRAY_INVENTORY)" || \
		(echo "ERROR: Kubespray inventory not found: $(KUBESPRAY_INVENTORY)"; \
		echo "Set KUBESPRAY_INVENTORY to your inventory hosts.yaml path."; \
		exit 1)
	@test -x "$(KUBESPRAY_ANSIBLE_PLAYBOOK)" || \
		(command -v ansible-playbook >/dev/null 2>&1) || \
		(echo "ERROR: ansible-playbook not found for Kubespray."; \
		echo "Install Kubespray's Python requirements in its virtualenv."; \
		exit 1)
	@echo "PASS: Kubespray checkout, inventory, and Ansible executable found"

kubespray-deploy: kubespray-check
	@echo "Installing/configuring Kubernetes with Kubespray..."
	@if [[ -x "$(KUBESPRAY_ANSIBLE_PLAYBOOK)" ]]; then \
		ANSIBLE="$(KUBESPRAY_ANSIBLE_PLAYBOOK)"; \
	else \
		ANSIBLE="$$(command -v ansible-playbook)"; \
	fi; \
	cd "$(KUBESPRAY_DIR)" && \
		"$$ANSIBLE" -i "$(KUBESPRAY_INVENTORY)" \
		"$(KUBESPRAY_PLAYBOOK)" -b

build: validate-manifests terraform-validate ansible-check kubespray-check
	@echo "PASS: build checks completed"

deploy:
	@echo "Step 1/4: Provisioning VMs with Terraform..."
	@cd "$(ROOT)/k8s-platform/terraform" && terraform apply
	@echo "Step 2/4: Installing/configuring Kubernetes with Kubespray..."
	@$(MAKE) kubespray-deploy
	@echo "Step 3/4: Applying node tuning..."
	@source "$(TUNING_VENV)/bin/activate" && \
		"$(TUNING_ANSIBLE)" -i "$(TUNING_INVENTORY)" \
		"$(TUNING_PLAYBOOK)"
	@echo "Step 4/4: Deploying the demo application..."
	@$(KUBECTL) apply -k "$(APP_OVERLAY)"
	@echo "Deployment commands completed"

destroy:
	@cd "$(ROOT)/k8s-platform/terraform" && terraform destroy

recreate:
	@$(MAKE) destroy
	@$(MAKE) deploy
```