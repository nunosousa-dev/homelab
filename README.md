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

## Kubernetes Bootstrap

After the cluster is running, bootstrap the core infrastructure layer. These steps are **one-time manual installs** — ArgoCD takes over everything afterwards.

### 6. Install Cilium (CNI)
```bash
helm repo add cilium https://helm.cilium.io
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  -f kubernetes/bootstrap/cilium/values.yaml
```

### 7. Install Sealed Secrets controller
```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller
```

Install the `kubeseal` CLI:
```bash
brew install kubeseal   # macOS
```

### 8. Seal all secrets

Sealed Secrets encrypts secrets against your specific cluster. A helper script `seal-secrets.sh` automates all sealing in one step. **The script is gitignored — never commit it with real values filled in.**

Pass values from your password manager as environment variables:
```bash
TRUENAS_API_KEY=<key> \
CLOUDFLARE_API_TOKEN=<token> \
IMMICH_DB_PASSWORD=<pw> \
IMMICH_SECRET_KEY=<key> \
./seal-secrets.sh
```

No keys are stored in the script — it is committed to Git and safe to share. Values are passed at runtime only.

This seals and writes all four secrets:
- `kubernetes/apps/democratic-csi/templates/truenas-nfs-config.yaml`
- `kubernetes/apps/democratic-csi/templates/truenas-iscsi-config.yaml`
- `kubernetes/apps/cert-manager/templates/cloudflare-secret.yaml`
- `kubernetes/apps/immich/templates/immich-secret.yaml`

Then commit the updated sealed secret files (safe to push — encrypted):
```bash
git add kubernetes/apps/
git commit -m "chore: rotate sealed secrets"
```

#### Back up the master decryption key

Store this outside Git (password manager or encrypted vault). Without it you cannot re-seal after a cluster reset.
```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key.yaml
# sealed-secrets-master-key.yaml is gitignored — store it somewhere safe
```

### 9. Build Helm chart dependencies

Charts with upstream dependencies need a `charts/` directory before ArgoCD can sync them:
```bash
helm dependency update kubernetes/apps/cert-manager
helm dependency update kubernetes/apps/traefik
helm dependency update kubernetes/apps/reflector
helm dependency update kubernetes/apps/democratic-csi
helm dependency update kubernetes/apps/monitoring
```

### 10. Install ArgoCD
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f kubernetes/bootstrap/argocd/values.yaml
```

Wait for ArgoCD to be ready:
```bash
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=120s
```

### 11. Apply the App of Apps

This single manifest registers every application with ArgoCD. After this, ArgoCD owns all further reconciliation.
```bash
kubectl apply -f kubernetes/apps/_apps.yaml
```

Verify all Applications are syncing:
```bash
kubectl get applications -n argocd
```

## GitOps Structure

All cluster state lives under `kubernetes/`:

```
kubernetes/
  bootstrap/          # One-time manual Helm installs (Cilium, ArgoCD)
    cilium/
    argocd/
  apps/               # GitOps-managed umbrella Helm charts
    _apps.yaml        # App of Apps — apply once to seed ArgoCD
    cilium-config/    # LB IP pool + L2 announcement (wave 0)
    cert-manager/     # cert-manager + ClusterIssuer + wildcard cert (wave 0)
    democratic-csi/   # TrueNAS NFS + iSCSI drivers (wave 0)
    traefik/          # Traefik + Gateway API gateway (wave 1)
    reflector/        # Secret reflection across namespaces (wave 1)
    monitoring/       # kube-prometheus-stack + Mimir (wave 2)
    immich/           # Immich photo server (wave 2)
    actual-budget/    # Actual Budget finance app (wave 2)
```

Sync waves control deployment order: wave 0 (infra) → wave 1 (ingress) → wave 2 (apps).

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

### Upgrade Talos nodes after changing factory image
When `talos_install_image` in `inputs.tfvars` is updated (e.g. to add system extensions), nodes must be upgraded:
```bash
# Apply new machine config first
terraform apply -var-file="inputs.tfvars"

# Upgrade each node (uses the new installer image from the updated machine config)
talosctl upgrade --nodes 10.0.0.21 --image factory.talos.dev/nocloud-installer/$(grep talos_install_image inputs.tfvars | grep -oP '(?<=nocloud-installer/)[^:]+'):v1.13.0
talosctl upgrade --nodes 10.0.0.30 --image factory.talos.dev/nocloud-installer/$(grep talos_install_image inputs.tfvars | grep -oP '(?<=nocloud-installer/)[^:]+'):v1.13.0
```

### Update Talos version
1. Generate a new image at [factory.talos.dev](https://factory.talos.dev) with desired extensions
2. Update `talos_version` and `talos_install_image` in `inputs.tfvars`
3. Upload new ISO to Proxmox and update `talos_iso` if needed
4. Run `terraform apply -var-file="inputs.tfvars"`

