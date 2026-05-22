gateway      = "10.0.0.1"
proxmox_node = "supernova"

control_plane_ips = ["10.0.0.21"]
worker_ips        = ["10.0.0.25"]

cluster_name       = "homelab"
talos_version      = "v1.13.2"
kubernetes_version = "1.35.5"

nameservers = ["10.0.0.10", "10.0.0.11"]

metrics_server_version = "v0.8.1"

rpi_workers = [
  { ip = "10.0.0.26", schematic_id = "cb30f8560e74c2233fc5e533467f802d35591fbf38336e67fb1751c2c98ceae9" },
  { ip = "10.0.0.27", schematic_id = "36b0689bafca8300fd1062f47fcfcec5df0563cf3513c3ecacc2a2b110900bb1" },
]
