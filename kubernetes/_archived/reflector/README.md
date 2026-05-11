https://github.com/emberstack/kubernetes-reflector/blob/main/README.md

helm repo add emberstack https://emberstack.github.io/helm-charts
helm repo update
helm upgrade --install reflector emberstack/reflector