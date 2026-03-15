#!/bin/bash
# setup-agent.sh — Install k3s agent and configure media infrastructure
# Usage: K3S_URL=https://<server-ip>:6443 K3S_TOKEN=<shared-secret> ./setup-agent.sh
#
# Idempotent: safe to re-run. All operations check existing state before acting.

set -euo pipefail

# --- Configuration -----------------------------------------------------------
K3S_URL="${K3S_URL:?Error: K3S_URL must be set (e.g. https://192.168.1.x:6443)}"
K3S_TOKEN="${K3S_TOKEN:?Error: K3S_TOKEN must be set}"
NODE_LABELS="${NODE_LABELS:-node-role.beanlab/media=true}"
MEDIA_DIR="${MEDIA_DIR:-/srv/media}"

# --- Install k3s agent -------------------------------------------------------
echo "Installing k3s agent..."
curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -s - \
    --node-label "$NODE_LABELS"

# --- Create media directories ------------------------------------------------
echo "Creating media directories..."
sudo mkdir -p "$MEDIA_DIR/library" "$MEDIA_DIR/ripping"

# --- Install and configure NFS server ----------------------------------------
echo "Installing NFS server..."
sudo apt-get update -qq
sudo apt-get install -y -qq nfs-kernel-server

# Configure NFS export (idempotent: only add if not already present)
NFS_EXPORT="$MEDIA_DIR *(rw,sync,no_subtree_check,no_root_squash)"
if ! grep -qF "$MEDIA_DIR " /etc/exports 2>/dev/null; then
    echo "$NFS_EXPORT" | sudo tee -a /etc/exports >/dev/null
    echo "Added NFS export for $MEDIA_DIR"
else
    echo "NFS export for $MEDIA_DIR already configured"
fi

sudo exportfs -a
sudo systemctl enable --now nfs-server

# --- Configure optical drive permissions --------------------------------------
echo "Configuring optical drive permissions..."

# Ensure cdrom group exists and current user is in it
sudo usermod -a -G cdrom "$(whoami)" 2>/dev/null || true

# Create udev rule for optical drive (idempotent: overwrites if exists)
sudo tee /etc/udev/rules.d/90-optical-drive.rules >/dev/null <<'UDEV'
SUBSYSTEM=="block", KERNEL=="sr*", GROUP="cdrom", MODE="0660"
UDEV
sudo udevadm control --reload-rules
sudo udevadm trigger

# --- Verify ------------------------------------------------------------------
echo ""
echo "=== k3s agent setup complete ==="
echo "Media directories:"
ls -la "$MEDIA_DIR/"
echo ""
echo "NFS exports:"
sudo exportfs -v
echo ""
echo "Optical drive:"
ls -la /dev/sr0 2>/dev/null || echo "/dev/sr0 not found (no disc inserted or no drive)"
