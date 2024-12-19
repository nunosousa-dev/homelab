resource "proxmox_vm_qemu" "control-plane" {
  vmid = 200
  name = "k8s-control-plane"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=10.0.100.100/16,gw=10.0.0.1"

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
  vmid = 201
  name = "k8s-node-1"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=10.0.100.101/16,gw=10.0.0.1"

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
  vmid = 202
  name = "k8s-node-2"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=10.0.100.102/16,gw=10.0.0.1"

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
