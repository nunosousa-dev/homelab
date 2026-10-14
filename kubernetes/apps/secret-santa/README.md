# Secret Santa family release

Initial local test site: `https://amigo-secreto.local.nunosousa.dev`. Final public family site: `https://amigo-secreto.nunosousa.dev`. The UI remains in European Portuguese; source and operational documentation use English.

## Prepared release

- Source: [nunosousa-dev/secret-santa](https://github.com/nunosousa-dev/secret-santa).
- Image: `ghcr.io/nunosousa-dev/secret-santa:sha-a3a140925ee46aca42eaa05a877b887d5769095f`, published by a successful GitHub workflow and available for anonymous pulls.
- Namespace/Application/release: `secret-santa`.
- Admin credential: existing local setup, encrypted for Secret `secret-santa-admin` in namespace `secret-santa`. The cluster controller has validated the SealedSecret. No plaintext credential is committed.
- Live database and avatar BLOBs: one replica, Recreate rollout, 1 GiB RWO `truenas-iscsi-retain` PVC.
- Backups: 5 GiB RWX `truenas-nfs-retain` PVC, daily at 03:00 Europe/Lisbon. No automatic deletion; monitor capacity and job success.
- Initial route: local DNS → Traefik Gateway `homelab` listener `websecure` → app service. The Application loads `values-local.yaml` after the base values, so `APP_URL` and all generated links use the local HTTPS origin.
- Public routing is a later promotion. This PR does not change cloudflared or create public DNS.

The Cloudflare DNS record required for this release is:

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| CNAME | `amigo-secreto.nunosousa.dev` | `e41659cd-6610-43c8-a33c-f944243f374d.cfargotunnel.com` | Enabled |

This target was read from the existing tunnel configuration. The record was absent during release preparation. Creating it is a separate deployment step; merging this chart does not create Cloudflare DNS.

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
9. Complete public promotion below before distributing final family editing links or printing the final cards. Local QR codes only work on the LAN/VPN.

The draw stays physical. The app does not record Secret Santa assignments. Profile information is public, so family members should enter only details they are comfortable sharing through the site.


## Promote to public access after the local pilot

Use the same Application, release, Secret and PVCs; changing the active hostname does not require copying the database. This configuration selects one canonical origin at a time rather than allowing edits through both hostnames concurrently.

1. Remove `values-local.yaml` from `helm.valueFiles` in `kubernetes/apps/secret-santa.yaml`, retaining `values.yaml`. This restores public `APP_URL=https://amigo-secreto.nunosousa.dev` and Gateway listener `web`.
2. Add the public hostname to cloudflared with backend `http://traefik.traefik.svc.cluster.local:80`. Include a ConfigMap checksum in its pod template or explicitly roll the tunnel deployment after syncing the routing change.
3. Create the proxied CNAME record documented above.
4. Review and apply the promotion, wait for the app/tunnel rollout, and verify public HTTPS from a mobile network. Recheck login and editing against the public origin.
5. Generate and share new editing links using the public hostname, then add the remaining members and print the final cards.

Local pilot data persists through promotion. Create only test profiles during storage/recovery acceptance; archive them before adding the real family.
