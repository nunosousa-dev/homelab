# Homelab - K8s cluster using Talos Linux on Proxmox

## Table of Contents

- [Homelab - K8s cluster using Talos Linux on Proxmox](#homelab---k8s-cluster-using-talos-linux-on-proxmox)
  - [Table of Contents](#table-of-contents)
  - [Architecture](#architecture)
    - [Cluster Network](#cluster-network)
  - [Prerequisites](#prerequisites)
  - [Deploy](#deploy)
    - [1. Initialize Terraform](#1-initialize-terraform)
    - [2. Review the plan](#2-review-the-plan)
    - [3. Apply](#3-apply)
    - [4. Get cluster credentials](#4-get-cluster-credentials)
    - [5. Verify](#5-verify)
  - [Kubernetes Bootstrap](#kubernetes-bootstrap)
    - [6. Install Cilium (CNI)](#6-install-cilium-cni)
    - [7. Install Sealed Secrets controller](#7-install-sealed-secrets-controller)
    - [8. Seal all secrets](#8-seal-all-secrets)
      - [Back up the master decryption key](#back-up-the-master-decryption-key)
    - [9. Build Helm chart dependencies](#9-build-helm-chart-dependencies)
    - [10. Install ArgoCD](#10-install-argocd)
    - [11. Apply the App of Apps](#11-apply-the-app-of-apps)
  - [GitOps Structure](#gitops-structure)
  - [Storage](#storage)
    - [NFS](#nfs)
    - [iSCSI](#iscsi)
    - [Secrets](#secrets)
  - [GitOps Structure](#gitops-structure-1)
  - [Day 2 Operations](#day-2-operations)
    - [Check cluster status](#check-cluster-status)
    - [Check ArgoCD sync status](#check-argocd-sync-status)
    - [Rotate secrets](#rotate-secrets)
    - [Upgrade bootstrap components](#upgrade-bootstrap-components)
    - [Node maintenance (cordon/drain)](#node-maintenance-cordondrain)
    - [Reset Talos cluster (DANGER ZONE)](#reset-talos-cluster-danger-zone)
    - [Destroy everything](#destroy-everything)
  - [Configuration](#configuration)
    - [Scaling](#scaling)
  - [Troubleshooting](#troubleshooting)
    - [Fix PVE API access](#fix-pve-api-access)
    - [Services unreachable via LoadBalancer IP (`ERR_ADDRESS_UNREACHABLE`)](#services-unreachable-via-loadbalancer-ip-err_address_unreachable)
    - [Talos install disk not found](#talos-install-disk-not-found)
    - [Upgrade Talos nodes after changing factory image](#upgrade-talos-nodes-after-changing-factory-image)
    - [Update Talos version](#update-talos-version)

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

> All Terraform commands must be run from the `terraform/` directory:
> ```bash
> cd terraform/
> ```

### 1. Initialize Terraform
```bash
cd terraform/
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
cd terraform/
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

Apply Cilium L2 announcement policy and IP pool:
```bash
kubectl apply -f kubernetes/bootstrap/cilium/lan-pool.yaml
kubectl apply -f kubernetes/bootstrap/cilium/l2-announce.yaml
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
GITHUB_APP_ID=<id> \
GITHUB_APP_INSTALLATION_ID=<id> \
GITHUB_APP_PRIVATE_KEY_FILE=<path-to-pem> \
./seal-secrets.sh
```

No keys are stored in the script — it is committed to Git and safe to share. Values are passed at runtime only.

This seals and writes all five secrets:
- `kubernetes/apps/democratic-csi/templates/truenas-nfs-config.yaml`
- `kubernetes/apps/democratic-csi/templates/truenas-iscsi-config.yaml`
- `kubernetes/apps/cert-manager/templates/cloudflare-secret.yaml`
- `kubernetes/apps/immich/templates/immich-secret.yaml`
- `kubernetes/bootstrap/argocd/repo-secret.yaml` (GitHub App credentials for ArgoCD)

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

## Storage

Storage is provided by [democratic-csi](https://github.com/democratic-csi/democratic-csi) talking to TrueNAS via its API. Two drivers are deployed in the `democratic-csi` namespace, each backed by its own `SealedSecret` holding the TrueNAS API key and connection details.

| Driver | CSI name | Storage class (Retain) | Storage class (Delete) | Use case |
|---|---|---|---|---|
| NFS | `org.democratic-csi.truenas-nfs` | `truenas-nfs-retain` | `truenas-nfs` | Shared / `ReadWriteMany` volumes |
| iSCSI | `org.democratic-csi.truenas-iscsi` | `truenas-iscsi-retain` | *(none)* | Block / `ReadWriteOnce` volumes |

### NFS

- NFS 4.1, `noatime` mount option
- Volumes are provisioned dynamically via the TrueNAS API
- Config secret: `truenas-nfs-config` (sealed)

### iSCSI

- `ext4` filesystem, block device exposed to the node via iSCSI
- Uses `nsenter` strategy to call `iscsiadm` on the host (`hostPID: true`)
- Config secret: `truenas-iscsi-config` (sealed)

### Secrets

Both drivers read their TrueNAS API key and endpoint from a sealed secret that is decrypted by the Sealed Secrets controller at runtime. The secrets are generated by `seal-secrets.sh` and committed as encrypted `SealedSecret` manifests — never in plaintext.

## GitOps Structure

All cluster state lives under `kubernetes/`:

```
kubernetes/
  bootstrap/          # One-time manual Helm installs (Cilium, ArgoCD)
    cilium/
    argocd/
  apps/               # GitOps-managed umbrella Helm charts
    _apps.yaml        # App of Apps — apply once to seed ArgoCD
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
kubectl get pods -A | grep -Ev 'Running|Completed'
```

### Check ArgoCD sync status
```bash
kubectl get applications -n argocd
```

Access the ArgoCD UI at [argocd.local.nunosousa.dev](https://argocd.local.nunosousa.dev).

Retrieve the initial admin password:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

### Rotate secrets

Re-run `seal-secrets.sh` with updated values, then commit and push — ArgoCD will detect the change and re-sync affected apps automatically:
```bash
TRUENAS_API_KEY=<key> \
CLOUDFLARE_API_TOKEN=<token> \
IMMICH_DB_PASSWORD=<pw> \
IMMICH_SECRET_KEY=<key> \
GITHUB_APP_ID=<id> \
GITHUB_APP_INSTALLATION_ID=<id> \
GITHUB_APP_PRIVATE_KEY_FILE=<path-to-pem> \
./seal-secrets.sh

git add kubernetes/apps/ kubernetes/bootstrap/argocd/repo-secret.yaml
git commit -m "chore: rotate sealed secrets"
git push
```

### Upgrade bootstrap components

Cilium, ArgoCD, and Sealed Secrets are **not** managed by ArgoCD and must be upgraded manually:
```bash
helm repo update

# Cilium
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  -f kubernetes/bootstrap/cilium/values.yaml

# Sealed Secrets
helm upgrade sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller

# ArgoCD
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  -f kubernetes/bootstrap/argocd/values.yaml
```

> **Note:** If Sealed Secrets is reinstalled (not just upgraded), back up the master key first and restore it after reinstall — otherwise existing sealed secrets cannot be decrypted.

### Node maintenance (cordon/drain)

Before performing maintenance on a node:
```bash
# Evict workloads and prevent new scheduling
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# ... perform maintenance ...

# Restore scheduling
kubectl uncordon <node>
```

### Reset Talos cluster (DANGER ZONE)

Reset nodes without re-creating Proxmox VMs:

```bash
talosctl reset --graceful=false --reboot --nodes 10.0.0.21
talosctl reset --graceful=false --reboot --nodes 10.0.0.30
```

After reset, delete Terraform state and re-apply:
```bash
cd terraform/
rm terraform.tfstate terraform.tfstate.backup
terraform apply -var-file="inputs.tfvars"
```

Then re-run the full [Kubernetes Bootstrap](#kubernetes-bootstrap) sequence from step 6.

### Destroy everything
```bash
cd terraform/
terraform destroy -var-file="inputs.tfvars"
```

## Configuration

All configuration is managed via variable files:

- `terraform/inputs.tfvars` — cluster settings (IPs, names, versions)
- `terraform/credentials.auto.tfvars` — Proxmox API credentials (gitignored)

### Scaling

Add nodes by extending the IP lists in `terraform/inputs.tfvars`:
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

### Services unreachable via LoadBalancer IP (`ERR_ADDRESS_UNREACHABLE`)
Ensure `loadBalancerIPs: true` is set in `kubernetes/bootstrap/cilium/l2-announce.yaml`. Without it, Cilium won't announce assigned IPs over ARP on the LAN.

### Talos install disk not found
Ensure `scsihw = "virtio-scsi-single"` is set on VMs. The disk appears as `/dev/sda`.

### Upgrade Talos nodes after changing factory image
When `talos_install_image` in `terraform/inputs.tfvars` is updated (e.g. to add system extensions), nodes must be upgraded:
```bash
# Apply new machine config first
cd terraform/ && terraform apply -var-file="inputs.tfvars"

# Upgrade each node (uses the new installer image from the updated machine config)
talosctl upgrade --nodes 10.0.0.21 --image factory.talos.dev/nocloud-installer/$(grep talos_install_image terraform/inputs.tfvars | grep -oP '(?<=nocloud-installer/)[^:]+'):v1.13.0
talosctl upgrade --nodes 10.0.0.30 --image factory.talos.dev/nocloud-installer/$(grep talos_install_image terraform/inputs.tfvars | grep -oP '(?<=nocloud-installer/)[^:]+'):v1.13.0
```

### Update Talos version
1. Generate a new image at [factory.talos.dev](https://factory.talos.dev) with desired extensions
2. Update `talos_version` and `talos_install_image` in `terraform/inputs.tfvars`
3. Upload new ISO to Proxmox and update `talos_iso` if needed
4. Run `cd terraform && terraform apply -var-file="inputs.tfvars"`

