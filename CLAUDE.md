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

## Design Plan

The full design plan with acceptance criteria and implementation phases is at `docs/design-plans/2026-03-09-beanlab-infra.md`.
