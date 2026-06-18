#!/usr/bin/env bash
# setup-nextcloud-truenas.sh — Create the TrueNAS datasets and NFS exports that
# Nextcloud's static PersistentVolumes depend on.
#
# The Nextcloud chart provisions its app/postgres volumes dynamically over iSCSI
# (democratic-csi), but the user-data and backup volumes use *static* NFS PVs
# (see kubernetes/apps/nextcloud/templates/nextcloud-pv.yaml). Those NFS paths
# must exist and be exported before the app is deployed — this script does that.
#
# It is idempotent: existing datasets/shares are detected and left untouched.
#
# Usage:
#   ./setup-nextcloud-truenas.sh           # create datasets + NFS exports
#   ./setup-nextcloud-truenas.sh --dry-run # show what would be done, change nothing
#
# Optional env overrides (defaults match kubernetes/apps/nextcloud/values.yaml):
#   TRUENAS_HOST       (default: 10.0.0.3)
#   TRUENAS_PORT       (default: 443)
#   NEXTCLOUD_DATASET  (default: data/nextcloud)   # ZFS path, no leading /mnt
#   USERDATA_SIZE_GI   (default: 100)              # quota for userdata, 0 = none
#   BACKUP_SIZE_GI     (default: 20)               # quota for backup,   0 = none
#   NFS_MAPALL_USER    (default: root)             # map all NFS access to this user
#   NFS_MAPALL_GROUP   (default: root)
#
# Requires: curl, jq, and TRUENAS_API_KEY (in the environment or in ./.env).

set -euo pipefail

# --- Argument parsing ---
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=true ;;
    --help|-h)
      grep '^#' "$0" | head -28 | sed 's/^# \?//'
      exit 0 ;;
    *)
      echo "error: unknown argument '$arg'" >&2
      echo "Usage: $0 [--dry-run|-n]" >&2
      exit 1 ;;
  esac
done

# --- Load .env file if present (inline env vars already set win) ---
if [[ -f ".env" ]]; then
  echo "==> Loading environment from .env"
  set -a
  # shellcheck source=/dev/null
  source ".env"
  set +a
fi

: "${TRUENAS_API_KEY:?TRUENAS_API_KEY is required}"

TRUENAS_HOST="${TRUENAS_HOST:-10.0.0.3}"
TRUENAS_PORT="${TRUENAS_PORT:-443}"
NEXTCLOUD_DATASET="${NEXTCLOUD_DATASET:-data/nextcloud}"
USERDATA_SIZE_GI="${USERDATA_SIZE_GI:-100}"
BACKUP_SIZE_GI="${BACKUP_SIZE_GI:-20}"
NFS_MAPALL_USER="${NFS_MAPALL_USER:-root}"
NFS_MAPALL_GROUP="${NFS_MAPALL_GROUP:-root}"

API="https://${TRUENAS_HOST}:${TRUENAS_PORT}/api/v2.0"

# --- Dependency check ---
for cmd in curl jq; do
  command -v "$cmd" &>/dev/null || { echo "error: '$cmd' is required but not found" >&2; exit 1; }
done

# --- API helpers ---

# api GET <path> -> body on stdout, non-zero on HTTP >= 400 (404 tolerated by callers)
api_get() {
  curl -sf -k -H "Authorization: Bearer ${TRUENAS_API_KEY}" "${API}$1"
}

# api POST <path> <json> -> body on stdout
api_post() {
  curl -sf -k -X POST \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    -H "Content-Type: application/json" \
    "${API}$1" -d "$2"
}

# Returns 0 if the dataset id exists, 1 otherwise.
dataset_exists() {
  local id="$1" encoded code
  encoded=$(printf '%s' "$id" | jq -Rr @uri)
  code=$(curl -s -k -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    "${API}/pool/dataset/id/${encoded}")
  [[ "$code" == "200" ]]
}

# Returns 0 if an NFS export for the given path already exists.
nfs_share_exists() {
  local path="$1"
  api_get "/sharing/nfs" | jq -e --arg p "$path" '.[] | select(.path == $p)' >/dev/null 2>&1
}

# Creates a dataset (with optional quota in GiB) if it doesn't already exist.
ensure_dataset() {
  local id="$1" quota_gi="${2:-0}" body quota_bytes
  if dataset_exists "$id"; then
    echo "    [skip] dataset '${id}' already exists"
    return 0
  fi
  body=$(jq -n --arg name "$id" '{name: $name}')
  if [[ "$quota_gi" != "0" ]]; then
    quota_bytes=$(( quota_gi * 1024 * 1024 * 1024 ))
    body=$(printf '%s' "$body" | jq --argjson q "$quota_bytes" '. + {quota: $q}')
  fi
  if $DRY_RUN; then
    echo "    [dry-run] would create dataset '${id}' ${quota_gi:+(quota ${quota_gi}Gi)}"
    return 0
  fi
  api_post "/pool/dataset" "$body" >/dev/null
  echo "    [ok] created dataset '${id}'${quota_gi:+ (quota ${quota_gi}Gi)}"
}

# Creates an NFS export for a path if one doesn't already exist.
ensure_nfs_share() {
  local path="$1" comment="$2" body
  if nfs_share_exists "$path"; then
    echo "    [skip] NFS export for '${path}' already exists"
    return 0
  fi
  body=$(jq -n \
    --arg path "$path" \
    --arg comment "$comment" \
    --arg muser "$NFS_MAPALL_USER" \
    --arg mgroup "$NFS_MAPALL_GROUP" \
    '{path: $path, comment: $comment, enabled: true,
      mapall_user: $muser, mapall_group: $mgroup}')
  if $DRY_RUN; then
    echo "    [dry-run] would create NFS export for '${path}' (mapall ${NFS_MAPALL_USER}:${NFS_MAPALL_GROUP})"
    return 0
  fi
  api_post "/sharing/nfs" "$body" >/dev/null
  echo "    [ok] created NFS export for '${path}'"
}

# --- Sanity checks ---

echo "==> Target: ${TRUENAS_HOST}:${TRUENAS_PORT}  dataset='${NEXTCLOUD_DATASET}'"
$DRY_RUN && echo "    (dry-run: no changes will be made)"

# Warn (do not silently change global config) if NFSv4 is disabled — the static
# PVs mount with nfsvers=4.1.
if ! api_get "/nfs" | jq -e '.v4 == true' >/dev/null 2>&1; then
  echo "    WARNING: NFSv4 appears disabled on TrueNAS. The Nextcloud PVs mount" >&2
  echo "             with nfsvers=4.1 — enable NFSv4 in the NFS service settings." >&2
fi

# --- Datasets ---

MNT_PATH="/mnt/${NEXTCLOUD_DATASET}"

echo "==> Ensuring datasets..."
ensure_dataset "${NEXTCLOUD_DATASET}"
ensure_dataset "${NEXTCLOUD_DATASET}/userdata" "${USERDATA_SIZE_GI}"
ensure_dataset "${NEXTCLOUD_DATASET}/backup"   "${BACKUP_SIZE_GI}"

# --- NFS exports ---

echo "==> Ensuring NFS exports..."
ensure_nfs_share "${MNT_PATH}/userdata" "nextcloud-userdata"
ensure_nfs_share "${MNT_PATH}/backup"   "nextcloud-backup"

# --- Ensure the NFS service is running ---
if ! $DRY_RUN; then
  if ! api_get "/service" | jq -e '.[] | select(.service == "nfs") | select(.state == "RUNNING")' >/dev/null 2>&1; then
    echo "==> Starting NFS service..."
    api_post "/service/start" '{"service": "nfs"}' >/dev/null \
      && echo "    [ok] NFS service started" \
      || echo "    WARNING: could not start NFS service — start it manually" >&2
  fi
fi

echo ""
echo "Done. Datasets and exports for '${NEXTCLOUD_DATASET}' are ready."
echo "Verify with: kubectl get pv | grep nextcloud   (after deploying the chart)"
