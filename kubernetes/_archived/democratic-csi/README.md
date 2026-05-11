```
helm repo add democratic-csi https://democratic-csi.github.io/charts/
kubectl create namespace democratic-csi
kubectl label namespace democratic-csi pod-security.kubernetes.io/enforce=privileged
helm upgrade --install zfs-nfs democratic-csi/democratic-csi -n democratic-csi -f kubernetes/setup/democratic-csi/values-nfs.yaml
helm upgrade --install zfs-iscsi democratic-csi/democratic-csi -n democratic-csi -f kubernetes/setup/democratic-csi/values-iscsi.yaml
```