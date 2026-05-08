# NFS CSI Driver for Kubernetes

Check GitHub project: https://github.com/kubernetes-csi/csi-driver-nfs

## How to install (using Helm)

1. Add Helm repo:
```
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
```

2. Install chart using custom `values.yaml`:

````
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system --version 4.13.2 --values kubernetes/setup/csi-driver-nfs/values.yaml
````
Make sure `--version X.Y.Z` is the one.

To update chart with new values:

```
helm upgrade csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system -f kubernetes/setup/csi-driver-nfs/values.yaml
```

## Testing

Use manifest `test.yaml` to deploy a pod using different `storageClasses` provisioned.

