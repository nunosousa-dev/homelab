# Install via Manifest

https://metallb.io/


```Bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
```
## Then apply IP Pools and Advertisement

```Bash
kubectl apply -f ipaddresspool.yaml
kubectl apply -f l2advertisement.yaml
```
