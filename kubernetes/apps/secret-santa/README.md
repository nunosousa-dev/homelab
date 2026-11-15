# Secret Santa family release

Public family site: `https://amigo-secreto.nunosousa.dev`. Home-network site and organiser area: `https://amigo-secreto.local.nunosousa.dev`. The UI remains in European Portuguese; source and operational documentation use English.

## Release

- Source: [nunosousa-dev/secret-santa](https://github.com/nunosousa-dev/secret-santa).
- Image: `ghcr.io/nunosousa-dev/secret-santa:sha-<full commit>` from the source repository's GitHub workflow, available for anonymous pulls. Bump `image.tag` in `values.yaml` to release.
- Namespace/Application/release: `secret-santa`.
- Admin credential: existing local setup, encrypted for Secret `secret-santa-admin` in namespace `secret-santa`. The cluster controller has validated the SealedSecret. No plaintext credential is committed.
- Live database and avatar BLOBs: one replica, Recreate rollout, 1 GiB RWO `truenas-iscsi-retain` PVC.
- Backups: 5 GiB RWX `truenas-nfs-retain` PVC, daily at 03:00 Europe/Lisbon. No automatic deletion; monitor capacity and job success.
- Routes, both live at once against the same database:
  - HTTPRoute `secret-santa`: `amigo-secreto.local.nunosousa.dev` → listener `websecure` (local wildcard certificate) → app.
  - HTTPRoute `secret-santa-public`: `amigo-secreto.nunosousa.dev` → Cloudflare tunnel → listener `web` → app, except `/admin` and `/api/admin`, which redirect (302) to the local hostname. The organiser area is only reachable from the LAN/VPN.
- `APP_URL=https://amigo-secreto.nunosousa.dev`: editing links and printed QR codes always use the public hostname, even when generated on the local one. `ADDITIONAL_ORIGINS` lets forms on the local hostname save. Sessions are per hostname.

The Cloudflare DNS record required for the public hostname is:

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| CNAME | `amigo-secreto.nunosousa.dev` | `e41659cd-6610-43c8-a33c-f944243f374d.cfargotunnel.com` | Enabled |

This target was read from the existing tunnel configuration. Create it in the Cloudflare dashboard, or with `cloudflared tunnel route dns homelab amigo-secreto.nunosousa.dev`; merging this chart does not create DNS.

## Activate locally after review

Merge the reviewed homelab change first. The existing bootstrap ApplicationSet does not discover user application manifests. Register the new Application explicitly:

```sh
kubectl --context admin@homelab apply -f kubernetes/apps/secret-santa.yaml
kubectl --context admin@homelab -n argocd get application secret-santa
kubectl --context admin@homelab -n secret-santa rollout status deployment/secret-santa --timeout=180s
kubectl --context admin@homelab -n secret-santa get pvc,pods,httproute,cronjob
```

Preflight on 14 October 2026 confirmed `amigo-secreto.local.nunosousa.dev` already resolves to the Traefik Gateway at `10.0.0.30`, and certificate `all-local-nunosousa-dev` is ready. No additional local DNS record is needed with the existing resolver. Test devices using a different resolver must resolve the hostname to the same LAN address. Use the existing local wildcard certificate over HTTPS. Phones must be on the LAN or VPN. This stage needs no public DNS or Cloudflare change.

```sh
kubectl --context admin@homelab -n traefik get gateway homelab -o 'jsonpath={.status.addresses[*].value}'
curl --fail https://amigo-secreto.local.nunosousa.dev/health/ready
```

## Storage and backup acceptance

Before adding real profiles, confirm both PVCs bind and the app can start as UID/GID 1001. Trigger the first backup rather than waiting for the schedule:

```sh
kubectl --context admin@homelab -n secret-santa create job --from=cronjob/secret-santa-backup secret-santa-backup-initial
kubectl --context admin@homelab -n secret-santa wait --for=condition=complete job/secret-santa-backup-initial --timeout=300s
kubectl --context admin@homelab -n secret-santa logs job/secret-santa-backup-initial
```

Verify a snapshot exists on the backup PVC, then test restoring a copy onto a fresh writable volume. Keep the production volume separate from that test. The app and backup job share the live RWO volume on the same node; a pending app can also delay its backup. NFS permissions and actual CSI recovery still require acceptance in the cluster.

Use [the application's recovery instructions](https://github.com/nunosousa-dev/secret-santa/blob/main/deploy/README.md#backups-and-recovery) for maintenance, schema compatibility and session/token considerations. Snapshots include avatars and access records and need protection. The live SQLite database must stay on iSCSI.

## Family pilot

1. Open the local URL on the LAN/VPN and confirm HTTPS, browsing and the Portuguese empty-family state.
2. Sign in at `/admin` using the password from the existing local setup. A fresh production database starts empty; no fictional seed runs automatically.
3. Configure the family title, welcome, year and optional budget/date. Keep the demonstration flag off for real profiles.
4. Create two pilot profiles and upload the matching avatars.
5. Generate each private editing link and share it manually. Treat these links as credentials; keep them out of issues, screenshots and printed cards.
6. Complete browsing and editing on iOS Safari and Android Chrome where available. Confirm one member cannot edit another profile and revoked links stop working.
7. Replace the app pod and confirm preferences and avatars persist; complete the backup/recovery acceptance above.
8. Print a sample from `/admin/cards` on A4 at 100%, with browser headers/footers disabled. Cut on the outlines, fold once horizontally and once vertically, then open and scan. QR codes point to permanent public profiles, not editing access.
9. Complete [Go public](#go-public) before distributing final family editing links or printing the final cards.

The draw stays physical. The app does not record Secret Santa assignments. Profile information is public, so family members should enter only details they are comfortable sharing through the site.

## Go public

The local deployment keeps its Application, release, Secret and PVCs; the database is not copied.

1. Confirm the source repository's workflow published the image tag set in `values.yaml` and that it pulls anonymously (`docker pull ghcr.io/nunosousa-dev/secret-santa:<tag>`).
2. Merge this change to `main`. The Application file changed (`values-local.yaml` is gone), so re-register it straight away; until then Argo CD reports a comparison error but leaves the running app untouched:

   ```sh
   kubectl --context admin@homelab apply -f kubernetes/apps/secret-santa.yaml
   kubectl --context admin@homelab -n secret-santa rollout status deployment/secret-santa --timeout=180s
   ```

3. After Argo CD syncs the cloudflared ConfigMap, restart the tunnel; it does not reload its configuration on its own:

   ```sh
   kubectl --context admin@homelab -n cloudflared rollout restart deployment/cloudflared
   kubectl --context admin@homelab -n cloudflared rollout status deployment/cloudflared
   ```

4. Create the proxied DNS record above.
5. Verify:

   ```sh
   kubectl --context admin@homelab -n argocd get application secret-santa           # Synced, Healthy
   kubectl --context admin@homelab -n secret-santa get httproute                     # secret-santa, secret-santa-public
   curl -fsS https://amigo-secreto.local.nunosousa.dev/health/ready                  # from LAN/VPN
   curl -fsS https://amigo-secreto.nunosousa.dev/health/ready                        # also over mobile data
   curl -sI https://amigo-secreto.nunosousa.dev/admin | grep -i '^location'         # → https://amigo-secreto.local.nunosousa.dev/admin
   ```

6. On a phone over mobile data, open a profile and complete an edit through a private link.
7. Editing links issued before this change point to the local hostname and only work on the LAN/VPN. Replace any that family members need away from home. Confirm `/admin/cards` reports `https://amigo-secreto.nunosousa.dev` before printing the final cards.
