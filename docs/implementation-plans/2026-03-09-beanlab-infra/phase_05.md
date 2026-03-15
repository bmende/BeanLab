# BeanLab Infrastructure Implementation Plan

**Goal:** Build a 2-node k3s cluster managed via GitOps with deployments for Jellyfin, media ripping pipeline, Home Assistant, and beanJAMinBOT.

**Architecture:** Two physical nodes (server + agent) joined into a k3s cluster. Flux CD watches the main branch and reconciles cluster state from YAML manifests. Layered Kustomization ordering ensures infrastructure is ready before apps deploy.

**Tech Stack:** k3s, Flux CD, Traefik, cert-manager, NFS, shell scripts (bash)

**Scope:** 7 phases from original design (phases 1-7)

**Codebase verified:** 2026-03-10 — greenfield repo confirmed

---

## Acceptance Criteria Coverage

This phase implements and verifies:

### beanlab-infra.AC4: Media ripping pipeline runs on horseradish
- **beanlab-infra.AC4.1 Success:** MakeMKV pod runs on horseradish with access to optical drive
- **beanlab-infra.AC4.2 Success:** MakeMKV web UI is accessible on LAN
- **beanlab-infra.AC4.3 Success:** Ripped files appear in `/srv/media/ripping/` on horseradish
- **beanlab-infra.AC4.4 Success:** HandBrake pod runs on wasabi with NFS access to horseradish's media directory
- **beanlab-infra.AC4.5 Success:** Encoded files written by HandBrake appear in `/srv/media/library/` on horseradish
- **beanlab-infra.AC4.6 Success:** HandBrake web UI is accessible on LAN

---

<!-- START_SUBCOMPONENT_A (tasks 1-2) -->
<!-- START_TASK_1 -->
### Task 1: Create MakeMKV Deployment on agent node with optical drive passthrough

**Verifies:** beanlab-infra.AC4.1, beanlab-infra.AC4.3

**Files:**
- Create: `apps/media-pipeline/makemkv-deployment.yaml`

**Step 1: Create the Deployment**

`apps/media-pipeline/makemkv-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: makemkv
  namespace: default
  labels:
    app: makemkv
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: makemkv
  template:
    metadata:
      labels:
        app: makemkv
    spec:
      nodeSelector:
        node-role.beanlab/media: "true"
      containers:
        - name: makemkv
          image: jlesage/makemkv:latest
          ports:
            - name: web-ui
              containerPort: 5800
              protocol: TCP
          env:
            - name: USER_ID
              value: "1000"
            - name: GROUP_ID
              value: "1000"
          securityContext:
            capabilities:
              add:
                - SYS_ADMIN   # Required by MakeMKV for ioctl operations on the drive
                - SYS_RAWIO   # Required for raw SCSI commands to the optical drive
          volumeMounts:
            - name: config
              mountPath: /config
            - name: output
              mountPath: /output
            - name: optical-drive
              mountPath: /dev/sr0
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              memory: 4Gi
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: makemkv-config
        - name: output
          hostPath:
            path: /srv/media/ripping
            type: DirectoryOrCreate
        - name: optical-drive
          hostPath:
            path: /dev/sr0
            type: BlockDevice
```

**Step 2: Verify operationally**

```bash
cat apps/media-pipeline/makemkv-deployment.yaml
```

Expected: Valid YAML, pinned to `node-role.beanlab/media=true`, optical drive as BlockDevice hostPath, ripping output via hostPath to `/srv/media/ripping`.

**Step 3: Commit**

```bash
git add apps/media-pipeline/makemkv-deployment.yaml
git commit -m "feat: add MakeMKV deployment with optical drive passthrough"
```
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create MakeMKV PVC and Service

**Verifies:** beanlab-infra.AC4.2

**Files:**
- Create: `apps/media-pipeline/makemkv-pvc.yaml`
- Create: `apps/media-pipeline/makemkv-service.yaml`

**Step 1: Create config PVC**

`apps/media-pipeline/makemkv-pvc.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: makemkv-config
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
```

**Step 2: Create Service (LAN-only, no Ingress)**

`apps/media-pipeline/makemkv-service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: makemkv
  namespace: default
spec:
  selector:
    app: makemkv
  ports:
    - name: web-ui
      port: 5800
      targetPort: web-ui
      protocol: TCP
  type: NodePort
```

**Step 3: Verify operationally**

```bash
cat apps/media-pipeline/makemkv-pvc.yaml
cat apps/media-pipeline/makemkv-service.yaml
```

Expected: PVC uses `local-path`, Service uses `NodePort` for LAN access.

**Step 4: Commit**

```bash
git add apps/media-pipeline/makemkv-pvc.yaml apps/media-pipeline/makemkv-service.yaml
git commit -m "feat: add MakeMKV config PVC and NodePort service"
```
<!-- END_TASK_2 -->
<!-- END_SUBCOMPONENT_A -->

<!-- START_SUBCOMPONENT_B (tasks 3-4) -->
<!-- START_TASK_3 -->
### Task 3: Create HandBrake Deployment on server node with NFS mount

**Verifies:** beanlab-infra.AC4.4, beanlab-infra.AC4.5

**Files:**
- Create: `apps/media-pipeline/handbrake-deployment.yaml`

**Step 1: Create the Deployment**

`apps/media-pipeline/handbrake-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: handbrake
  namespace: default
  labels:
    app: handbrake
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: handbrake
  template:
    metadata:
      labels:
        app: handbrake
    spec:
      nodeSelector:
        node-role.beanlab/streaming: "true"
      containers:
        - name: handbrake
          image: jlesage/handbrake:latest
          ports:
            - name: web-ui
              containerPort: 5800
              protocol: TCP
          env:
            - name: USER_ID
              value: "1000"
            - name: GROUP_ID
              value: "1000"
          volumeMounts:
            - name: config
              mountPath: /config
            - name: media
              mountPath: /storage
              subPath: ripping
            - name: media
              mountPath: /output
              subPath: library
          resources:
            requests:
              cpu: 1000m
              memory: 1Gi
            limits:
              memory: 4Gi
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: handbrake-config
        - name: media
          persistentVolumeClaim:
            claimName: handbrake-media
```

**Step 2: Verify operationally**

```bash
cat apps/media-pipeline/handbrake-deployment.yaml
```

Expected: Valid YAML, pinned to `node-role.beanlab/streaming=true`, NFS PVC with subPath `ripping` for input and `library` for output.

**Step 3: Commit**

```bash
git add apps/media-pipeline/handbrake-deployment.yaml
git commit -m "feat: add HandBrake deployment with NFS media mount"
```
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Create HandBrake PVCs and Service

**Verifies:** beanlab-infra.AC4.6

**Files:**
- Create: `apps/media-pipeline/handbrake-pvc-config.yaml`
- Create: `apps/media-pipeline/handbrake-pvc-media.yaml`
- Create: `apps/media-pipeline/handbrake-service.yaml`

**Step 1: Create config PVC**

`apps/media-pipeline/handbrake-pvc-config.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: handbrake-config
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
```

**Step 2: Create NFS media PVC (binds to the NFS PV from Phase 3)**

`apps/media-pipeline/handbrake-pvc-media.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: handbrake-media
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-media
  volumeName: media-nfs
  resources:
    requests:
      storage: 500Gi
```

**Step 3: Create Service (LAN-only)**

`apps/media-pipeline/handbrake-service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: handbrake
  namespace: default
spec:
  selector:
    app: handbrake
  ports:
    - name: web-ui
      port: 5800
      targetPort: web-ui
      protocol: TCP
  type: NodePort
```

**Step 4: Verify operationally**

```bash
cat apps/media-pipeline/handbrake-pvc-config.yaml
cat apps/media-pipeline/handbrake-pvc-media.yaml
cat apps/media-pipeline/handbrake-service.yaml
```

Expected: Config PVC uses `local-path`, media PVC binds to `media-nfs` NFS PV, Service uses `NodePort`.

**Step 5: Commit**

```bash
git add apps/media-pipeline/handbrake-pvc-config.yaml apps/media-pipeline/handbrake-pvc-media.yaml apps/media-pipeline/handbrake-service.yaml
git commit -m "feat: add HandBrake PVCs and NodePort service"
```
<!-- END_TASK_4 -->
<!-- END_SUBCOMPONENT_B -->

<!-- START_TASK_5 -->
### Task 5: Create kustomization.yaml and wire into apps/

**Verifies:** None (wiring)

**Files:**
- Create: `apps/media-pipeline/kustomization.yaml`
- Modify: `apps/kustomization.yaml`

**Step 1: Create apps/media-pipeline/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - makemkv-deployment.yaml
  - makemkv-pvc.yaml
  - makemkv-service.yaml
  - handbrake-deployment.yaml
  - handbrake-pvc-config.yaml
  - handbrake-pvc-media.yaml
  - handbrake-service.yaml
```

**Step 2: Update apps/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - jellyfin/
  - media-pipeline/
```

**Step 3: Verify operationally**

```bash
cat apps/media-pipeline/kustomization.yaml
cat apps/kustomization.yaml
```

Expected: Media-pipeline kustomization lists all 7 resources, root apps kustomization includes both jellyfin/ and media-pipeline/.

**Step 4: Commit**

```bash
git add apps/media-pipeline/kustomization.yaml apps/kustomization.yaml
git commit -m "chore: wire media-pipeline kustomization into apps layer"
```
<!-- END_TASK_5 -->
