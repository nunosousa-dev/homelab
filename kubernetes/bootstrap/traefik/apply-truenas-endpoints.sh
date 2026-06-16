#!/usr/bin/env bash
# Apply manually after cluster bootstrap.
# ArgoCD excludes Endpoints by default, so this must live outside GitOps.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Endpoints
metadata:
  name: truenas-external
  namespace: traefik
subsets:
  - addresses:
      - ip: 10.0.0.3
    ports:
      - port: 443
        protocol: TCP
EOF

echo "✔ truenas-external Endpoints created in traefik namespace"
