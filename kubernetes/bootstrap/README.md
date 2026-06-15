# Bootstrap

Infrastructure components managed by ArgoCD via the [App of Apps pattern](_apps.yaml).

## Components

| Component | Description |
|-----------|-------------|
| argocd | GitOps continuous delivery |
| cert-manager | TLS certificate management |
| cilium | CNI and network policies |
| cloudflared | Cloudflare Tunnel for external access |
| democratic-csi | CSI driver for TrueNAS storage |
| intel-gpu-plugin | Intel GPU device plugin |
| monitoring | Prometheus + Grafana stack |
| reflector | Secret/ConfigMap mirroring across namespaces |
| traefik | Ingress/Gateway API proxy |

## External Services (TrueNAS)

TrueNAS runs as an external VM at `10.0.0.3` and is exposed via Traefik at `data.local.nunosousa.dev`.

Traffic flow:
```
Client → Cloudflare (*.local.nunosousa.dev)
       → 10.0.0.30 (k8s LoadBalancer / Traefik)
       → IngressRoute (Host match)
       → 10.0.0.3:443 (TrueNAS UI)
```

Since TrueNAS is outside the cluster, a selector-less `Service` is used with a manually-created `Endpoints` resource. ArgoCD excludes `Endpoints` by default, so this resource must be applied manually after cluster bootstrap:

```bash
./kubernetes/bootstrap/traefik/templates/apply-truenas-endpoints.sh
```

### Why manual?

ArgoCD excludes `Endpoints` and `EndpointSlice` to avoid noise from Kubernetes constantly updating them as pods scale. Overriding this exclusion works but adds unnecessary reconciliation churn. For a single static endpoint, a manual apply on bootstrap is the simplest trade-off.
