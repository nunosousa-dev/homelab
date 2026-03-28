locals {
  control_plane_ip = split("/", var.control_plane_cidr)[0]
  node1_ip        = split("/", var.node1_cidr)[0]
}

resource "proxmox_vm_qemu" "control-plane" {
  vmid = 200
  name = "k8s-control-plane"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.control_plane_cidr},gw=${var.gateway}"

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

resource "proxmox_vm_qemu" "node-1" {
  vmid = 201
  name = "k8s-node-1"

  target_node = "supernova"

  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.node1_cidr},gw=${var.gateway}"

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

resource "null_resource" "talos_control_plane_init" {
  depends_on = [proxmox_vm_qemu.control-plane]

  provisioner "local-exec" {
    command = <<EOT
talosctl gen config casinha-cluster https://${var.control_plane_vip}:6443 \
  --output-dir cluster-config \
  --install-image factory.talos.dev/nocloud-installer/07fe29582dc9bf9c1b8bf07294b8c62e6a0fe231c7a8107d3cf52f38486436c9:v1.12.6 \
  --force

TALOSCONFIG="${path.module}/cluster-config/talosconfig" talosctl apply-config --insecure --nodes ${local.control_plane_ip} \
  --file cluster-config/controlplane.yaml \
  --config-patch @cluster-config/patches/controlplane.yaml
EOT
  }

  triggers = {
    control_plane_vmid = proxmox_vm_qemu.control-plane.vmid
    control_plane_ip   = local.control_plane_ip
    controlplane_yaml  = filemd5("${path.module}/cluster-config/controlplane.yaml")
    patch_yaml         = filemd5("${path.module}/cluster-config/patches/controlplane.yaml")
  }
}

resource "null_resource" "talos_node1_init" {
  depends_on = [proxmox_vm_qemu.node-1, null_resource.talos_control_plane_init]

  provisioner "local-exec" {
    command = <<EOT
TALOSCONFIG="${path.module}/cluster-config/talosconfig" talosctl apply-config --insecure --nodes ${local.node1_ip} \
  --file cluster-config/worker.yaml \
  --config-patch @cluster-config/patches/worker1.yaml
EOT
  }

  triggers = {
    node_vmid   = proxmox_vm_qemu.node-1.vmid
    node_ip     = local.node1_ip
    worker_yaml = filemd5("${path.module}/cluster-config/worker.yaml")
    patch_yaml  = filemd5("${path.module}/cluster-config/patches/worker1.yaml")
  }
}