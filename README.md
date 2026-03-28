# K8s cluster using Talos Linux

### Cluster Network

#### Control plane nodes:

Starting IP: 10.0.100.100/16 <br>
Added to certSANs for API server certificate <br>
Updated cluster endpoint to use this IP <br>

#### Worker nodes:

Starting IP: 10.0.101.100/16

#### Added network configuration for both node types:

Interface configuration (assuming eth0)
Default route (assuming gateway is 10.0.0.1)

### Generate the base configuration
```bash
talosctl gen config casinha-cluster https://10.0.0.20:6443 \
    --output-dir cluster-config \
    --install-image factory.talos.dev/nocloud-installer/07fe29582dc9bf9c1b8bf07294b8c62e6a0fe231c7a8107d3cf52f38486436c9:v1.12.6 \
    --force
```

### Control Plane
```bash
talosctl apply-config --insecure --nodes 10.0.0.21 \
  --file cluster-config/controlplane.yaml \
  --config-patch @cluster-config/patches/controlplane1.yaml
```

### Worker Node
```bash
talosctl apply-config --insecure --nodes 10.0.0.30 \
  --file cluster-config/worker.yaml \
  --config-patch @cluster-config/patches/worker1.yaml
```

### Configure talosctl to talk to our cluster
```bash
export TALOSCONFIG="cluster-config/talosconfig"
talosctl config endpoint 10.0.0.21 10.0.0.22 10.0.0.23
```
```bash
talosctl config node 10.0.0.30
```

### Bootstrap cluster (we just do it for the first control plane)
```bash
talosctl --nodes 10.0.0.21 bootstrap
```

### Check the cluster status
```bash
talosctl health
```

### Generate kubeconfig and copy to kube folder
```bash
talosctl kubeconfig cluster-config/
```
```bash
cp cluster-config/kubeconfig ~/.kube/config
```

### Reset Talos cluster (DANGER ZONE)

This is helpful because we don't need to re-create Proxmox VMs, just reset Talos Linux :)

#### Reset control planes
```bash
talosctl reset --graceful=false --reboot --nodes 10.0.100.100,10.0.100.101,10.0.100.102
```

#### Reset worker nodes
```bash
talosctl reset --graceful=false --reboot --nodes 10.0.101.100,10.0.101.101
```

## Troubleshooting
### Fix PVE API access
```bash
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add terraform-prov@pve
pveum aclmod / -user terraform-prov@pve -role TerraformProv # Apply permission to the user
pveum user token add terraform-prov@pve api
pveum aclmod / --tokens 'terraform-prov@pve!api' -role TerraformProv # Apply permission to the token
```