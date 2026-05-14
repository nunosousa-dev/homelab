#!/usr/bin/env bash
# truenas-orphaned-datasets.sh — List (and optionally delete) TrueNAS datasets
# that have no matching Kubernetes PersistentVolume.
#
# Usage:
#   ./truenas-orphaned-datasets.sh              # list only
#   ./truenas-orphaned-datasets.sh --delete     # list + interactive delete
#   ./truenas-orphaned-datasets.sh --delete --yes  # list + delete all (pipeline)
#
# Optional env overrides:
#   TRUENAS_HOST   (default: 10.0.0.3)
#   TRUENAS_PORT   (default: 443)
#   NFS_PARENT     (default: data/k8s-nfs/vols)
#   ISCSI_PARENT   (default: data/k8s-iscsi/vols)

set -euo pipefail

# --- Argument parsing ---
DELETE=false
YES=false
for arg in "$@"; do
  case "$arg" in
    --delete)  DELETE=true ;;
    --yes|-y)  YES=true ;;
    --help|-h)
      grep '^#' "$0" | head -15 | sed 's/^# \?//'
      exit 0 ;;
    *)
      echo "error: unknown argument '$arg'" >&2
      echo "Usage: $0 [--delete] [--yes|-y]" >&2
      exit 1 ;;
  esac
done

# Load .env file if present (inline env vars already set will not be overwritten)
if [[ -f ".env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source ".env"
  set +a
fi

: "${TRUENAS_API_KEY:?TRUENAS_API_KEY is required}"

TRUENAS_HOST="${TRUENAS_HOST:-10.0.0.3}"
TRUENAS_PORT="${TRUENAS_PORT:-443}"
NFS_PARENT="${NFS_PARENT:-data/k8s-nfs/vols}"
ISCSI_PARENT="${ISCSI_PARENT:-data/k8s-iscsi/vols}"

# --- Dependency check ---
for cmd in curl jq kubectl; do
  command -v "$cmd" &>/dev/null || { echo "error: '$cmd' is required but not found" >&2; exit 1; }
done

# --- Helpers ---

# Returns the basename of each direct child dataset under $1.
# Uses .id == (prefix + .name) to match only immediate children, not nested sub-datasets.
truenas_list_children() {
  local parent="$1"
  curl -sf -k \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    "https://${TRUENAS_HOST}:${TRUENAS_PORT}/api/v2.0/pool/dataset" \
    | jq -r --arg prefix "${parent}/" \
        '.[] | select(.id | startswith($prefix)) | .id | ltrimstr($prefix) | select(contains("/") | not)'
}

# Returns 0 if $1 appears as an exact line in $PV_NAMES, 1 otherwise.
is_pv_present() {
  printf '%s' "${PV_NAMES}" | grep -qFx "$1"
}

# Deletes a TrueNAS dataset by its full ZFS path.
delete_dataset() {
  local full_id="$1"
  local encoded_id
  encoded_id=$(printf '%s' "${full_id}" | jq -Rr @uri)
  curl -sf -k -X DELETE \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"recursive": false, "force": false}' \
    "https://${TRUENAS_HOST}:${TRUENAS_PORT}/api/v2.0/pool/dataset/id/${encoded_id}" \
    > /dev/null
}

# --- Fetch data ---

echo "==> Fetching Kubernetes PersistentVolumes..."
PV_NAMES=""
while IFS= read -r line; do
  [[ -n "$line" ]] && PV_NAMES+="${line}"$'\n'
done < <(kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
pv_count=$(printf '%s' "${PV_NAMES}" | grep -c '.' || true)
echo "    Found ${pv_count} PV(s)."

echo "==> Fetching TrueNAS datasets under '${NFS_PARENT}'..."
NFS_DATASETS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && NFS_DATASETS+=("$line")
done < <(truenas_list_children "${NFS_PARENT}" || true)
echo "    Found ${#NFS_DATASETS[@]} NFS dataset(s)."

echo "==> Fetching TrueNAS datasets under '${ISCSI_PARENT}'..."
ISCSI_DATASETS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && ISCSI_DATASETS+=("$line")
done < <(truenas_list_children "${ISCSI_PARENT}" || true)
echo "    Found ${#ISCSI_DATASETS[@]} iSCSI dataset(s)."

echo ""

# Parallel arrays tracking orphans for optional deletion
ORPHAN_FULL_IDS=()
ORPHAN_NAMES=()
ORPHAN_LABELS=()
orphan_count=0
released_count=0

# --- Orphaned datasets ---
echo "====== Orphaned Datasets (no matching PV in cluster) ======"

collect_orphans() {
  local label="$1"
  local parent="$2"
  shift 2
  local dataset
  for dataset in "$@"; do
    [[ -z "$dataset" ]] && continue
    if ! is_pv_present "$dataset"; then
      printf "  %-8s %s\n" "${label}" "${dataset}"
      ORPHAN_FULL_IDS+=("${parent}/${dataset}")
      ORPHAN_NAMES+=("${dataset}")
      ORPHAN_LABELS+=("${label}")
      ((orphan_count++)) || true
    fi
  done
}

[[ ${#NFS_DATASETS[@]}   -gt 0 ]] && collect_orphans "[NFS]"   "${NFS_PARENT}"   "${NFS_DATASETS[@]}"
[[ ${#ISCSI_DATASETS[@]} -gt 0 ]] && collect_orphans "[iSCSI]" "${ISCSI_PARENT}" "${ISCSI_DATASETS[@]}"

[[ $orphan_count -eq 0 ]] && echo "  (none)"

# --- Released PVs ---
echo ""
echo "====== Released PVs (PVC deleted, dataset still retained) ======"

while IFS= read -r pv; do
  [[ -z "$pv" ]] && continue
  printf "  %-12s %s\n" "[RELEASED]" "${pv}"
  ((released_count++)) || true
done < <(
  kubectl get pv --field-selector=status.phase=Released \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
)

[[ $released_count -eq 0 ]] && echo "  (none)"

echo ""
echo "Summary: ${orphan_count} orphaned dataset(s), ${released_count} released PV(s)."

# --- Optional deletion ---
if [[ "$DELETE" == "false" ]]; then
  [[ $orphan_count -gt 0 ]] && echo "Tip: run with --delete [--yes] to remove orphaned datasets."
  exit 0
fi

[[ $orphan_count -eq 0 ]] && exit 0

echo ""
if [[ "$YES" == "true" ]]; then
  echo "==> Deleting ${orphan_count} orphaned dataset(s) (--yes mode)..."
else
  echo "==> Interactive deletion — answer y/N for each dataset."
fi

delete_count=0
skip_count=0

for i in "${!ORPHAN_FULL_IDS[@]}"; do
  full_id="${ORPHAN_FULL_IDS[$i]}"
  label="${ORPHAN_LABELS[$i]}"
  name="${ORPHAN_NAMES[$i]}"

  confirm=false
  if [[ "$YES" == "true" ]]; then
    confirm=true
  else
    read -rp "  Delete ${label} ${name}? [y/N] " answer < /dev/tty
    [[ "$answer" == "y" || "$answer" == "Y" ]] && confirm=true
  fi

  if [[ "$confirm" == "true" ]]; then
    printf "    Deleting %-52s " "${name}..."
    if delete_dataset "${full_id}"; then
      echo "OK"
      ((delete_count++)) || true
    else
      echo "FAILED"
    fi
  else
    ((skip_count++)) || true
  fi
done

echo ""
echo "Deleted: ${delete_count}, Skipped: ${skip_count}."
