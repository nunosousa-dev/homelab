#!/bin/zsh
set -euo pipefail

# =============================================================================
# Arr-Stack PVC Recovery Script
# =============================================================================
# This script recovers arr-stack apps by rebinding them to their original
# Released PVs that still contain the configuration data.
#
# Run each step manually or uncomment the "execute" sections as needed.
# =============================================================================

NAMESPACE="arr-stack"
APPS=(sonarr radarr prowlarr lidarr bazarr qbittorrent tdarr whisparr)
STORAGE_CLASS="truenas-iscsi-retain"

# App config sizes (must match values.yaml)
declare -A APP_SIZES
APP_SIZES[sonarr]="5Gi"
APP_SIZES[radarr]="5Gi"
APP_SIZES[prowlarr]="2Gi"
APP_SIZES[lidarr]="5Gi"
APP_SIZES[bazarr]="2Gi"
APP_SIZES[qbittorrent]="2Gi"
APP_SIZES[tdarr]="5Gi"
APP_SIZES[whisparr]="5Gi"

echo "============================================="
echo "STEP 1: Identify Released PVs"
echo "============================================="
echo ""
echo "These are the Released PVs in your cluster:"
echo ""
kubectl get pv | grep -E "Released|CAPACITY"
echo ""
echo "Describe each to identify which app it belonged to:"
echo "(Look at spec.claimRef.name for the original PVC name)"
echo ""

RELEASED_PVS=$(kubectl get pv -o json | jq -r '.items[] | select(.status.phase=="Released") | select(.spec.claimRef.namespace=="arr-stack") | "\(.metadata.name) \(.spec.claimRef.name)"')

if [ -z "$RELEASED_PVS" ]; then
    echo "ERROR: No Released PVs found in namespace $NAMESPACE"
    echo "Check manually: kubectl get pv -o wide"
    exit 1
fi

echo "Found Released PVs for arr-stack:"
echo "$RELEASED_PVS"
echo ""

# Build a map of PVC name -> PV name
declare -A PVC_TO_PV
while IFS=' ' read -r pv_name pvc_name; do
    PVC_TO_PV[$pvc_name]=$pv_name
    echo "  $pvc_name -> $pv_name"
done <<< "$RELEASED_PVS"

echo ""
echo "============================================="
echo "STEP 2: Scale down deployments"
echo "============================================="
echo ""
read -q "REPLY?Scale down all arr-stack deployments? (y/N) " || true
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for app in "${APPS[@]}"; do
        deploy_name="$app"
        # tdarr has a different deployment name
        if [[ "$app" == "tdarr" ]]; then
            deploy_name="tdarr-server"
        fi
        echo "Scaling down $deploy_name..."
        kubectl -n "$NAMESPACE" scale deployment "$deploy_name" --replicas=0 2>/dev/null || echo "  (deployment $deploy_name not found, skipping)"
    done
    # Also scale tdarr-node if it exists
    kubectl -n "$NAMESPACE" scale deployment tdarr-node --replicas=0 2>/dev/null || true
    echo "All deployments scaled to 0."
else
    echo "Skipped. Run manually:"
    echo "  kubectl -n $NAMESPACE scale deployment sonarr radarr prowlarr lidarr bazarr qbittorrent tdarr-server whisparr --replicas=0"
    exit 0
fi

echo ""
echo "============================================="
echo "STEP 3: Delete new (empty) PVCs"
echo "============================================="
echo ""
echo "Current PVCs in $NAMESPACE:"
kubectl -n "$NAMESPACE" get pvc
echo ""
read -q "REPLY?Delete the current (empty) config PVCs? (y/N) " || true
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for app in "${APPS[@]}"; do
        pvc_name="${app}-config"
        echo "Deleting PVC $pvc_name..."
        kubectl -n "$NAMESPACE" delete pvc "$pvc_name" --ignore-not-found
    done
    echo "Empty PVCs deleted."
else
    echo "Skipped."
    exit 0
fi

echo ""
echo "============================================="
echo "STEP 4: Patch Released PVs (remove claimRef)"
echo "============================================="
echo ""
read -q "REPLY?Remove claimRef from Released PVs to make them Available? (y/N) " || true
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for pvc_name in "${(k)PVC_TO_PV[@]}"; do
        pv_name="${PVC_TO_PV[$pvc_name]}"
        echo "Patching PV $pv_name (was bound to $pvc_name)..."
        kubectl patch pv "$pv_name" --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
    done
    echo "All PVs patched to Available."
else
    echo "Skipped."
    exit 0
fi

echo ""
echo "============================================="
echo "STEP 5: Recreate PVCs with volumeName binding"
echo "============================================="
echo ""
read -q "REPLY?Create new PVCs bound to the original PVs? (y/N) " || true
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for app in "${APPS[@]}"; do
        pvc_name="${app}-config"
        if [ -z "${PVC_TO_PV[$pvc_name]+x}" ]; then
            echo "  WARNING: No Released PV found for $pvc_name, skipping."
            continue
        fi
        pv_name="${PVC_TO_PV[$pvc_name]}"
        size="${APP_SIZES[$app]}"
        echo "Creating PVC $pvc_name -> PV $pv_name ($size)..."
        kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $pvc_name
  namespace: $NAMESPACE
spec:
  storageClassName: $STORAGE_CLASS
  volumeName: $pv_name
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $size
EOF
    done
    echo ""
    echo "Verifying PVC status:"
    kubectl -n "$NAMESPACE" get pvc
else
    echo "Skipped."
    exit 0
fi

echo ""
echo "============================================="
echo "STEP 6: Scale deployments back up"
echo "============================================="
echo ""
read -q "REPLY?Scale all arr-stack deployments back up? (y/N) " || true
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for app in "${APPS[@]}"; do
        deploy_name="$app"
        if [[ "$app" == "tdarr" ]]; then
            deploy_name="tdarr-server"
        fi
        echo "Scaling up $deploy_name..."
        kubectl -n "$NAMESPACE" scale deployment "$deploy_name" --replicas=1 2>/dev/null || echo "  (deployment $deploy_name not found, skipping)"
    done
    kubectl -n "$NAMESPACE" scale deployment tdarr-node --replicas=1 2>/dev/null || true
    echo "All deployments scaled to 1."
else
    echo "Skipped."
fi

echo ""
echo "============================================="
echo "STEP 7: Verify"
echo "============================================="
echo ""
echo "PVC status:"
kubectl -n "$NAMESPACE" get pvc
echo ""
echo "Pod status (wait a moment for pods to start):"
kubectl -n "$NAMESPACE" get pods
echo ""
echo "============================================="
echo "DONE! Monitor pods with:"
echo "  kubectl -n $NAMESPACE get pods -w"
echo "============================================="
