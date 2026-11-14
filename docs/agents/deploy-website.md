# Deploy a website to the cluster

Recipe for shipping a containerised website as a Helm chart under `kubernetes/apps/<name>/`, reachable on a **local** hostname, a **public** hostname, or both. Copy from `kubernetes/apps/wedding/` (static site, local + public) or `kubernetes/apps/jellyfin/` (local only, with storage).

## Traffic paths

Two paths reach the same Traefik Gateway `homelab` (namespace `traefik`, LoadBalancer IP `10.0.0.30`). The path decides the HTTPRoute listener, so pick it first.

| Exposure | Hostname | Path | HTTPRoute `sectionName` | TLS |
|---|---|---|---|---|
| **Local** | `<name>.local.nunosousa.dev` | client → DNS `*.local.nunosousa.dev` → `10.0.0.30` → listener `websecure` | `websecure` | Wildcard cert `all-local-nunosousa-dev`, already issued |
| **Public** | any domain in the Cloudflare account (e.g. `<name>.nunosousa.dev`, `denu.pt`) | client → Cloudflare edge → tunnel `homelab` (cloudflared pods) → `http://traefik.traefik.svc.cluster.local:80` → listener `web` | `web` | Terminated at Cloudflare; in-cluster hop is plain HTTP |

Facts that make these paths work:

- Local DNS is already a wildcard: any `*.local.nunosousa.dev` name resolves to `10.0.0.30`. A local site needs **no DNS change and no certificate change**. Only reachable from the LAN or VPN.
- The wildcard cert covers one label only: `foo.local.nunosousa.dev` works, `a.foo.local.nunosousa.dev` does not.
- Public traffic arrives on `web` (port 80). An HTTPRoute that only attaches to `websecure` returns 404 for the public hostname.
- Public DNS is **not** managed from this repo. Creating the Cloudflare record is a step the human performs (see step 6).

Default to **local** unless the user asks for public access. When public, also keep the local hostname (pattern used by `wedding`, `julieta`, `benedita`).

## Steps

### 1. Gather inputs

Done when every value below is known; ask the user for anything missing.

- `name`: app name, used for chart dir, namespace, Application, Deployment, Service.
- `image`: full reference (usually `ghcr.io/nunosousa-dev/<name>:<tag>`). Confirm it exists and is pullable anonymously, or the pod will sit in `ImagePullBackOff`.
- Container port, UID it runs as, and a health path for probes.
- Exposure: local, public, or both; public hostname if any.
- Persistent data? If yes, size and access mode (see Storage below).
- Secrets? If yes, they must be SealedSecrets (see Secrets below).

### 2. Create the chart

```
kubernetes/apps/<name>/
  Chart.yaml
  values.yaml
  templates/namespace.yaml
  templates/deployment.yaml
  templates/service.yaml
  templates/httproute.yaml
```

Copy `kubernetes/apps/wedding/` and rename every `wedding`. Conventions to keep:

- `Chart.yaml`: `apiVersion: v2`, `type: application`, `version: 1.0.0`, one-line `description`.
- `values.yaml`: `hostname`, optional `publicHostname`, `image`, `resources`. Hardcode the namespace in templates (repo convention), not `.Release.Namespace`.
- `namespace.yaml`: label `pod-security.kubernetes.io/enforce: baseline`.
- `deployment.yaml`: `nodeSelector: homelab/node-type: vm`; pod `securityContext` with explicit `runAsUser`/`runAsGroup`/`fsGroup` and `seccompProfile: RuntimeDefault`; container `allowPrivilegeEscalation: false`, `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`; readiness + liveness probes; `resources` from values. With a read-only root, mount `emptyDir` on every path the process writes (for nginx: `/tmp`, `/var/cache/nginx`, `/var/run`).
- `service.yaml`: `ClusterIP`, port matching the container.

### 3. Write the HTTPRoute for the chosen exposure

Local only (as in `jellyfin`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <name>
  namespace: <name>
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: homelab
      namespace: traefik
      sectionName: websecure
  hostnames:
    - {{ .Values.hostname | quote }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: <name>
          port: <service-port>
          weight: 1
```

Local + public (as in `wedding`): add a second `parentRefs` entry identical except `sectionName: web`, and add `- {{ .Values.publicHostname | quote }}` to `hostnames`.

If the app builds absolute URLs (e.g. an `APP_URL` env var), it has one canonical origin. Set it to the hostname users will actually use; `secret-santa` switches it with an overlay `values-local.yaml`.

Write every HTTPRoute field the Gateway API CRD defaults, as in the template above: each rule's `matches`, plus `group`/`kind` on refs and `weight` on backend refs. Rules are compared whole, so a rule missing a defaulted field (e.g. a redirect-only rule without `matches`) stays OutOfSync in ArgoCD forever.

### 4. Create the ArgoCD Application

User apps are **not** in the ApplicationSet `kubernetes/bootstrap/_apps.yaml` (that one is bootstrap-only). Each app has its own `kubernetes/apps/<name>.yaml`; copy `kubernetes/apps/wedding.yaml`, replacing `name`, `path`, and `destination.namespace`. Keep `targetRevision: main`, automated `prune`/`selfHeal`, and `CreateNamespace=true`, `ServerSideApply=true`.

### 5. Public only: route the hostname through the tunnel

Add an entry to `kubernetes/bootstrap/cloudflared/templates/config.yaml`, **above** the final `http_status:404` catch-all:

```yaml
      - hostname: <public-hostname>
        service: http://traefik.traefik.svc.cluster.local:80
```

The cloudflared Deployment carries no ConfigMap checksum, so pods keep the old config after sync. After ArgoCD syncs, restart them (step 7).

### 6. Public only: hand the DNS record to the human

The agent cannot create this. Tell the user to add in the Cloudflare dashboard (zone of the hostname):

| Type | Name | Target | Proxy |
|---|---|---|---|
| CNAME | `<public-hostname>` | `e41659cd-6610-43c8-a33c-f944243f374d.cfargotunnel.com` | Proxied (orange cloud) |

Equivalent CLI, if they have `cloudflared` logged in: `cloudflared tunnel route dns homelab <public-hostname>`. For an apex domain (like `denu.pt`) the dashboard CNAME is flattened automatically.

### 7. Validate, commit, activate

Render before committing; done when this exits 0 and the output contains the Namespace, Deployment, Service, and HTTPRoute:

```sh
helm template <name> kubernetes/apps/<name>
```

Commit and push to `main` (or open a PR if the user prefers). ArgoCD tracks `main`, so nothing deploys before merge. Then register the Application once, since nothing discovers it automatically:

```sh
kubectl apply -f kubernetes/apps/<name>.yaml
kubectl -n argocd get application <name>
kubectl -n <name> rollout status deployment/<name> --timeout=180s
```

Public only, after the cloudflared change has synced:

```sh
kubectl -n cloudflared rollout restart deployment/cloudflared
kubectl -n cloudflared rollout status deployment/cloudflared
```

### 8. Verify

Done when every check for the chosen exposure passes:

```sh
kubectl -n argocd get application <name>          # Synced, Healthy
kubectl -n <name> get httproute <name> -o yaml     # status.parents[*].conditions Accepted=True, ResolvedRefs=True
curl -fsS https://<name>.local.nunosousa.dev/       # local (from LAN/VPN)
dig +short <public-hostname>                        # public: Cloudflare IPs
curl -fsS https://<public-hostname>/                # public
```

Report to the user any step left for them (DNS record, `kubectl apply` if you lack cluster access).

## Storage

Only when the app persists data. Add a PVC template; pick the class by access pattern:

- `truenas-iscsi-retain`: `ReadWriteOnce`, databases (SQLite, Postgres). Use `strategy: Recreate` on the Deployment so the old pod releases the volume.
- `truenas-nfs-retain`: `ReadWriteMany`, shared files, backups.
- Existing TrueNAS datasets (`10.0.0.3`): static NFS PV as in `kubernetes/apps/jellyfin/templates/media-pv.yaml`.

PVCs survive Application deletion; that is intended.

## Secrets

Commit only `SealedSecret` manifests, never plaintext. Seal against the cluster with `kubeseal` (controller `sealed-secrets-controller` in `kube-system`), as in `kubernetes/apps/secret-santa/templates/admin-sealedsecret.yaml`. Values come from the user or `.env` (gitignored); if the secret should be reproducible, add it to `seal-secrets.sh`.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Public hostname returns Cloudflare 404 / error 1033 | Missing tunnel ingress entry, cloudflared not restarted, or DNS record not proxied to the tunnel |
| Public hostname returns Traefik 404 | HTTPRoute lacks `sectionName: web` or the public hostname |
| Local hostname cert error | Hostname is more than one label below `local.nunosousa.dev` |
| HTTPRoute `Accepted=False` | Wrong Gateway name/namespace/sectionName |
| Application missing in ArgoCD | `kubectl apply -f kubernetes/apps/<name>.yaml` not run |
| HTTPRoute permanently OutOfSync in ArgoCD, re-sync doesn't help | A rule omits a CRD-defaulted field (usually `matches`); write the default explicitly |
| Pod `CrashLoopBackOff` with permission errors | Read-only root: add an `emptyDir` for the written path, or fix `runAsUser` |
