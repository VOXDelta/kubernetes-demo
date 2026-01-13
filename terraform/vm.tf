variable "cluster_nodes" {
  description = "K3s cluster node configuration"
  type = map(object({
    ip      = string
    cores   = number
    memory  = number
    storage = string
    role    = string
  }))

  default = {
    "k3s-master-2" = {
      ip      = "10.0.1.2"
      cores   = 2
      memory  = 4096
      storage = "good"
      role    = "master"
    },
    "k3s-master-3" = {
      ip      = "10.0.1.3"
      cores   = 2
      memory  = 4096
      storage = "dying"
      role    = "master"
    },
    "k3s-worker-3" = {
      ip      = "10.0.1.10"
      cores   = 2
      memory  = 2048
      storage = "dying"
      role    = "worker"
    },
    "k3s-worker-4" = {
      ip      = "10.0.1.11"
      cores   = 2
      memory  = 2048
      storage = "good"
      role    = "worker"
    },
    "k3s-worker-5" = {
      ip      = "10.0.1.12"
      cores   = 2
      memory  = 2048
      storage = "good"
      role    = "worker"
    }
  }

}

resource "proxmox_vm_qemu" "cluster" {
  for_each = var.cluster_nodes

  # Basics
  name        = each.key
  target_node = "pve"
  clone       = "debian-cloud-template"

  #user
  os_type    = "cloud-init"
  ciuser     = "debian"
  cipassword = "test123"
  ipconfig0  = "ip=${each.value.ip}/24,gw=10.0.1.1"

  # Hardware
  cores  = each.value.cores
  memory = each.value.memory

  # Network
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr1"
  }

  disks {
    scsi {
      scsi0 {
        disk {
          size    = 200
          storage = each.value.storage # ← "good" oder "dying"
        }
      }
    }
  }

  timeouts {
    create = "15m" # Statt default 5m
  }

  # QEMU Agent
  agent                  = 1
  define_connection_info = false

}
