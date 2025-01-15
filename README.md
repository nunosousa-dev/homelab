# homelab

This is the main setup for my personal homelab.

## Generate the base configuration
```bash
talosctl gen config talos-cluster https://10.0.100.50:6443 \
    --output-dir cluster-config \
    --install-image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.9.0
```

## Control Plane 1
```bash
talosctl apply-config --insecure --nodes 10.0.100.100 \
  --file cluster-config/controlplane.yaml \
  --config-patch @cluster-config/patches/controlplane1.yaml
```

## Control Plane 2
```bash
talosctl apply-config --insecure --nodes 10.0.100.101 \
  --file cluster-config/controlplane.yaml \
  --config-patch @cluster-config/patches/controlplane2.yaml
```

## Control Plane 3
```bash
talosctl apply-config --insecure --nodes 10.0.100.102 \
  --file cluster-config/controlplane.yaml \
  --config-patch @cluster-config/patches/controlplane3.yaml
```

## Worde Node 1
```bash
talosctl apply-config --insecure --nodes 10.0.101.100 \
  --file cluster-config/worker.yaml \
  --config-patch @cluster-config/patches/worker1.yaml
```

## Worde Node 2
```bash
talosctl apply-config --insecure --nodes 10.0.101.101 \
  --file cluster-config/worker.yaml \
  --config-patch @cluster-config/patches/worker2.yaml
```

## Bootstrap cluster (we just do it for the first control plane, it will automate others)
```bash
talosctl --nodes 10.0.100.100 bootstrap
```

## Configure talosctl to talk to our cluster
```bash
talosctl config endpoint 10.0.100.100 10.0.100.101 10.0.100.102
```
```bash
talosctl config node 10.0.100.100
```

## Check the cluster status
```bash
talosctl health
```

## Generate kubeconfig and copy to kube folder
```bash
talosctl kubeconfig cluster-config/
```
```bash
cp cluster-config/kubeconfig ~/.kube/config
```