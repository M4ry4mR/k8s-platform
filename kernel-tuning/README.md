# Kubernetes Node Tuning

This repository is a standalone Ansible role for tuning Kubernetes nodes.
It owns the node-level configuration it changes and does not depend on a
specific cluster installer.

## Scope

The role manages:

- swap state
- chrony configuration
- journald limits
- login-session file descriptor limits
- kernel modules and sysctl settings
- containerd configuration and service limits
- kubelet configuration and service limits
- read-only verification of the effective node state

Environment-specific values are kept in `vars/tuning.yml`.

## Layout

```text
kernel-tuning/
├── inventory.ini
├── vars/
│   └── tuning.yml
├── playbooks/
│   └── node-tuning.yml
└── roles/
    └── kuber_node_tuning/
        ├── defaults/
        ├── handlers/
        ├── tasks/
        └── templates/
```

## Run

```bash
cd ~/kernel-tuning
source .venv/bin/activate

ansible-playbook -i inventory.ini playbooks/node-tuning.yml --syntax-check

# Dry run
ansible-playbook -i inventory.ini playbooks/node-tuning.yml --check --diff

# Apply, one node at a time
ansible-playbook -i inventory.ini playbooks/node-tuning.yml

# Verify only
ansible-playbook -i inventory.ini playbooks/node-tuning.yml --tags verify
```

The role uses the inventory supplied with `-i`; no files need to be copied
into another Ansible project.

## Important

Before applying, set `containerd_version` in `vars/tuning.yml` to the exact
version installed on the target nodes and set `pause_image` to an image
available in your environment.

If the role was previously managing a different configuration layout, run:

```bash
ansible-playbook -i inventory.ini playbooks/node-tuning.yml --tags cleanup
```

Then apply the role again.
