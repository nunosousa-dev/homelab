data "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/iscsi-tools",
          "siderolabs/util-linux-tools",
          "siderolabs/qemu-guest-agent",
          "siderolabs/nfs-mount",
        ]
      }
    }
  })
}

locals {
  talos_install_image = "factory.talos.dev/installer/${data.talos_image_factory_schematic.this.id}:${var.talos_version}"
}

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
}

resource "talos_machine_configuration_apply" "controlplane" {
  count = length(var.control_plane_ips)

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = var.control_plane_ips[count.index]

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
              interface = "eth0"
              dhcp      = false
              addresses = ["${var.control_plane_ips[count.index]}/${var.cidr_prefix}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
              vip = {
                ip = var.control_plane_vip
              }
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
          certSANs = concat(
            [var.control_plane_vip],
            var.control_plane_ips
          )
        }
        extraManifests = [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml",
          "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
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
              interface = "eth0"
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
