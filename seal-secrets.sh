#!/bin/bash
# seal-secrets.sh — Re-seal all cluster secrets
#
# Run from repo root when the cluster is reachable.
# Pass values via environment variables — never hardcode keys in this file.
#
# Usage:
#   TRUENAS_API_KEY=<key> CLOUDFLARE_API_TOKEN=<token> \
#   IMMICH_DB_PASSWORD=<pw> IMMICH_SECRET_KEY=<key> \
#   ./seal-secrets.sh

set -euo pipefail

: "${TRUENAS_API_KEY:?TRUENAS_API_KEY is required}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"
: "${IMMICH_DB_PASSWORD:?IMMICH_DB_PASSWORD is required}"
: "${IMMICH_SECRET_KEY:?IMMICH_SECRET_KEY is required}"

KUBESEAL="kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system --format yaml"

echo "==> Sealing truenas-nfs-config..."
NFS_DRIVER_CONFIG=$(cat <<EOF
{
  "driver": "freenas-api-nfs",
  "instance_id": "homelab-nfs",
  "httpConnection": {
    "protocol": "https",
    "host": "10.0.0.3",
    "port": 443,
    "apiKey": "${TRUENAS_API_KEY}",
    "allowInsecure": true
  },
  "zfs": {
    "datasetParentName": "data/k8s-nfs/vols",
    "detachedSnapshotsDatasetParentName": "data/k8s-nfs/snaps",
    "datasetEnableQuotas": true,
    "datasetEnableReservation": false,
    "datasetPermissionsMode": "0777",
    "datasetPermissionsUser": 0,
    "datasetPermissionsGroup": 0,
    "datasetProperties": {
      "org.freenas:description": "{{ parameters.[csi.storage.k8s.io/pvc/namespace] }}/{{ parameters.[csi.storage.k8s.io/pvc/name] }}"
    }
  },
  "nfs": {
    "shareHost": "10.0.0.3",
    "shareAlldirs": false,
    "shareAllowedHosts": [],
    "shareAllowedNetworks": [],
    "shareMaprootUser": "root",
    "shareMaprootGroup": "root",
    "shareMapallUser": "",
    "shareMapallGroup": ""
  }
}
EOF
)
kubectl create secret generic truenas-nfs-config \
  --namespace democratic-csi \
  --from-literal=driver-config-file.yaml="${NFS_DRIVER_CONFIG}" \
  --dry-run=client -o yaml \
  | $KUBESEAL \
  > kubernetes/apps/democratic-csi/templates/truenas-nfs-config.yaml
echo "    -> kubernetes/apps/democratic-csi/templates/truenas-nfs-config.yaml"

echo "==> Sealing truenas-iscsi-config..."
ISCSI_DRIVER_CONFIG=$(cat <<EOF
{
  "driver": "freenas-api-iscsi",
  "instance_id": "homelab-iscsi",
  "httpConnection": {
    "protocol": "https",
    "host": "10.0.0.3",
    "port": 443,
    "apiKey": "${TRUENAS_API_KEY}",
    "allowInsecure": true
  },
  "zfs": {
    "datasetParentName": "data/k8s-iscsi/vols",
    "detachedSnapshotsDatasetParentName": "data/k8s-iscsi/snaps",
    "zvolCompression": "",
    "zvolDedup": "",
    "zvolEnableReservation": false,
    "zvolBlocksize": "16K",
    "datasetProperties": {
      "org.freenas:description": "{{ parameters.[csi.storage.k8s.io/pvc/namespace] }}/{{ parameters.[csi.storage.k8s.io/pvc/name] }}"
    }
  },
  "iscsi": {
    "targetPortal": "10.0.0.3:3260",
    "interface": "",
    "namePrefix": "csi-",
    "nameSuffix": "-homelab",
    "targetGroups": [
      {
        "targetGroupPortalGroup": 1,
        "targetGroupInitiatorGroup": 1,
        "targetGroupAuthType": "None"
      }
    ],
    "extentInsecureTpc": true,
    "extentXenCompat": false,
    "extentDisablePhysicalBlocksize": true,
    "extentBlocksize": 512,
    "extentRpm": "SSD",
    "extentAvailThreshold": 0
  }
}
EOF
)
kubectl create secret generic truenas-iscsi-config \
  --namespace democratic-csi \
  --from-literal=driver-config-file.yaml="${ISCSI_DRIVER_CONFIG}" \
  --dry-run=client -o yaml \
  | $KUBESEAL \
  > kubernetes/apps/democratic-csi/templates/truenas-iscsi-config.yaml
echo "    -> kubernetes/apps/democratic-csi/templates/truenas-iscsi-config.yaml"

echo "==> Sealing cloudflare-api-token-secret..."
kubectl create secret generic cloudflare-api-token-secret \
  --namespace cert-manager \
  --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
  --dry-run=client -o yaml \
  | $KUBESEAL \
  > kubernetes/apps/cert-manager/templates/cloudflare-secret.yaml
echo "    -> kubernetes/apps/cert-manager/templates/cloudflare-secret.yaml"

echo "==> Sealing immich-secret..."
kubectl create secret generic immich-secret \
  --namespace immich \
  --from-literal=DB_PASSWORD="${IMMICH_DB_PASSWORD}" \
  --from-literal=SECRET_KEY="${IMMICH_SECRET_KEY}" \
  --dry-run=client -o yaml \
  | $KUBESEAL \
  > kubernetes/apps/immich/templates/immich-secret.yaml
echo "    -> kubernetes/apps/immich/templates/immich-secret.yaml"

echo ""
echo "==> Done. Commit the updated sealed secret files:"
echo "    git add kubernetes/apps/*/templates/*secret*.yaml kubernetes/apps/democratic-csi/templates/truenas-*-config.yaml"
echo "    git commit -m 'chore: rotate sealed secrets'"

echo ""
echo "==> Also back up the sealed-secrets master key (store outside Git):"
echo "    kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-master-key.yaml"
