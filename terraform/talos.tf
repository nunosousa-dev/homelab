resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/iscsi-tools",
          "siderolabs/util-linux-tools",
          "siderolabs/qemu-guest-agent",
          "siderolabs/nfs-utils",
          "siderolabs/i915",
        ]
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}

locals {
  talos_install_image = "factory.talos.dev/installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"
  talos_iso_filename  = "talos-nocloud-amd64-${var.talos_version}.iso"
  talos_iso           = "${var.iso_storage}:iso/${local.talos_iso_filename}"
}

resource "null_resource" "talos_iso_download" {
  triggers = {
    schematic_id  = talos_image_factory_schematic.this.id
    talos_version = var.talos_version
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/download-talos-iso.sh"

    environment = {
      PM_API_URL       = var.pm_api_url
      PM_TOKEN_ID      = var.pm_api_token_id
      PM_TOKEN_SECRET  = var.pm_api_token_secret
      NODE             = var.proxmox_node
      STORAGE          = var.iso_storage
      FILENAME         = local.talos_iso_filename
      ISO_URL          = data.talos_image_factory_urls.this.urls.iso
    }
  }
}

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = "https://${var.control_plane_ips[0]}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = "https://${var.control_plane_ips[0]}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

resource "talos_machine_configuration_apply" "controlplane" {
  count = length(var.control_plane_ips)

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = var.control_plane_ips[count.index]

  depends_on = [proxmox_vm_qemu.control-plane]

  config_patches = [
    yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        }
        network = {
          nameservers = var.nameservers
          interfaces = [
            {
              deviceSelector = {
                driver = "virtio_net"
              }
              dhcp      = false
              addresses = ["${var.control_plane_ips[count.index]}/${var.cidr_prefix}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
            }
          ]
        }
        install = {
          disk  = "/dev/sda"
          image = local.talos_install_image
        }
      }
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
        apiServer = {
          certSANs = var.control_plane_ips
        }
        extraManifests = [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml",
          "https://github.com/kubernetes-sigs/metrics-server/releases/download/${var.metrics_server_version}/components.yaml"
        ]
        allowSchedulingOnControlPlanes = false
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  count = length(var.worker_ips)

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = var.worker_ips[count.index]

  depends_on = [proxmox_vm_qemu.worker]

  config_patches = [
    yamlencode({
      machine = {
        nodeLabels = {
          "homelab/node-type" = "vm"
        }
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        }
        network = {
          nameservers = var.nameservers
          interfaces = [
            {
              deviceSelector = {
                driver = "virtio_net"
              }
              dhcp      = false
              addresses = ["${var.worker_ips[count.index]}/${var.cidr_prefix}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
            }
          ]
        }
        install = {
          disk  = "/dev/sda"
          image = local.talos_install_image
        }
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "rpi_worker" {
  count = length(var.rpi_workers)

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = var.rpi_workers[count.index].ip

  config_patches = [
    yamlencode({
      machine = {
        nodeLabels = {
          "homelab/node-type" = "rpi"
        }
        nodeTaints = {
          "homelab/node-type" = "rpi:NoExecute"
        }
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
            container-log-max-size     = "5Mi"
            container-log-max-files    = "2"
            image-gc-high-threshold    = "70"
            image-gc-low-threshold     = "50"
          }
        }
        network = {
          nameservers = var.nameservers
          interfaces = [
            {
              deviceSelector = {
                driver = "bcmgenet"
              }
              dhcp      = false
              addresses = ["${var.rpi_workers[count.index].ip}/${var.cidr_prefix}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
            }
          ]
        }
        install = {
          disk  = "/dev/mmcblk0"
          image = "factory.talos.dev/installer/${var.rpi_workers[count.index].schematic_id}:${var.talos_version}"
        }
        sysctls = {
          "vm.dirty_writeback_centisecs" = "6000"
          "vm.dirty_ratio"              = "60"
        }
      }
    })
  ]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = var.control_plane_ips
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_ips[0]

  depends_on = [talos_machine_configuration_apply.controlplane]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_ips[0]

  depends_on = [talos_machine_bootstrap.this]
}
