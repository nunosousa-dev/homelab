resource "proxmox_vm_qemu" "control-plane-1" {
  vmid = 200
  name = "k8s-control-plane-1"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.control_plane1_cidr},gw=${var.gateway}"

  cores  = "2"
  memory = "2048"

  network {
    id        = 0
    bridge    = "vmbr0"
    firewall  = false
    link_down = false
    model     = "virtio"
  }

  agent = 1

  disks {
    ide {
      ide1 {
        disk {
          size    = "20G"
          storage = "local-lvm"
        }
      }
      ide2 {
        cdrom {
          iso = "local:iso/nocloud-amd64.iso"
        }
      }
      ide3 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }
}

resource "proxmox_vm_qemu" "control-plane-2" {
  vmid = 201
  name = "k8s-control-plane-2"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.control_plane2_cidr},gw=${var.gateway}"

  cores  = "2"
  memory = "2048"

  network {
    id        = 0
    bridge    = "vmbr0"
    firewall  = false
    link_down = false
    model     = "virtio"
  }

  agent = 1

  disks {
    ide {
      ide1 {
        disk {
          size    = "20G"
          storage = "local-lvm"
        }
      }
      ide2 {
        cdrom {
          iso = "local:iso/nocloud-amd64.iso"
        }
      }
      ide3 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }
}

resource "proxmox_vm_qemu" "control-plane-3" {
  vmid = 202
  name = "k8s-control-plane-3"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.control_plane3_cidr}/16,gw=${var.gateway}"

  cores  = "2"
  memory = "2048"

  network {
    id        = 0
    bridge    = "vmbr0"
    firewall  = false
    link_down = false
    model     = "virtio"
  }

  agent = 1

  disks {
    ide {
      ide1 {
        disk {
          size    = "20G"
          storage = "local-lvm"
        }
      }
      ide2 {
        cdrom {
          iso = "local:iso/nocloud-amd64.iso"
        }
      }
      ide3 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }
}

resource "proxmox_vm_qemu" "node-1" {
  vmid = 205
  name = "k8s-node-1"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.node1_cidr},gw=${var.gateway}"

  cores  = "2"
  memory = "4096"

  network {
    id        = 0
    bridge    = "vmbr0"
    firewall  = false
    link_down = false
    model     = "virtio"
  }

  agent = 1

  disks {
    ide {
      ide1 {
        disk {
          size    = "10G"
          storage = "local-lvm"
        }
      }
      ide2 {
        cdrom {
          iso = "local:iso/nocloud-amd64.iso"
        }
      }
      ide3 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }
}

resource "proxmox_vm_qemu" "node-2" {
  vmid = 206
  name = "k8s-node-2"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.node2_cidr},gw=${var.gateway}"

  cores  = "2"
  memory = "4096"

  network {
    id        = 0
    bridge    = "vmbr0"
    firewall  = false
    link_down = false
    model     = "virtio"
  }

  agent = 1

  disks {
    ide {
      ide1 {
        disk {
          size    = "10G"
          storage = "local-lvm"
        }
      }
      ide2 {
        cdrom {
          iso = "local:iso/nocloud-amd64.iso"
        }
      }
      ide3 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }
}
