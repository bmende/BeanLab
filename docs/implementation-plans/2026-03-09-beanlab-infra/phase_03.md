# BeanLab Infrastructure Implementation Plan

**Goal:** Build a 2-node k3s cluster managed via GitOps with deployments for Jellyfin, media ripping pipeline, Home Assistant, and beanJAMinBOT.

**Architecture:** Two physical nodes (server + agent) joined into a k3s cluster. Flux CD watches the main branch and reconciles cluster state from YAML manifests. Layered Kustomization ordering ensures infrastructure is ready before apps deploy.

**Tech Stack:** k3s, Flux CD, Traefik, cert-manager, NFS, shell scripts (bash)

**Scope:** 7 phases from original design (phases 1-7)

**Codebase verified:** 2026-03-10 — greenfield repo confirmed

---

## Acceptance Criteria Coverage

This phase provides infrastructure enabling later ACs. No ACs are directly verified by this phase.

**Verifies:** None (infrastructure scaffolding enabling AC3.4, AC4.4, AC4.5)

---

<!-- START_SUBCOMPONENT_A (tasks 1-2) -->
<!-- START_TASK_1 -->
### Task 1: Create infrastructure/storage/ — local StorageClass and media PV

**Verifies:** None (infrastructure enabling AC3, AC4)

**Files:**
- Create: `infrastructure/storage/storageclass-local.yaml`
- Create: `infrastructure/storage/pv-media-local.yaml`
- Create: `infrastructure/storage/kustomization.yaml`

**Step 1: Create StorageClass for local volumes**

`infrastructure/storage/storageclass-local.yaml`:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-media
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

**Step 2: Create local PV for /srv/media/ on the agent node**

`infrastructure/storage/pv-media-local.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: media-local
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-media
  local:
    path: /srv/media
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-role.beanlab/media
              operator: In
              values:
                - "true"
```

**Step 3: Create kustomization.yaml**

`infrastructure/storage/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - storageclass-local.yaml
  - pv-media-local.yaml
```

**Step 4: Verify operationally**

```bash
cat infrastructure/storage/storageclass-local.yaml
cat infrastructure/storage/pv-media-local.yaml
cat infrastructure/storage/kustomization.yaml
```

Expected: Valid YAML, PV uses nodeAffinity matching `node-role.beanlab/media=true` label.

**Step 5: Commit**

```bash
git add infrastructure/storage/
git commit -m "feat: add local StorageClass and media PV for agent node"
```
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Add NFS PV for cross-node media access

**Verifies:** None (infrastructure enabling AC4.4, AC4.5)

**Files:**
- Create: `infrastructure/storage/pv-media-nfs.yaml`
- Modify: `infrastructure/storage/kustomization.yaml`

**Note:** The server node's `nfs-common` package is installed by `setup-server.sh` (Phase 1, Task 2).

**Step 1: Create NFS PV**

**IMPORTANT:** Replace `<AGENT_NODE_IP>` in the YAML below with the agent node's actual LAN IP address (e.g., `192.168.1.100`). This is the IP of the NFS server. You can find it by running `hostname -I` on the agent node. Do **not** commit the placeholder value.

`infrastructure/storage/pv-media-nfs.yaml`:
```yaml
# Replace <AGENT_NODE_IP> with the agent node's LAN IP address
apiVersion: v1
kind: PersistentVolume
metadata:
  name: media-nfs
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-media
  nfs:
    server: <AGENT_NODE_IP>
    path: /srv/media
    readOnly: false
```

**Step 2: Update kustomization.yaml**

Add `pv-media-nfs.yaml` to the resources list in `infrastructure/storage/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - storageclass-local.yaml
  - pv-media-local.yaml
  - pv-media-nfs.yaml
```

**Step 3: Verify operationally**

```bash
cat infrastructure/storage/pv-media-nfs.yaml
cat infrastructure/storage/kustomization.yaml
```

Expected: NFS PV has `ReadWriteMany` access mode, `nfs:` spec with a real IP address (not `<AGENT_NODE_IP>`).

```bash
# Verify no placeholders remain:
grep -c '<AGENT_NODE_IP>' infrastructure/storage/pv-media-nfs.yaml
```

Expected: Returns `0` (no remaining placeholders).

**Step 4: Commit**

```bash
git add infrastructure/storage/
git commit -m "feat: add NFS PV for cross-node media access"
```
<!-- END_TASK_2 -->
<!-- END_SUBCOMPONENT_A -->

<!-- START_SUBCOMPONENT_B (tasks 3-4) -->
<!-- START_TASK_3 -->
### Task 3: Create infrastructure/cert-manager/ — HelmRelease and namespace

**Verifies:** None (infrastructure enabling AC3.4)

**Files:**
- Create: `infrastructure/cert-manager/namespace.yaml`
- Create: `infrastructure/cert-manager/helmrepo.yaml`
- Create: `infrastructure/cert-manager/helmrelease.yaml`
- Create: `infrastructure/cert-manager/kustomization.yaml`

**Step 1: Create namespace**

`infrastructure/cert-manager/namespace.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
```

**Step 2: Create HelmRepository for Jetstack charts**

`infrastructure/cert-manager/helmrepo.yaml`:
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: jetstack
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.jetstack.io
```

**Step 3: Create HelmRelease for cert-manager**

`infrastructure/cert-manager/helmrelease.yaml`:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 30m
  chart:
    spec:
      chart: cert-manager
      version: "1.14.x"
      sourceRef:
        kind: HelmRepository
        name: jetstack
        namespace: flux-system
  install:
    crds: CreateReplace
  upgrade:
    crds: CreateReplace
  values:
    replicaCount: 1
```

**Step 4: Create kustomization.yaml**

`infrastructure/cert-manager/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrepo.yaml
  - helmrelease.yaml
```

**Step 5: Verify operationally**

```bash
cat infrastructure/cert-manager/namespace.yaml
cat infrastructure/cert-manager/helmrepo.yaml
cat infrastructure/cert-manager/helmrelease.yaml
cat infrastructure/cert-manager/kustomization.yaml
```

Expected: Valid YAML, HelmRelease references Jetstack HelmRepository, CRDs set to CreateReplace.

**Step 6: Commit**

```bash
git add infrastructure/cert-manager/
git commit -m "feat: add cert-manager Flux HelmRelease"
```
<!-- END_TASK_3 -->

<!-- END_TASK_3 is the end of cert-manager subcomponent B; ClusterIssuers are in Task 4 below -->
<!-- END_SUBCOMPONENT_B -->

<!-- START_TASK_4 -->
### Task 4: Create infrastructure/cert-manager-issuers/ — ClusterIssuers (separate from cert-manager)

**Verifies:** None (infrastructure enabling AC3.4)

**Important:** The ClusterIssuer CRD (`cert-manager.io/v1`) does not exist until cert-manager finishes installing via HelmRelease. Placing ClusterIssuers in the same Kustomization as the HelmRelease causes first-time reconciliation failures. They must be in a **separate directory** with its own **Flux Kustomization** that depends on the cert-manager HelmRelease being healthy.

**Files:**
- Create: `infrastructure/cert-manager-issuers/clusterissuer.yaml`
- Create: `infrastructure/cert-manager-issuers/kustomization.yaml`
- Create: `clusters/beanlab/cert-manager-issuers.yaml` (Flux Kustomization with dependsOn)

**Step 1: Create ClusterIssuer with staging and production issuers**

`infrastructure/cert-manager-issuers/clusterissuer.yaml`:

**IMPORTANT:** Replace `<YOUR_EMAIL>` with a real email address for Let's Encrypt registration notifications before committing. Let's Encrypt will use this to notify you about expiring certificates. Example: `admin@yourdomain.com`.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: <YOUR_EMAIL>
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - http01:
          ingress:
            class: traefik
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <YOUR_EMAIL>
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: traefik
```

**Step 2: Create kustomization.yaml for the issuers directory**

`infrastructure/cert-manager-issuers/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - clusterissuer.yaml
```

**Step 3: Create Flux Kustomization that depends on cert-manager being ready**

`clusters/beanlab/cert-manager-issuers.yaml`:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager-issuers
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/cert-manager-issuers
  prune: true
  wait: true
  dependsOn:
    - name: infrastructure
```

This ensures Flux fully reconciles the infrastructure Kustomization (including the cert-manager HelmRelease and CRDs) before attempting to apply the ClusterIssuers.

**Step 4: Verify operationally**

```bash
cat infrastructure/cert-manager-issuers/clusterissuer.yaml
cat infrastructure/cert-manager-issuers/kustomization.yaml
cat clusters/beanlab/cert-manager-issuers.yaml
# Verify email placeholder has been replaced:
grep -c '<YOUR_EMAIL>' infrastructure/cert-manager-issuers/clusterissuer.yaml
```

Expected: Valid YAML in all files. The grep command should return `0` (no remaining placeholders).

**Step 5: Commit**

```bash
git add infrastructure/cert-manager-issuers/ clusters/beanlab/cert-manager-issuers.yaml
git commit -m "feat: add Let's Encrypt ClusterIssuers with cert-manager dependency ordering"
```
<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Create infrastructure/traefik/ — HelmChartConfig

**Verifies:** None (infrastructure enabling AC3.4)

**Files:**
- Create: `infrastructure/traefik/helmchartconfig.yaml`
- Create: `infrastructure/traefik/kustomization.yaml`

**Step 1: Create HelmChartConfig to customize k3s-bundled Traefik**

`infrastructure/traefik/helmchartconfig.yaml`:
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    globalArguments:
      - "--global.checknewversion=false"
      - "--global.sendanonymoususage=false"
    ports:
      web:
        port: 8000
        expose:
          default: true
        exposedPort: 80
        protocol: TCP
      websecure:
        port: 8443
        expose:
          default: true
        exposedPort: 443
        protocol: TCP
        tls:
          enabled: true
```

**Step 2: Create kustomization.yaml**

`infrastructure/traefik/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmchartconfig.yaml
```

**Step 3: Verify operationally**

```bash
cat infrastructure/traefik/helmchartconfig.yaml
cat infrastructure/traefik/kustomization.yaml
```

Expected: Valid YAML, HelmChartConfig targets `traefik` in `kube-system`, enables TLS on websecure port.

**Step 4: Commit**

```bash
git add infrastructure/traefik/
git commit -m "feat: add Traefik HelmChartConfig with TLS defaults"
```
<!-- END_TASK_5 -->

<!-- START_TASK_6 -->
### Task 6: Update infrastructure/kustomization.yaml to include all subdirectories

**Verifies:** None (wiring)

**Files:**
- Modify: `infrastructure/kustomization.yaml`

**Step 1: Update the root infrastructure kustomization**

Replace the empty stub with references to all subdirectories:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - storage/
  - cert-manager/
  - traefik/
```

**Step 2: Verify operationally**

```bash
cat infrastructure/kustomization.yaml
```

Expected: Lists all three infrastructure subdirectories.

**Step 3: Commit**

```bash
git add infrastructure/kustomization.yaml
git commit -m "chore: wire infrastructure kustomization to storage, cert-manager, traefik"
```
<!-- END_TASK_6 -->
