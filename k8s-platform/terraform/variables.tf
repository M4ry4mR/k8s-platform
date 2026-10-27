variable "ubuntu_image" {
  description = "Path to the Ubuntu cloud image"
  type        = string
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/k8s-platform.pub"
}

variable "gateway" {
  type    = string
  default = "192.168.122.1"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.1", "1.1.1.1"]
}

variable "nodes" {
  description = "Kubernetes nodes"
  type = map(object({
    vcpu   = number
    memory = number
    disk   = number
    ip     = string
  }))

  default = {
    k8s-cp = {
      vcpu   = 2
      memory = 4096
      disk   = 40 * 1024 * 1024 * 1024
      ip     = "192.168.122.10"
    }
    k8s-worker-1 = {
      vcpu   = 2
      memory = 4096
      disk   = 40 * 1024 * 1024 * 1024
      ip     = "192.168.122.11"
    }
    k8s-worker-2 = {
      vcpu   = 2
      memory = 4096
      disk   = 40 * 1024 * 1024 * 1024
      ip     = "192.168.122.12"
    }
  }
}