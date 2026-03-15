# BeanLab Infrastructure Implementation Plan

**Goal:** Build a 2-node k3s cluster managed via GitOps with deployments for Jellyfin, media ripping pipeline, Home Assistant, and beanJAMinBOT.

**Architecture:** Two physical nodes (server + agent) joined into a k3s cluster. Flux CD watches the main branch and reconciles cluster state from YAML manifests. Layered Kustomization ordering ensures infrastructure is ready before apps deploy.

**Tech Stack:** k3s, Flux CD, Traefik, cert-manager, NFS, shell scripts (bash)

**Scope:** 7 phases from original design (phases 1-7)

**Codebase verified:** 2026-03-10 — greenfield repo confirmed (only CLAUDE.md and design plan exist)

---

## Acceptance Criteria Coverage

This phase implements and verifies:

### beanlab-infra.AC1: Cluster is reproducibly provisioned from shell scripts
- **beanlab-infra.AC1.1 Success:** Running `setup-server.sh` on wasabi installs k3s server and applies node labels
- **beanlab-infra.AC1.2 Success:** Running `setup-agent.sh` on horseradish installs k3s agent and joins the cluster
- **beanlab-infra.AC1.3 Success:** Both nodes appear as Ready in `kubectl get nodes`
- **beanlab-infra.AC1.4 Success:** Scripts are idempotent — re-running produces no errors or changes
- **beanlab-infra.AC1.5 Success:** Node labels (`node-role.beanlab/media`, `node-role.beanlab/streaming`) are correctly applied

---

<!-- START_TASK_1 -->
### Task 1: Create repo directory structure and .gitignore

**Verifies:** None (infrastructure scaffolding)

**Files:**
- Create: `clusters/beanlab/.gitkeep`
- Create: `infrastructure/.gitkeep`
- Create: `apps/.gitkeep`
- Create: `scripts/` (populated by Tasks 2-3)
- Create: `.gitignore`

**Step 1: Create directory structure with placeholder files**

```bash
mkdir -p clusters/beanlab infrastructure apps scripts
touch clusters/beanlab/.gitkeep infrastructure/.gitkeep apps/.gitkeep
```

**Step 2: Create `.gitignore`**

```gitignore
# k3s
*.kubeconfig

# Editor
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Secrets - never commit
*.secret
*.key
```

**Step 3: Verify operationally**

```bash
ls -la clusters/beanlab/ infrastructure/ apps/ scripts/
cat .gitignore
```

Expected: All directories exist with `.gitkeep` files, `.gitignore` contains expected content.

**Step 4: Commit**

```bash
git add clusters/ infrastructure/ apps/ scripts/ .gitignore
git commit -m "chore: initialize repo directory structure"
```
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create scripts/setup-server.sh

**Verifies:** beanlab-infra.AC1.1, beanlab-infra.AC1.4, beanlab-infra.AC1.5

**Files:**
- Create: `scripts/setup-server.sh`

**Step 1: Create the script**

```bash
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
echo "Installing k3s server..."
curl -sfL https://get.k3s.io | K3S_TOKEN="$K3S_TOKEN" sh -s - \
    --write-kubeconfig-mode 644 \
    --node-label "$NODE_LABELS"

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
```

**Step 2: Make executable**

```bash
chmod +x scripts/setup-server.sh
```

**Step 3: Verify operationally**

```bash
bash -n scripts/setup-server.sh  # Syntax check
head -5 scripts/setup-server.sh  # Verify shebang and set flags
```

Expected: No syntax errors, shebang is `#!/bin/bash`, `set -euo pipefail` present.

**Step 4: Commit**

```bash
git add scripts/setup-server.sh
git commit -m "feat: add k3s server provisioning script"
```
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Create scripts/setup-agent.sh

**Verifies:** beanlab-infra.AC1.2, beanlab-infra.AC1.3, beanlab-infra.AC1.4, beanlab-infra.AC1.5

**Files:**
- Create: `scripts/setup-agent.sh`

**Step 1: Create the script**

```bash
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
```

**Step 2: Make executable**

```bash
chmod +x scripts/setup-agent.sh
```

**Step 3: Verify operationally**

```bash
bash -n scripts/setup-agent.sh  # Syntax check
head -5 scripts/setup-agent.sh  # Verify shebang and set flags
```

Expected: No syntax errors, shebang is `#!/bin/bash`, `set -euo pipefail` present.

**Step 4: Commit**

```bash
git add scripts/setup-agent.sh
git commit -m "feat: add k3s agent provisioning script"
```
<!-- END_TASK_3 -->
