#!/bin/bash

export CONTROL_PLANE_IP=10.0.100.100
export WORKER1_IP=10.0.100.101
export WORKER2_IP=10.0.100.102

talosctl gen config k8s-casinha-prd https://$CONTROL_PLANE_IP:6443 --output-dir _out --install-image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.9.0

talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file _out/controlplane.yaml

sleep 60

talosctl apply-config --insecure --nodes $WORKER1_IP --file _out/worker.yaml
talosctl apply-config --insecure --nodes $WORKER2_IP --file _out/worker.yaml

export TALOSCONFIG="_out/talosconfig"
talosctl config endpoint "$CONTROL_PLANE_IP"
talosctl config node "$CONTROL_PLANE_IP"

talosctl bootstrap

talosctl kubeconfig _out/

export KUBECONFIG="_out/kubeconfig"
