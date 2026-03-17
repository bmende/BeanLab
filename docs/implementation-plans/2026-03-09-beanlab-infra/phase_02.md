# BeanLab Infrastructure Implementation Plan

**Goal:** Build a 2-node k3s cluster managed via GitOps with deployments for Jellyfin, media ripping pipeline, Home Assistant, and beanJAMinBOT.

**Architecture:** Two physical nodes (server + agent) joined into a k3s cluster. Flux CD watches the main branch and reconciles cluster state from YAML manifests. Layered Kustomization ordering ensures infrastructure is ready before apps deploy.

**Tech Stack:** k3s, Flux CD, Traefik, cert-manager, NFS, shell scripts (bash)

**Scope:** 7 phases from original design (phases 1-7)

**Codebase verified:** 2026-03-10 — greenfield repo confirmed

---

## Acceptance Criteria Coverage

This phase implements and verifies:

### beanlab-infra.AC2: Apps deployed and updated via Flux CD
- **beanlab-infra.AC2.1 Success:** Flux is running and `flux get kustomizations` shows all kustomizations reconciled
- **beanlab-infra.AC2.2 Success:** Pushing a manifest change to `main` triggers reconciliation within configured interval
- **beanlab-infra.AC2.3 Success:** Infrastructure kustomization reconciles before apps kustomization (dependency ordering)
- **beanlab-infra.AC2.4 Failure:** Invalid manifest pushed to repo results in Flux reporting error, existing deployments unaffected

---

<!-- START_TASK_1 -->
### Task 1: Create initial kustomization.yaml stubs for infrastructure/ and apps/

**Verifies:** None (infrastructure scaffolding)

**Files:**
- Create: `infrastructure/kustomization.yaml`
- Create: `apps/kustomization.yaml`

**Step 1: Create infrastructure/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
```

**Step 2: Create apps/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
```

**Step 3: Verify operationally**

```bash
cat infrastructure/kustomization.yaml
cat apps/kustomization.yaml
```

Expected: Both files contain valid YAML with empty resources list.

**Step 4: Commit**

```bash
git add infrastructure/kustomization.yaml apps/kustomization.yaml
git commit -m "chore: add empty kustomization stubs for infrastructure and apps"
```
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create clusters/beanlab/infrastructure.yaml

**Verifies:** beanlab-infra.AC2.3

**Files:**
- Create: `clusters/beanlab/infrastructure.yaml`

**Step 1: Create the Flux Kustomization resource**

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure
  prune: true
  wait: true
```

**Step 2: Verify operationally**

```bash
cat clusters/beanlab/infrastructure.yaml
```

Expected: Valid YAML with sourceRef pointing to `flux-system`, path `./infrastructure`, `prune: true`, `wait: true`.

**Step 3: Commit**

```bash
git add clusters/beanlab/infrastructure.yaml
git commit -m "feat: add Flux Kustomization for infrastructure layer"
```
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Create clusters/beanlab/apps.yaml

**Verifies:** beanlab-infra.AC2.3

**Files:**
- Create: `clusters/beanlab/apps.yaml`

**Step 1: Create the Flux Kustomization resource with dependency on infrastructure**

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps
  prune: true
  wait: true
  dependsOn:
    - name: infrastructure
```

**Step 2: Verify operationally**

```bash
cat clusters/beanlab/apps.yaml
```

Expected: Valid YAML with `dependsOn` referencing `infrastructure`, ensuring apps reconcile only after infrastructure is ready.

**Step 3: Commit**

```bash
git add clusters/beanlab/apps.yaml
git commit -m "feat: add Flux Kustomization for apps layer with infrastructure dependency"
```
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Document Flux bootstrap procedure

**Verifies:** beanlab-infra.AC2.1, beanlab-infra.AC2.2, beanlab-infra.AC2.4

**Files:**
- Create: `scripts/bootstrap-flux.sh`

**Step 1: Create the bootstrap script**

This is a helper script that documents and runs the Flux bootstrap process. It must be run from a machine with kubectl access to the cluster and a GitHub PAT.

```bash
#!/bin/bash
# bootstrap-flux.sh — Bootstrap Flux CD into the k3s cluster
# Usage: GITHUB_TOKEN=<pat> GITHUB_USER=<username> ./bootstrap-flux.sh
#
# Prerequisites:
#   - kubectl configured with access to the k3s cluster
#   - flux CLI installed (curl -s https://fluxcd.io/install.sh | sudo bash)
#   - GitHub PAT with 'repo' scope exported as GITHUB_TOKEN
#
# This script is idempotent: re-running updates Flux to the latest version.

set -euo pipefail

# --- Configuration -----------------------------------------------------------
GITHUB_USER="${GITHUB_USER:?Error: GITHUB_USER must be set}"
GITHUB_TOKEN="${GITHUB_TOKEN:?Error: GITHUB_TOKEN must be set}"
GITHUB_REPO="${GITHUB_REPO:-BeanLab}"
FLUX_BRANCH="${FLUX_BRANCH:-master}"
FLUX_PATH="${FLUX_PATH:-clusters/beanlab}"

# --- Pre-flight checks -------------------------------------------------------
echo "Checking prerequisites..."

if ! command -v flux &>/dev/null; then
    echo "Error: flux CLI not found. Install with: curl -s https://fluxcd.io/install.sh | sudo bash"
    exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
    echo "Error: kubectl cannot reach the cluster. Is kubeconfig configured?"
    exit 1
fi

flux check --pre

# --- Bootstrap Flux -----------------------------------------------------------
echo "Bootstrapping Flux CD..."
export GITHUB_TOKEN

flux bootstrap github \
    --owner="$GITHUB_USER" \
    --repository="$GITHUB_REPO" \
    --branch="$FLUX_BRANCH" \
    --path="$FLUX_PATH" \
    --personal

# --- Verify -------------------------------------------------------------------
echo ""
echo "=== Flux bootstrap complete ==="
echo ""
echo "Kustomizations:"
flux get kustomizations
echo ""
echo "Git repository source:"
flux get sources git
```

**Step 2: Make executable**

```bash
chmod +x scripts/bootstrap-flux.sh
```

**Step 3: Verify operationally**

```bash
bash -n scripts/bootstrap-flux.sh  # Syntax check
```

Expected: No syntax errors.

**Step 4: Commit**

```bash
git add scripts/bootstrap-flux.sh
git commit -m "feat: add Flux CD bootstrap script"
```
<!-- END_TASK_4 -->
