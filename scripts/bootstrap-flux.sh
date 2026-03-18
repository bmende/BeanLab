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
    echo "Installing Flux CLI..."
    curl -s https://fluxcd.io/install.sh | sudo bash
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
