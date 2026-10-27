# Automated Local Kubernetes Platform

Senior DevOps/SRE take-home implementation using:

- Terraform + libvirt for reproducible local VMs
- Kubespray for Kubernetes cluster installation and configuration
- containerd as the container runtime
- Calico for pod networking
- ingress-nginx with host ports for local ingress
- Kustomize for application desired state
- Ansible for node/runtime tuning
- `make test` as the single acceptance command
- `make build` for configuration and prerequisite validation
- `make deploy` for VM provisioning, Kubernetes installation, node tuning, and application deployment

## Status

| Area | Status |
|---|---|
| Multi-node local VMs | **Implemented** |
| Idempotent Kubernetes provisioning | **Implemented through Kubespray** |
| Node/container-runtime tuning | **Implemented** |
| Versioned HTTP application | **Implemented** |
| Ingress, probes, replicas, resources, security context | **Implemented** |
| Basic operational visibility | **Implemented** |
| Failure exercise | **Implemented as a documented/scripted test** |
| Single-command acceptance test | **Implemented** |
| GitLab CI/CD | **Designed, not implemented** |
| Production deployment | **Designed, not implemented** |
| Rollback | **Designed, not implemented** |
| Production monitoring/alerting | **Designed, not implemented** |
| HPA | **Out of scope / design only** |
| Production database | **Out of scope** |

See [`docs/PLATFORM.md`](docs/PLATFORM.md), [`docs/CI-CD.md`](docs/CI-CD.md), and [`docs/OPERATIONS.md`](docs/OPERATIONS.md).

## Prerequisites

The host must provide:

- Ubuntu/Linux with KVM and libvirt configured
- Terraform and the libvirt Terraform provider
- `kubectl`
- SSH access to all Kubernetes VMs
- The Ubuntu cloud image configured in `k8s-platform/terraform/terraform.tfvars`
- A Kubespray checkout with its Python dependencies installed
- A Kubespray inventory configured for the provisioned control-plane and worker VMs
- The node-tuning Ansible virtual environment and inventory

By default, the Makefile expects Kubespray at `~/kubespray` and the project inventory at `k8s-platform/kubespray/inventory/k8s-platform/inventory.ini`. Adjust these paths to match the actual inventory layout.

## Quick start

### 1. Install Kubespray

Clone the Kubespray release used by this project and install its dependencies according to that release's requirements.

For example:

```bash
git clone --branch release-2.29 \
  https://github.com/kubernetes