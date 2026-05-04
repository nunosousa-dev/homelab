# Homelab - K8s cluster using Talos Linux on Proxmox

## Architecture

| VM | CPU | RAM | Disk | Role |
|---|---|---|---|---|
| Control Plane | 4 cores | 4GB | 20G | etcd, API server, scheduler, workloads |
| Worker | 4 cores | 12GB | 10G | Heavy workloads (Immich, Prometheus, etc.) |
| TrueNAS *(manual)* | - | ~10GB | - | NAS / storage backend |

### Cluster Network

| Component | IP |
|---|---|
| Gateway | 10.0.0.1 |
| Control Plane VIP | 10.0.0.20 |
| Control Plane Node | 10.0.0.21 |
| Worker Node | 10.0.0.30 |

## Prerequisites

1. Proxmox VE with API token configured (see [Troubleshooting](#troubleshooting))
2. Talos Linux nocloud ISO uploaded to Proxmox storage (`truenas_data:iso/nocloud-amd64.iso`)
3. Terraform installed locally

## Deploy

### 1. Initialize Terraform
```bash
terraform init
```

### 2. Review the plan
```bash
terraform plan -var-file="inputs.tfvars"
```

### 3. Apply
```bash
terraform apply -var-file="inputs.tfvars"
```

This will:
- Create Proxmox VMs (control plane + worker)
- Generate Talos machine secrets
- Apply Talos machine configuration to all nodes
- Bootstrap the cluster
- Retrieve kubeconfig

### 4. Get cluster credentials
```bash
terraform output -raw kubeconfig > ~/.kube/config
terraform output -raw talosconfig > ~/.talos/config
```

### 5. Verify
```bash
kubectl get nodes
talosctl health
```

## Day 2 Operations

### Check cluster status
```bash
talosctl health
kubectl get nodes -o wide
```

### Reset Talos cluster (DANGER ZONE)

Reset nodes without re-creating Proxmox VMs:

```bash
talosctl reset --graceful=false --reboot --nodes 10.0.0.21
talosctl reset --graceful=false --reboot --nodes 10.0.0.30
```

After reset, delete Terraform state and re-apply:
```bash
rm terraform.tfstate terraform.tfstate.backup
terraform apply -var-file="inputs.tfvars"
```

### Destroy everything
```bash
terraform destroy -var-file="inputs.tfvars"
```

## Configuration

All configuration is managed via variable files:

- `inputs.tfvars` — cluster settings (IPs, names, versions)
- `credentials.auto.tfvars` — Proxmox API credentials (gitignored)

### Scaling

Add nodes by extending the IP lists in `inputs.tfvars`:
```terraform
control_plane_ips = ["10.0.0.21", "10.0.0.22", "10.0.0.23"]
worker_ips        = ["10.0.0.30", "10.0.0.31"]
```

## Troubleshooting

### Fix PVE API access
```bash
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add terraform-prov@pve
pveum aclmod / -user terraform-prov@pve -role TerraformProv
pveum user token add terraform-prov@pve api
pveum aclmod / --tokens 'terraform-prov@pve!api' -role TerraformProv
```

### Talos install disk not found
Ensure `scsihw = "virtio-scsi-single"` is set on VMs. The disk appears as `/dev/sda`.

### Update Talos version
1. Generate a new image at [factory.talos.dev](https://factory.talos.dev) with desired extensions
2. Update `talos_version` and `talos_install_image` in `inputs.tfvars`
3. Upload new ISO to Proxmox and update `talos_iso` if needed
4. Run `terraform apply -var-file="inputs.tfvars"`

