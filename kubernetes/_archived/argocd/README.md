# Installed via Helm

```
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f kubernetes/setup/argocd/values.yaml
```