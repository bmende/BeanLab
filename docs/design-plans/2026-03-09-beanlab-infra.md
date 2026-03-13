# BeanLab Infrastructure Design

## Summary

This project builds the "beanlab" home lab Kubernetes cluster from scratch: two physical machines (wasabi and horseradish) joined into a lightweight k3s cluster, with all configuration, provisioning scripts, and application manifests living in the BeanServer repo. The cluster runs four self-hosted services — Jellyfin (media streaming), a two-stage media ripping and encoding pipeline (MakeMKV + HandBrake), Home Assistant (home automation), and beanJAMinBOT (a Twitch chat bot) — distributed across the two nodes based on hardware requirements and workload characteristics.

The high-level approach is GitOps: no application is deployed or updated by running commands directly against the cluster. Instead, Flux CD continuously watches the `main` branch of this repo and reconciles the cluster state to match what is declared in YAML manifests. A layered Kustomization structure (flux-system → infrastructure → apps) ensures that shared infrastructure like TLS certificate management and ingress routing is in place before any application is deployed. Node affinity rules pin workloads to the machine whose hardware they depend on — Jellyfin and the optical-drive-based ripping tool run on horseradish (which has the large SSD and DVD drive), while Home Assistant and beanJAMinBOT run on wasabi. Cross-node media access is bridged by an NFS export from horseradish, allowing the HandBrake encoding pod on wasabi to read and write back to horseradish's media storage.

## Definition of Done

A working 2-node k3s cluster (wasabi + horseradish) managed via GitOps (Flux CD), with deployment manifests for Jellyfin (with media ripping/encoding pipeline), Home Assistant, and beanJAMinBOT. The cluster is externally accessible via Traefik + DDNS + TLS. All cluster configuration, provisioning scripts, and app manifests live in the BeanServer repo.

**Success criteria:**
- The cluster is reproducibly provisioned from shell scripts in this repo
- Apps are deployed and updated via Flux CD watching this repo
- Jellyfin runs on horseradish serving media from horseradish's local storage and is accessible externally
- The media ripping pipeline runs on horseradish (which has the DVD drive and storage)
- Home Assistant is deployed and accessible
- beanJAMinBOT is deployed and running

**Nice to have (not required for done):**
- GPU-accelerated transcoding using wasabi's NVIDIA 1650 Super

**Out of scope:**
- Individual app development (beanJAMinBOT features, Home Assistant automations)
- Cloud infrastructure
- Terraform
- Migration of existing data

## Acceptance Criteria

### beanlab-infra.AC1: Cluster is reproducibly provisioned from shell scripts
- **beanlab-infra.AC1.1 Success:** Running `setup-server.sh` on wasabi installs k3s server and applies node labels
- **beanlab-infra.AC1.2 Success:** Running `setup-agent.sh` on horseradish installs k3s agent and joins the cluster
- **beanlab-infra.AC1.3 Success:** Both nodes appear as Ready in `kubectl get nodes`
- **beanlab-infra.AC1.4 Success:** Scripts are idempotent — re-running produces no errors or changes
- **beanlab-infra.AC1.5 Success:** Node labels (`node-role.beanlab/media`, `node-role.beanlab/streaming`) are correctly applied

### beanlab-infra.AC2: Apps deployed and updated via Flux CD
- **beanlab-infra.AC2.1 Success:** Flux is running and `flux get kustomizations` shows all kustomizations reconciled
- **beanlab-infra.AC2.2 Success:** Pushing a manifest change to `main` triggers reconciliation within configured interval
- **beanlab-infra.AC2.3 Success:** Infrastructure kustomization reconciles before apps kustomization (dependency ordering)
- **beanlab-infra.AC2.4 Failure:** Invalid manifest pushed to repo results in Flux reporting error, existing deployments unaffected

### beanlab-infra.AC3: Jellyfin runs on horseradish serving local media, accessible externally
- **beanlab-infra.AC3.1 Success:** Jellyfin pod runs on horseradish (verified by `kubectl get pod -o wide`)
- **beanlab-infra.AC3.2 Success:** Jellyfin can browse and play media files from `/srv/media/library/`
- **beanlab-infra.AC3.3 Success:** Adding a file to `/srv/media/library/` on the host makes it visible in Jellyfin after library scan
- **beanlab-infra.AC3.4 Success:** Jellyfin is accessible externally via DDNS domain with valid TLS certificate
- **beanlab-infra.AC3.5 Success:** Jellyfin config and database persist across pod restarts

### beanlab-infra.AC4: Media ripping pipeline runs on horseradish
- **beanlab-infra.AC4.1 Success:** MakeMKV pod runs on horseradish with access to optical drive
- **beanlab-infra.AC4.2 Success:** MakeMKV web UI is accessible on LAN
- **beanlab-infra.AC4.3 Success:** Ripped files appear in `/srv/media/ripping/` on horseradish
- **beanlab-infra.AC4.4 Success:** HandBrake pod runs on wasabi with NFS access to horseradish's media directory
- **beanlab-infra.AC4.5 Success:** Encoded files written by HandBrake appear in `/srv/media/library/` on horseradish
- **beanlab-infra.AC4.6 Success:** HandBrake web UI is accessible on LAN

### beanlab-infra.AC5: Home Assistant is deployed and accessible
- **beanlab-infra.AC5.1 Success:** Home Assistant pod runs on wasabi with host networking
- **beanlab-infra.AC5.2 Success:** Home Assistant web UI accessible on LAN at wasabi's IP:8123
- **beanlab-infra.AC5.3 Success:** mDNS device discovery finds WiFi devices on the LAN
- **beanlab-infra.AC5.4 Success:** Home Assistant config persists across pod restarts

### beanlab-infra.AC6: beanJAMinBOT is deployed and running
- **beanlab-infra.AC6.1 Success:** beanJAMinBOT pod runs on wasabi
- **beanlab-infra.AC6.2 Success:** Bot connects to Twitch IRC and responds to chat commands
- **beanlab-infra.AC6.3 Success:** Bot config (`config/`) and data (`data/`) persist across pod restarts
- **beanlab-infra.AC6.4 Success:** Credentials are stored as K8s Secret, not in plain text in manifests

## Glossary

- **k3s**: A lightweight, production-grade Kubernetes distribution from Rancher. Bundles common dependencies (Flannel, Traefik, local-path provisioner, embedded etcd) into a single binary. "Server" and "agent" are k3s terminology for control-plane node and worker node respectively.
- **Flux CD**: A GitOps operator that runs inside the cluster and continuously syncs cluster state to match YAML manifests in a git repository. Changes are deployed by pushing to git, not by running `kubectl apply` manually.
- **GitOps**: A deployment model where git is the single source of truth for infrastructure and application configuration. The cluster pulls its desired state from a repo rather than having state pushed to it imperatively.
- **Kustomization**: A Flux CD resource (distinct from a plain Kubernetes Kustomize overlay) that defines a source, a path within that source, and reconciliation behavior. Multiple Kustomizations can declare dependencies on each other to enforce ordering.
- **Traefik**: A reverse proxy and ingress controller bundled with k3s. Routes external HTTP/HTTPS traffic to the correct in-cluster service based on hostname or path rules.
- **cert-manager**: A Kubernetes add-on that automates provisioning and renewal of TLS certificates, typically from Let's Encrypt.
- **Let's Encrypt**: A free, automated certificate authority. cert-manager uses it to issue publicly trusted TLS certificates via ACME challenge.
- **ACME challenge (HTTP-01 / DNS-01)**: Protocols used to prove domain ownership to Let's Encrypt. HTTP-01 requires port 80 to be reachable; DNS-01 proves ownership via DNS record and avoids that requirement.
- **DDNS (Dynamic DNS)**: A service that keeps a DNS hostname pointed at a home IP address that may change over time.
- **Flannel**: A simple CNI plugin bundled with k3s that creates an overlay network so pods on different nodes can communicate.
- **NFS (Network File System)**: A protocol for mounting a remote filesystem over a network. Used here so the encoding pod on wasabi can access media on horseradish's disk.
- **PersistentVolume (PV)**: A Kubernetes resource representing provisioned storage (here, a directory on a node's local disk). Pods claim storage from PVs via PersistentVolumeClaims (PVCs).
- **local-path provisioner**: A dynamic storage provisioner bundled with k3s that automatically creates PersistentVolumes backed by directories on the node's local filesystem.
- **Node affinity**: A Kubernetes scheduling rule that constrains which node a pod can run on, based on node labels.
- **hostNetwork**: A Kubernetes pod setting that bypasses the cluster's virtual network and gives the pod direct access to the host's network interfaces. Required for Home Assistant's mDNS device discovery.
- **mDNS (Multicast DNS)**: A zero-configuration protocol for discovering services on a local network without a central DNS server. Used by smart home devices.
- **Jellyfin**: Open-source media server software. Organizes a media library and streams video/audio to clients.
- **MakeMKV**: Software that reads encrypted DVDs and Blu-rays and outputs them as MKV video files.
- **HandBrake**: Open-source video transcoder. Re-encodes raw ripped video files into compressed formats suitable for streaming.
- **NVENC**: NVIDIA's hardware video encoding API. Allows transcoding on the GPU rather than CPU. Listed as a future nice-to-have for wasabi's NVIDIA 1650 Super.
- **beanJAMinBOT**: A custom Twitch chat bot in a separate repo (`beanJAMinBOT`). Uses YAML config and flat-file data persistence.
- **K8s Secret**: A Kubernetes object for storing sensitive data separately from application manifests.
- **SOPS**: "Secrets OPerationS" — a tool for encrypting secret values so they can be safely committed to git. Mentioned as a future upgrade from manual secret creation.
- **etcd**: The distributed key-value store Kubernetes uses as its backing database. k3s embeds it on the server node.
- **ClusterIssuer**: A cert-manager resource that defines how certificates should be obtained (e.g., from Let's Encrypt). Cluster-scoped so all namespaces can use it.
- **Idempotent**: A property of a script meaning it can be run multiple times and produce the same result without errors or unintended side effects.

## Architecture

Two-node k3s cluster with wasabi as server (control plane + workloads) and horseradish as agent (workloads only). Flux CD manages all deployments via GitOps, watching the `main` branch of this repo.

### Cluster Topology

| Node | Role | CPU | RAM | GPU | Storage | Special Hardware |
|------|------|-----|-----|-----|---------|-----------------|
| wasabi | k3s server | i5 13th gen | 64 GB | NVIDIA 1650 Super | NVMe (OS) | None |
| horseradish | k3s agent | i7 4th gen | 32 GB | Older (TBD) | ~1TB SATA SSD (media) | DVD optical drive |

wasabi runs the control plane (API server, scheduler, controller-manager, embedded etcd), Flux CD controllers, cert-manager, and Traefik ingress controller. horseradish focuses on media workloads.

### Node Labels

- `node-role.beanlab/media: "true"` on horseradish — used by Jellyfin, MakeMKV, and storage-dependent pods
- `node-role.beanlab/streaming: "true"` on wasabi — used by beanJAMinBOT (audio requirement)

### Storage

Two storage mechanisms:

1. **Local PersistentVolumes** for horseradish's media library. A dedicated directory (`/srv/media/`) on horseradish's 1TB SSD, with subdirectories:
   - `/srv/media/library/` — organized media files served by Jellyfin
   - `/srv/media/ripping/` — in-progress rips and encodes

   Files remain accessible directly on the host filesystem. K8s mounts them into pods; it does not hide or move them.

2. **local-path provisioner** (ships with k3s) for application config/data. Each app gets a PVC for its own config and state. Since pods are pinned to specific nodes via affinity, local-path storage is safe.

3. **NFS export** from horseradish exposes `/srv/media/` to the cluster network. This enables the encoding pod on wasabi to read ripped files and write finished encodes back to horseradish's storage.

### Networking

- **Internal:** Flannel CNI (ships with k3s) handles pod-to-pod communication across nodes. K8s Services provide stable DNS names.
- **Ingress:** Traefik (ships with k3s) on wasabi handles external traffic on configurable ports. Router port-forwards to wasabi.
- **TLS:** cert-manager provisions and auto-renews Let's Encrypt certificates. Supports HTTP-01 or DNS-01 challenge (DNS-01 avoids needing port 80 open).
- **DDNS:** Existing DDNS service on the router points the domain to the home IP.
- **Home Assistant:** Uses `hostNetwork: true` on wasabi for mDNS device discovery on the LAN.

### Application Deployments

**Jellyfin** — horseradish, node affinity. Local PV for media library, local-path PVC for config/database. Traefik Ingress for external access with TLS.

**Home Assistant** — wasabi, `hostNetwork: true`. Local-path PVC for config/database. Traefik Ingress for external access (optional). Future: USB device passthrough for Zigbee/Z-Wave.

**beanJAMinBOT** — wasabi, node affinity (audio requirement, removable later). Requires a new production Dockerfile. Config (`config/`) and data (`data/`) via PVCs. Credentials (`botjamin_auth.yaml`) as a K8s Secret. Outbound-only to Twitch (IRC, EventSub WebSocket, Helix API). OAuth callback may need a NodePort or Ingress route.

**Media Pipeline — Ripping (MakeMKV)** — horseradish, `/dev/sr0` device passthrough. Community container image (e.g., `jlesage/docker-makemkv`) with web UI accessible on LAN only. Output to `/srv/media/ripping/`.

**Media Pipeline — Encoding (HandBrake)** — wasabi, NFS mount to horseradish's `/srv/media/`. Community container image (e.g., `jlesage/docker-handbrake`) with web UI on LAN only. Reads from `/srv/media/ripping/`, writes to `/srv/media/library/`. Software encoding initially; GPU-accelerated NVENC is a future nice-to-have.

### GitOps Flow

Flux CD watches `main` branch. Three Kustomization layers with dependency ordering:

```
flux-system (self-manages Flux)
    └── infrastructure (cert-manager, traefik config, storage classes, NFS)
            └── apps (jellyfin, homeassistant, beanjaminbot, media-pipeline)
```

Each app's Kustomization is independent — updating one app doesn't redeploy others. Secrets created manually via `kubectl create secret` initially, with SOPS as a future upgrade path for encrypted-in-git secrets.

### Repo Structure

```
BeanServer/
├── clusters/beanlab/
│   ├── flux-system/          # Flux bootstrap (auto-generated)
│   ├── infrastructure.yaml   # Kustomization pointing to infrastructure/
│   └── apps.yaml             # Kustomization pointing to apps/
├── infrastructure/
│   ├── cert-manager/         # CRDs, ClusterIssuer for Let's Encrypt
│   ├── traefik/              # Traefik config overrides
│   └── storage/              # StorageClasses, PVs for media, NFS PV config
├── apps/
│   ├── jellyfin/             # Deployment, PVC, Ingress, Service
│   ├── homeassistant/        # Deployment, PVC, Ingress, Service
│   ├── beanjaminbot/         # Deployment, PVC, Secret refs
│   └── media-pipeline/       # MakeMKV + HandBrake deployments
├── scripts/
│   ├── setup-server.sh       # wasabi: install k3s server, node labels
│   └── setup-agent.sh        # horseradish: install k3s agent, labels, NFS server setup, optical drive perms
└── docs/
    └── design-plans/
```

Note: NFS server configuration (exports, firewall rules) is handled by `scripts/setup-agent.sh` on the horseradish node. The NFS PersistentVolume definition lives in `infrastructure/storage/`.

## Existing Patterns

No existing codebase — this is a greenfield project. The BeanServer repo is empty.

beanJAMinBOT (in `~/Projects/beanJAMinBOT`) has an experimental Docker exploration directory (`docker-server-explore/`) with a UBI9-based Dockerfile for a separate Bottle web app, not the bot itself. A production Dockerfile for the bot needs to be created as part of this project. The bot uses YAML config files (not environment variables) and flat-file data persistence (YAML, JSON, CSV in `data/`).

The Flux monorepo structure follows the standard pattern from Flux CD documentation (`clusters/`, `infrastructure/`, `apps/` separation with Kustomization dependency ordering).

## Implementation Phases

<!-- START_PHASE_1 -->
### Phase 1: Repository Setup & Node Provisioning Scripts
**Goal:** Initialize the BeanServer repo structure and create idempotent shell scripts that install k3s on both nodes.

**Components:**
- Repo directory structure (`clusters/`, `infrastructure/`, `apps/`, `scripts/`)
- `scripts/setup-server.sh` — installs k3s server on wasabi, applies node labels
- `scripts/setup-agent.sh` — installs k3s agent on horseradish, applies node labels, configures optical drive permissions, installs NFS server packages

**Dependencies:** None (first phase)

**Done when:** k3s cluster is running with both nodes visible via `kubectl get nodes`, node labels are applied, scripts are idempotent (can be re-run safely)
<!-- END_PHASE_1 -->

<!-- START_PHASE_2 -->
### Phase 2: Flux CD Bootstrap
**Goal:** Bootstrap Flux CD into the cluster and verify it can reconcile from the repo.

**Components:**
- Flux bootstrap into `clusters/beanlab/flux-system/`
- `clusters/beanlab/infrastructure.yaml` — Kustomization pointing to `infrastructure/`
- `clusters/beanlab/apps.yaml` — Kustomization pointing to `apps/`
- Initial empty `infrastructure/` and `apps/` kustomization files

**Dependencies:** Phase 1 (running cluster)

**Done when:** Flux is running in the cluster, `flux get kustomizations` shows all kustomizations reconciled, pushing a change to the repo triggers reconciliation
<!-- END_PHASE_2 -->

<!-- START_PHASE_3 -->
### Phase 3: Infrastructure — Storage, NFS, cert-manager, Traefik
**Goal:** Set up cluster infrastructure: storage classes, NFS for cross-node media access, TLS certificate management, and Traefik ingress configuration.

**Components:**
- `infrastructure/storage/` — local StorageClass, PersistentVolume for `/srv/media/` on horseradish
- `infrastructure/nfs/` — NFS server configuration exposing horseradish's media directory to the cluster
- `infrastructure/cert-manager/` — cert-manager installation, ClusterIssuer for Let's Encrypt
- `infrastructure/traefik/` — Traefik configuration overrides (ports, TLS defaults)

**Dependencies:** Phase 2 (Flux CD managing infrastructure)

**Done when:** PV is bound, NFS mount is accessible from wasabi, cert-manager can issue a test certificate, Traefik is serving on configured ports with TLS
<!-- END_PHASE_3 -->

<!-- START_PHASE_4 -->
### Phase 4: Jellyfin Deployment
**Goal:** Deploy Jellyfin on horseradish, serving media from local storage, accessible externally via Traefik with TLS.

**Components:**
- `apps/jellyfin/` — Deployment (node affinity to horseradish), Service, PVC for config, PVC referencing media PV, Ingress with TLS

**Dependencies:** Phase 3 (storage, cert-manager, Traefik)

**Done when:** Jellyfin web UI is accessible on LAN, Jellyfin is accessible externally via DDNS domain with valid TLS certificate, media library directory is visible to Jellyfin
<!-- END_PHASE_4 -->

<!-- START_PHASE_5 -->
### Phase 5: Media Pipeline Deployment
**Goal:** Deploy MakeMKV (ripping) on horseradish and HandBrake (encoding) on wasabi, connected via NFS.

**Components:**
- `apps/media-pipeline/` — MakeMKV Deployment (horseradish, `/dev/sr0` passthrough, local media PV), HandBrake Deployment (wasabi, NFS mount to horseradish media), Services for web UIs

**Dependencies:** Phase 3 (NFS, storage), Phase 4 (media directory structure established)

**Done when:** MakeMKV web UI accessible on LAN, can detect optical drive, HandBrake web UI accessible on LAN, can read files from ripping directory via NFS, encoded output appears in library directory on horseradish
<!-- END_PHASE_5 -->

<!-- START_PHASE_6 -->
### Phase 6: Home Assistant Deployment
**Goal:** Deploy Home Assistant on wasabi with host networking for mDNS device discovery.

**Components:**
- `apps/homeassistant/` — Deployment (`hostNetwork: true`, on wasabi), PVC for config/database, Service, Ingress with TLS (optional external access)

**Dependencies:** Phase 3 (cert-manager, Traefik)

**Done when:** Home Assistant web UI accessible on LAN via wasabi's IP:8123, initial setup wizard loads, mDNS device discovery functional (can find WiFi devices on LAN)
<!-- END_PHASE_6 -->

<!-- START_PHASE_7 -->
### Phase 7: beanJAMinBOT Deployment
**Goal:** Containerize beanJAMinBOT and deploy it to wasabi.

**Components:**
- Production Dockerfile for beanJAMinBOT (in the beanJAMinBOT repo, referenced here)
- `apps/beanjaminbot/` — Deployment (node affinity to wasabi), PVCs for `config/` and `data/`, Secret for `botjamin_auth.yaml`, Service (NodePort or Ingress for OAuth callback if needed)

**Dependencies:** Phase 3 (infrastructure)

**Done when:** beanJAMinBOT pod is running on wasabi, connects to Twitch IRC, responds to chat commands, config and data persist across pod restarts
<!-- END_PHASE_7 -->

## Additional Considerations

**Secret management:** Secrets are created manually via `kubectl` initially. This is pragmatic for a home lab. SOPS integration with Flux is a natural upgrade path for storing encrypted secrets in git — add when manual secret management becomes tedious.

**Backup:** Not in scope, but the design supports it. All persistent data lives in known paths on known nodes (`/srv/media/` on horseradish, local-path volumes under k3s default paths). Standard backup tools (rsync, borg) work against these directories.

**Future USB device passthrough (Zigbee/Z-Wave):** Home Assistant is on wasabi with host networking. If a Zigbee USB coordinator is added to wasabi, it can be passed through to the pod via device configuration similar to the optical drive passthrough on horseradish. If the coordinator is on horseradish instead, Home Assistant's node affinity would need to change.

**beanJAMinBOT audio dependency:** Currently pinned to wasabi for TTS/sound playback. The node affinity label (`node-role.beanlab/streaming`) can be removed once the bot's audio dependency is refactored. No architectural changes needed — just remove the affinity rule.
