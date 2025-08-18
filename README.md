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
talosctl gen config casinha-cluster https://10.0.100.50:6443 \
    --output-dir cluster-config \
    --install-image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.9.3
```

### Control Plane 1
```bash
talosctl apply-config --insecure --nodes 10.0.100.100 \
  --file cluster-config/controlplane.yaml \
  --config-patch @cluster-config/patches/controlplane1.yaml
```

### Control Plane 2
```bash
talosctl apply-config --insecure --nodes 10.0.100.101 \
  --file cluster-config/controlplane.yaml \
  --config-patch @cluster-config/patches/controlplane2.yaml
```

### Control Plane 3
```bash
talosctl apply-config --insecure --nodes 10.0.100.102 \
  --file cluster-config/controlplane.yaml \
  --config-patch @cluster-config/patches/controlplane3.yaml
```

### Worker Node 1
```bash
talosctl apply-config --insecure --nodes 10.0.101.100 \
  --file cluster-config/worker.yaml \
  --config-patch @cluster-config/patches/worker1.yaml
```

### Worker Node 2
```bash
talosctl apply-config --insecure --nodes 10.0.101.101 \
  --file cluster-config/worker.yaml \
  --config-patch @cluster-config/patches/worker2.yaml
```

### Configure talosctl to talk to our cluster
```bash
export TALOSCONFIG="cluster-config/talosconfig"
talosctl config endpoint 10.0.100.100 10.0.100.101 10.0.100.102
```
```bash
talosctl config node 10.0.100.100
```

### Bootstrap cluster (we just do it for the first control plane)
```bash
talosctl --nodes 10.0.100.100 bootstrap
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