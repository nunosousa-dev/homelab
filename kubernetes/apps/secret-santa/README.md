# Secret Santa family release

Public family site: `https://amigo-secreto.nunosousa.dev`. The UI remains in European Portuguese; source and operational documentation use English.

## Prepared release

- Source: [nunosousa-dev/secret-santa](https://github.com/nunosousa-dev/secret-santa).
- Image: `ghcr.io/nunosousa-dev/secret-santa:sha-a3a140925ee46aca42eaa05a877b887d5769095f`, published by a successful GitHub workflow and available for anonymous pulls.
- Namespace/Application/release: `secret-santa`.
- Admin credential: existing local setup, encrypted for Secret `secret-santa-admin` in namespace `secret-santa`. The cluster controller has validated the SealedSecret. No plaintext credential is committed.
- Live database and avatar BLOBs: one replica, Recreate rollout, 1 GiB RWO `truenas-iscsi-retain` PVC.
- Backups: 5 GiB RWX `truenas-nfs-retain` PVC, daily at 03:00 Europe/Lisbon. No automatic deletion; monitor capacity and job success.
- Public route: Cloudflare HTTPS/tunnel → Traefik Gateway `homelab` listener `web` → app service.

The Cloudflare DNS record required for this release is:

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| CNAME | `amigo-secreto.nunosousa.dev` | `e41659cd-6610-43c8-a33c-f944243f374d.cfargotunnel.com` | Enabled |

This target was read from the existing tunnel configuration. The record was absent during release preparation. Creating it is a separate deployment step; merging this chart does not create Cloudflare DNS.

## Activate after review

Merge the reviewed homelab change first. The existing bootstrap ApplicationSet manages cloudflared, but does not discover user application manifests. Register the new Application explicitly:

```sh
kubectl --context admin@homelab apply -f kubernetes/apps/secret-santa.yaml
kubectl --context admin@homelab -n argocd get application secret-santa
kubectl --context admin@homelab -n secret-santa rollout status deployment/secret-santa --timeout=180s
kubectl --context admin@homelab -n secret-santa get pvc,pods,httproute,cronjob
```

Create the proxied DNS record above. Check that cloudflared synchronises and rolls out after the ConfigMap change; its pod template now includes a config checksum. Existing hostnames remain in the tunnel configuration.

```sh
kubectl --context admin@homelab -n cloudflared rollout status deployment/cloudflared --timeout=180s
curl --fail https://amigo-secreto.nunosousa.dev/health/ready
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

1. Open the public URL over a mobile network and confirm HTTPS, browsing and the Portuguese empty-family state.
2. Sign in at `/admin` using the password from the existing local setup. A fresh production database starts empty; no fictional seed runs automatically.
3. Configure the family title, welcome, year and optional budget/date. Keep the demonstration flag off for real profiles.
4. Create two pilot profiles and upload the matching avatars.
5. Generate each private editing link and share it manually. Treat these links as credentials; keep them out of issues, screenshots and printed cards.
6. Complete browsing and editing on iOS Safari and Android Chrome where available. Confirm one member cannot edit another profile and revoked links stop working.
7. Replace the app pod and confirm preferences and avatars persist; complete the backup/recovery acceptance above.
8. Print a sample from `/admin/cards` on A4 at 100%, with browser headers/footers disabled. Cut on the outlines, fold once horizontally and once vertically, then open and scan. QR codes point to permanent public profiles, not editing access.
9. Add the remaining family members and print the final cards after the pilot succeeds.

The draw stays physical. The app does not record Secret Santa assignments. Profile information is public, so family members should enter only details they are comfortable sharing through the site.
