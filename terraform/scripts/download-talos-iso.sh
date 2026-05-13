#!/usr/bin/env bash
set -euo pipefail

# Required environment variables:
#   PM_API_URL       - Proxmox API base URL (e.g. https://proxmox:8006/api2/json)
#   PM_TOKEN_ID      - Proxmox API token ID (e.g. user@pam!token)
#   PM_TOKEN_SECRET  - Proxmox API token secret
#   NODE             - Proxmox node name
#   STORAGE          - Proxmox storage ID (e.g. truenas)
#   FILENAME         - Target ISO filename
#   ISO_URL          - URL to download the ISO from

for var in PM_API_URL PM_TOKEN_ID PM_TOKEN_SECRET NODE STORAGE FILENAME ISO_URL; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set" >&2
    exit 1
  fi
done

API_BASE="${PM_API_URL%/}"
AUTH_HEADER="Authorization: PVEAPIToken=${PM_TOKEN_ID}=${PM_TOKEN_SECRET}"

api_get() {
  curl -fsSL --insecure -H "$AUTH_HEADER" "$1"
}

# Check if the ISO already exists in storage
echo "Checking if ${FILENAME} already exists on ${STORAGE}..."
EXISTING=$(api_get "${API_BASE}/nodes/${NODE}/storage/${STORAGE}/content" | jq -r --arg volid "${STORAGE}:iso/${FILENAME}" '.data[]? | select(.volid == $volid) | .volid')

if [[ -n "$EXISTING" ]]; then
  echo "ISO already exists: ${EXISTING}. Skipping download."
  exit 0
fi

# Download ISO locally
TMPFILE=$(mktemp "${TMPDIR:-/tmp}/${FILENAME}.XXXXXX")
trap 'rm -f "$TMPFILE"' EXIT

echo "Downloading ${FILENAME} from ${ISO_URL} to local machine..."
HTTP_CODE=$(curl -sSL -o "$TMPFILE" -w "%{http_code}" "$ISO_URL")

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "ERROR: Download failed with HTTP ${HTTP_CODE}" >&2
  echo "URL: ${ISO_URL}" >&2
  echo "Response: $(head -c 500 "$TMPFILE")" >&2
  exit 1
fi

echo "Local download complete ($(du -h "$TMPFILE" | cut -f1))."

# Upload ISO to Proxmox storage
echo "Uploading ${FILENAME} to ${STORAGE} on ${NODE}..."
RESPONSE=$(curl -fsSL --insecure -H "$AUTH_HEADER" -X POST \
  -F "content=iso" \
  -F "filename=@${TMPFILE};filename=${FILENAME}" \
  "${API_BASE}/nodes/${NODE}/storage/${STORAGE}/upload")

UPID=$(echo "$RESPONSE" | jq -r '.data')

if [[ -z "$UPID" || "$UPID" == "null" ]]; then
  echo "ERROR: Failed to start upload. Response: ${RESPONSE}" >&2
  exit 1
fi

echo "Upload task started: ${UPID}"

# Poll task status until completion
ENCODED_UPID=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${UPID}', safe=''))")

while true; do
  sleep 5
  STATUS_RESPONSE=$(api_get "${API_BASE}/nodes/${NODE}/tasks/${ENCODED_UPID}/status")
  STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.data.status')

  if [[ "$STATUS" == "stopped" ]]; then
    EXIT_STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.data.exitstatus')
    if [[ "$EXIT_STATUS" == "OK" ]]; then
      echo "ISO uploaded successfully: ${STORAGE}:iso/${FILENAME}"
      exit 0
    else
      echo "ERROR: Upload task failed with exit status: ${EXIT_STATUS}" >&2
      exit 1
    fi
  fi

  echo "Upload in progress..."
done
