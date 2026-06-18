# Nextcloud Helm Chart

Self-hosted Nextcloud with PostgreSQL and Redis (Valkey).

## Storage overview

This chart uses **two different storage backends**:

| Volume | PVC | Backend | Provisioning |
|--------|-----|---------|--------------|
| App (`/var/www/html`) | `nextcloud-app` | iSCSI (`truenas-iscsi-retain`) | Dynamic (democratic-csi) |
| PostgreSQL data | `pgdata` (StatefulSet volumeClaimTemplate) | iSCSI (`truenas-iscsi-retain`) | Dynamic (democratic-csi) |
| User data (`/var/www/html/data`) | `nextcloud-userdata` | NFS static PV | **Manual** |
| Backups | `nextcloud-backup` | NFS static PV | **Manual** |

The iSCSI-backed volumes are provisioned automatically. The two NFS-backed
volumes use static `PersistentVolume`s (see
[`templates/nextcloud-pv.yaml`](templates/nextcloud-pv.yaml)) that point at
fixed paths on TrueNAS, so **those paths must exist and be exported over NFS
before the app is deployed**.

## Manual prerequisites (TrueNAS)

Configured in [`values.yaml`](values.yaml):

```yaml
nfs:
  server: 10.0.0.3
  basePath: /mnt/data/nextcloud
```

Before deploying, create the following on TrueNAS (`10.0.0.3`):

1. **Datasets / directories** under `basePath`:
   - `/mnt/data/nextcloud/userdata`
   - `/mnt/data/nextcloud/backup`
2. **NFS export(s)** covering those paths, reachable from the cluster nodes.
   The static PVs mount with `nfsvers=4.1`, so NFSv4.1 must be enabled.
3. **Permissions** so Nextcloud (`www-data`) can read/write the share
   (set an appropriate maproot user/group or mode on the export).

> If these NFS paths do not exist, the `nextcloud-userdata` and
> `nextcloud-backup` PVCs will bind but the pods will fail to mount.

### Automated setup

Instead of clicking through the TrueNAS UI, run the idempotent helper script,
which creates the datasets (with quotas), the NFS exports, and ensures the NFS
service is running via the TrueNAS API:

```bash
./setup-nextcloud-truenas.sh            # create datasets + NFS exports
./setup-nextcloud-truenas.sh --dry-run  # preview, change nothing
```

It reads `TRUENAS_API_KEY` from `.env` (same as the other scripts in this repo).
See [`setup-nextcloud-truenas.sh`](../../../setup-nextcloud-truenas.sh) for the
available env overrides.

## Deploy

The chart is deployed via ArgoCD from
[`kubernetes/apps/nextcloud.yaml`](../nextcloud.yaml). The
`nextcloud-secret` (PostgreSQL + admin passwords) is sealed via
[`seal-secrets.sh`](../../../seal-secrets.sh) — see the `NEXTCLOUD_*`
variables in [`.env.example`](../../../.env.example).
