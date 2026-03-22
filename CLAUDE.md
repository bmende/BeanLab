# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BeanLab is a home lab Kubernetes (k3s) cluster managed via GitOps. Two physical nodes — **wasabi** (server/control plane, i5 13th gen, 64GB RAM, NVIDIA 1650 Super) and **horseradish** (agent, i7 4th gen, 16GB RAM, DVD drive, ~1TB SSD for media) — run four self-hosted services: Jellyfin, a media ripping pipeline (MakeMKV + HandBrake), Home Assistant, and beanJAMinBOT.

All deployments are managed by **Flux CD** watching the `master` branch. No `kubectl apply` — push YAML to git and Flux reconciles.

**The `master` branch has branch protections on GitHub.** All changes must go through a PR — never commit directly to `master`.

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
│   ├── coredns-lan/              # LAN DNS server (CoreDNS, hostPort 53, wasabi)
│   ├── headlamp/                 # Cluster dashboard (HelmRelease, NodePort)
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
- **MakeMKV security**: Runs in `privileged` mode — required for SCSI subsystem access to the optical drive. Individual capabilities (`SYS_ADMIN`, `SYS_RAWIO`) were insufficient. Both `/dev/sr0` (block device) and `/dev/sg0` (SCSI generic) are passed through
- **Headlamp** cluster dashboard deployed as Flux HelmRelease in `headlamp` namespace, accessible via NodePort on LAN
- **CoreDNS LAN** authoritative DNS server for LAN zones, deployed in `dns` namespace on wasabi via `hostPort: 53`; zone files are read from `/etc/coredns-lan/zones` on the host (auto-reloaded every 10s); forwards non-local queries to `8.8.8.8`/`8.8.4.4`
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
- **ClusterIssuer** email field is omitted — Let's Encrypt no longer stores or uses contact emails (as of June 2025)
- **`/dev/sr0`** (optical drive) is a `BlockDevice`; **`/dev/sg0`** (SCSI generic) is a `CharDevice` — both required for MakeMKV
- **`nfs-common`** must be installed on the server node (wasabi) for NFS mounts — handled in `setup-server.sh`
- **Provisioning scripts** use generic terms (server/agent), not node hostnames — configurable via env vars (`NODE_LABELS`, `MEDIA_DIR`, `K3S_TOKEN`, `K3S_URL`)
- **Flux bootstrap** requires a GitHub PAT (Personal Access Token) with `repo` scope — one-time use, can be revoked after bootstrap creates its own deploy key

## Contracts and Invariants

- **All app deployments live in `default` namespace** — no custom namespaces for apps
- **cert-manager lives in `cert-manager` namespace** (defined in `infrastructure/cert-manager/namespace.yaml`)
- **Headlamp lives in `headlamp` namespace** (defined in `infrastructure/headlamp/namespace.yaml`) — access via Ingress (`${HEADLAMP_DOMAIN}`), authenticate with `kubectl create token headlamp -n headlamp`
- **CoreDNS LAN lives in `dns` namespace** (defined in `infrastructure/coredns-lan/namespace.yaml`) — uses `hostPort: 53` on wasabi; zone files must be placed in `/etc/coredns-lan/zones/` on the host as standard BIND-format zone files named `db.<zone>`
- **Flux Kustomization dependency chain**: `apps` dependsOn `infrastructure`; `cert-manager-issuers` dependsOn `infrastructure`
- **All Flux Kustomizations use `prune: true` and `wait: true`** with 10m reconciliation interval
- **NFS export path**: `/srv/media` on agent node, exported with `rw,sync,no_subtree_check,no_root_squash`
- **Media directory layout**: `/srv/media/library` (finished media) and `/srv/media/ripping` (MakeMKV output)
- **Script env vars**: `setup-server.sh` requires `K3S_TOKEN`; `setup-agent.sh` requires `K3S_URL` + `K3S_TOKEN`; `bootstrap-flux.sh` requires `GITHUB_USER` + `GITHUB_TOKEN`

## Flux Variable Substitution

Configurable values are **not committed to git**. Instead, manifests use `${VAR_NAME}` placeholders that Flux substitutes at reconciliation time from a `beanlab-config` ConfigMap in the cluster.

**Variables** are defined in `config.env` (gitignored) in the project root. Each variable documents which manifest uses it. Edit that file, then apply:

```bash
kubectl -n flux-system create configmap beanlab-config \
  --from-env-file=config.env --dry-run=client -o yaml | kubectl apply -f -
```

**Additional manual secrets:**
- `beanjaminbot-auth` secret must be created manually (see `apps/beanjaminbot/README-secrets.md`)

## Design Plan

The full design plan with acceptance criteria and implementation phases is at `docs/design-plans/2026-03-09-beanlab-infra.md`.

<!-- Freshness: 2026-03-20 -->
