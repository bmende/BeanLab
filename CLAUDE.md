# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BeanLab is a home lab Kubernetes (k3s) cluster managed via GitOps. Two physical nodes — **wasabi** (server/control plane, i5 13th gen, 64GB RAM, NVIDIA 1650 Super) and **horseradish** (agent, i7 4th gen, 32GB RAM, DVD drive, ~1TB SSD for media) — run four self-hosted services: Jellyfin, a media ripping pipeline (MakeMKV + HandBrake), Home Assistant, and beanJAMinBOT.

All deployments are managed by **Flux CD** watching the `master` branch. No `kubectl apply` — push YAML to git and Flux reconciles.

## Architecture

### Repo Structure

```
BeanLab/
├── clusters/beanlab/
│   ├── flux-system/              # Flux bootstrap (auto-generated)
│   ├── infrastructure.yaml       # Kustomization → infrastructure/
│   ├── cert-manager-issuers.yaml # Kustomization → infrastructure/cert-manager-issuers/
│   └── apps.yaml                 # Kustomization → apps/ (dependsOn: infrastructure)
├── infrastructure/
│   ├── cert-manager/             # HelmRelease, HelmRepo, Namespace
│   ├── cert-manager-issuers/     # ClusterIssuer (separate layer, dependsOn: infrastructure)
│   ├── storage/                  # Local PVs, NFS PV, StorageClass
│   └── traefik/                  # HelmChartConfig for k3s-bundled Traefik
├── apps/
│   ├── jellyfin/                 # Deployment, Service, Ingress, PVCs
│   ├── media-pipeline/           # MakeMKV + HandBrake deployments
│   ├── homeassistant/            # Deployment (hostNetwork), Service, PVC
│   └── beanjaminbot/             # Deployment, PVCs, Dockerfile, secrets docs
├── scripts/
│   ├── setup-server.sh           # wasabi provisioning (k3s server + nfs-common)
│   ├── setup-agent.sh            # horseradish provisioning (k3s agent + NFS server + media dirs)
│   └── bootstrap-flux.sh         # Flux CD bootstrap (requires GitHub PAT)
└── docs/
    ├── design-plans/
    └── implementation-plans/
```

### Key Design Decisions

- **Flux Kustomization layers**: `flux-system → infrastructure → cert-manager-issuers / apps` (infrastructure must complete before issuers or apps)
- **Node affinity**: Media workloads (Jellyfin, MakeMKV, HandBrake) use `nodeSelector: node-role.beanlab/media: "true"` (horseradish); Home Assistant and beanJAMinBOT use `nodeSelector: node-role.beanlab/streaming: "true"` (wasabi)
- **Storage**: Local PVs for horseradish media (`/srv/media/`), local-path provisioner for app config/state, NFS PV for cross-node media access (requires `<AGENT_NODE_IP>` substitution)
- **Home Assistant** uses `hostNetwork: true` + `dnsPolicy: ClusterFirstWithHostNet` for mDNS device discovery
- **Secrets**: Manual `kubectl create secret` initially; SOPS is future upgrade path. beanJAMinBOT requires `beanjaminbot-auth` secret (see `apps/beanjaminbot/README-secrets.md`)
- **beanJAMinBOT image**: Deployment uses `<BOT_IMAGE>` placeholder — must be replaced with actual registry/image reference
- **MakeMKV security**: Requires `SYS_ADMIN` and `SYS_RAWIO` capabilities for optical drive ioctl/SCSI operations
- **All deployments** use `strategy: Recreate` (single-replica workloads with PVCs)
- **Provisioning scripts** must be idempotent

### Node Labels

- `node-role.beanlab/media: "true"` → horseradish
- `node-role.beanlab/streaming: "true"` → wasabi

## Implementation Plan

A detailed 7-phase implementation plan lives at `docs/implementation-plans/2026-03-09-beanlab-infra/`. Each phase has its own file (`phase_01.md` through `phase_07.md`) plus `test-requirements.md` mapping acceptance criteria to verification steps.

**Phases:**
1. Repository setup & node provisioning scripts
2. Flux CD bootstrap
3. Infrastructure — storage, NFS, cert-manager, Traefik
4. Jellyfin deployment
5. Media pipeline (MakeMKV + HandBrake)
6. Home Assistant deployment
7. beanJAMinBOT deployment

**Key implementation details discovered during planning:**
- **cert-manager ClusterIssuers** must be in a separate Flux Kustomization (`infrastructure/cert-manager-issuers/`) with `dependsOn: infrastructure`, because the ClusterIssuer CRD doesn't exist until cert-manager finishes installing
- **Default branch is `master`**, not `main` — Flux bootstrap script defaults to `master`
- **NFS PV** requires manual IP substitution (`<AGENT_NODE_IP>` placeholder) before deployment
- **ClusterIssuer** requires manual email substitution (`<YOUR_EMAIL>` placeholder)
- **`/dev/sr0`** (optical drive) is a `BlockDevice`, not `CharDevice`
- **`nfs-common`** must be installed on the server node (wasabi) for NFS mounts — handled in `setup-server.sh`
- **Provisioning scripts** use generic terms (server/agent), not node hostnames — configurable via env vars (`NODE_LABELS`, `MEDIA_DIR`, `K3S_TOKEN`, `K3S_URL`)
- **Flux bootstrap** requires a GitHub PAT (Personal Access Token) with `repo` scope — one-time use, can be revoked after bootstrap creates its own deploy key

## Contracts and Invariants

- **All app deployments live in `default` namespace** — no custom namespaces for apps
- **cert-manager lives in `cert-manager` namespace** (defined in `infrastructure/cert-manager/namespace.yaml`)
- **Flux Kustomization dependency chain**: `apps` dependsOn `infrastructure`; `cert-manager-issuers` dependsOn `infrastructure`
- **All Flux Kustomizations use `prune: true` and `wait: true`** with 10m reconciliation interval
- **NFS export path**: `/srv/media` on agent node, exported with `rw,sync,no_subtree_check,no_root_squash`
- **Media directory layout**: `/srv/media/library` (finished media) and `/srv/media/ripping` (MakeMKV output)
- **Script env vars**: `setup-server.sh` requires `K3S_TOKEN`; `setup-agent.sh` requires `K3S_URL` + `K3S_TOKEN`; `bootstrap-flux.sh` requires `GITHUB_USER` + `GITHUB_TOKEN`

## Placeholders Requiring Manual Substitution Before Deployment

- `<AGENT_NODE_IP>` in `infrastructure/storage/pv-media-nfs.yaml`
- `<YOUR_EMAIL>` in `infrastructure/cert-manager-issuers/clusterissuer.yaml`
- `<YOUR_DOMAIN>` in `apps/jellyfin/ingress.yaml` (lines 13, 16) — replace with DDNS domain (e.g., jellyfin.example.com)
- `<BOT_IMAGE>` in `apps/beanjaminbot/deployment.yaml`
- `beanjaminbot-auth` secret must be created manually (see `apps/beanjaminbot/README-secrets.md`)

## Design Plan

The full design plan with acceptance criteria and implementation phases is at `docs/design-plans/2026-03-09-beanlab-infra.md`.

<!-- Freshness: 2026-03-12 -->
