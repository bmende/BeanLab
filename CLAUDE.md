# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BeanLab is a home lab Kubernetes (k3s) cluster managed via GitOps. Two physical nodes — **wasabi** (server/control plane, i5 13th gen, 64GB RAM, NVIDIA 1650 Super) and **horseradish** (agent, i7 4th gen, 32GB RAM, DVD drive, ~1TB SSD for media) — run four self-hosted services: Jellyfin, a media ripping pipeline (MakeMKV + HandBrake), Home Assistant, and beanJAMinBOT.

All deployments are managed by **Flux CD** watching the `main` branch. No `kubectl apply` — push YAML to git and Flux reconciles.

## Architecture

### Repo Structure (planned)

```
BeanServer/
├── clusters/beanlab/
│   ├── flux-system/          # Flux bootstrap (auto-generated)
│   ├── infrastructure.yaml   # Kustomization → infrastructure/
│   └── apps.yaml             # Kustomization → apps/
├── infrastructure/           # cert-manager, traefik, storage, NFS
├── apps/                     # jellyfin, homeassistant, beanjaminbot, media-pipeline
├── scripts/
│   ├── setup-server.sh       # wasabi provisioning
│   └── setup-agent.sh        # horseradish provisioning
└── docs/design-plans/
```

### Key Design Decisions

- **Flux Kustomization layers**: `flux-system → infrastructure → apps` (dependency ordering)
- **Node affinity**: Media workloads (Jellyfin, MakeMKV) pinned to horseradish; Home Assistant and beanJAMinBOT on wasabi
- **Storage**: Local PVs for horseradish media (`/srv/media/`), local-path provisioner for app config/state, NFS export from horseradish for cross-node media access
- **Home Assistant** uses `hostNetwork: true` for mDNS device discovery
- **Secrets**: Manual `kubectl create secret` initially; SOPS is future upgrade path
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

## Design Plan

The full design plan with acceptance criteria and implementation phases is at `docs/design-plans/2026-03-09-beanlab-infra.md`.
