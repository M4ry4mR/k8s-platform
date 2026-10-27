terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

 
# ---------------------------------------------------------------
# Root disks (copy-on-write on top of the Ubuntu cloud image)
# ---------------------------------------------------------------
resource "libvirt_volume" "node_disk" {
  for_each = var.nodes

  name = "${each.key}.qcow2"
  pool = "default"

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = var.ubuntu_image

    format = {
      type = "qcow2"
    }
  }

  capacity = each.value.disk
}

# ---------------------------------------------------------------
# cloud-init: user, SSH key, hostname, static IP
# ---------------------------------------------------------------
resource "libvirt_cloudinit_disk" "init" {
  for_each = var.nodes

  name = "${each.key}-init"

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  })

  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })

  network_config = yamlencode({
    version = 2
    ethernets = {
      nic0 = {
        match       = { name = "en*" }
        dhcp4       = false
        addresses   = ["${each.value.ip}/24"]
        routes      = [{ to = "default", via = var.gateway }]
        nameservers = { addresses = var.dns }
      }
    }
  })
}

# Upload the seed ISO into the pool so it can be attached as a CD-ROM
resource "libvirt_volume" "cloudinit" {
  for_each = var.nodes

  name = "${each.key}-cloudinit.iso"
  pool = "default"

  create = {
    content = {
      url = libvirt_cloudinit_disk.init[each.key].path
    }
  }
}

# ---------------------------------------------------------------
# VMs
# ---------------------------------------------------------------
resource "libvirt_domain" "node" {
  for_each = var.nodes

  name = each.key
  type = "kvm"

  memory      = each.value.memory
  memory_unit = "MiB"

  vcpu = each.value.vcpu

  cpu = {
    mode = "host-passthrough"
  }

  running = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"

    boot_devices = [
      {
        dev = "hd"
      }
    ]
  }

  devices = {
    disks = [
      # Root disk
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }

        source = {
          file = {
            file = libvirt_volume.node_disk[each.key].path
          }
        }

        target = {
          dev = "vda"
          bus = "virtio"
        }
      },

      # cloud-init seed ISO
      {
        device = "cdrom"

        source = {
          volume = {
            pool   = libvirt_volume.cloudinit[each.key].pool
            volume = libvirt_volume.cloudinit[each.key].name
          }
        }

        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        model = {
          type = "virtio"
        }

        source = {
          network = {
            network = "default"
          }
        }
      }
    ]
  }
}