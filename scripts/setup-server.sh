#!/bin/bash
# setup-server.sh — Install k3s server (control plane node)
# Usage: K3S_TOKEN=<shared-secret> ./setup-server.sh
#
# Idempotent: safe to re-run. The k3s install script detects existing
# installations and updates the service configuration.

set -euo pipefail

# --- Configuration -----------------------------------------------------------
K3S_TOKEN="${K3S_TOKEN:?Error: K3S_TOKEN must be set}"
NODE_LABELS="${NODE_LABELS:-node-role.beanlab/streaming=true}"

# --- Install NFS client (needed to mount NFS volumes from agent node) --------
echo "Installing NFS client packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq nfs-common

# --- Install k3s server ------------------------------------------------------
# Unset K3S_URL to prevent the installer from treating this node as an agent
unset K3S_URL

echo "Installing k3s server..."
curl -sfL https://get.k3s.io | K3S_TOKEN="$K3S_TOKEN" sh -s - server \
    --write-kubeconfig-mode 644 \
    --node-label "$NODE_LABELS"

# --- Copy kubeconfig to default location --------------------------------------
echo "Setting up kubeconfig..."
mkdir -p "$HOME/.kube"
cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"

# --- Wait for node to be ready -----------------------------------------------
echo "Waiting for k3s to be ready..."
until sudo k3s kubectl get nodes &>/dev/null; do
    sleep 2
done

# --- Verify ------------------------------------------------------------------
echo ""
echo "=== k3s server is ready ==="
sudo k3s kubectl get nodes
echo ""
echo "Node token (provide this to the agent node):"
sudo cat /var/lib/rancher/k3s/server/node-token
echo ""
echo "Kubeconfig is at: /etc/rancher/k3s/k3s.yaml"
