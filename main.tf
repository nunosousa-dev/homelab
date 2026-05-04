
resource "proxmox_vm_qemu" "control-plane" {
  count = length(var.control_plane_ips)

  vmid = 200 + count.index
  name = "k8s-control-plane-${count.index}"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.control_plane_ips[count.index]}/${var.cidr_prefix},gw=${var.gateway}"

  cpu {
    cores = "4"
  }

  memory = "8192"

  network {
    id        = 0
    bridge    = "vmbr0"
    firewall  = false
    link_down = false
    model     = "virtio"
  }

  disks {
    ide {
      ide1 {
        disk {
          size    = var.control_plane_disk_size
          storage = "local-lvm"
        }
      }
      ide2 {
        cdrom {
          iso = "truenas_data:iso/nocloud-amd64.iso"
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

resource "proxmox_vm_qemu" "worker" {
  count = length(var.worker_ips)

  vmid = 210 + count.index
  name = "k8s-worker-${count.index}"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.worker_ips[count.index]}/${var.cidr_prefix},gw=${var.gateway}"

  cpu {
    cores = "4"
  }

  memory = "8192"

  network {
    id        = 0
    bridge    = "vmbr0"
    firewall  = false
    link_down = false
    model     = "virtio"
  }

  disks {
    ide {
      ide1 {
        disk {
          size    = var.worker_disk_size
          storage = "local-lvm"
        }
      }
      ide2 {
        cdrom {
          iso = "truenas_data:iso/nocloud-amd64.iso"
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
