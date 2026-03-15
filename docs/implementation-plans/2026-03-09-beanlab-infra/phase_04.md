# BeanLab Infrastructure Implementation Plan

**Goal:** Build a 2-node k3s cluster managed via GitOps with deployments for Jellyfin, media ripping pipeline, Home Assistant, and beanJAMinBOT.

**Architecture:** Two physical nodes (server + agent) joined into a k3s cluster. Flux CD watches the main branch and reconciles cluster state from YAML manifests. Layered Kustomization ordering ensures infrastructure is ready before apps deploy.

**Tech Stack:** k3s, Flux CD, Traefik, cert-manager, NFS, shell scripts (bash)

**Scope:** 7 phases from original design (phases 1-7)

**Codebase verified:** 2026-03-10 — greenfield repo confirmed

---

## Acceptance Criteria Coverage

This phase implements and verifies:

### beanlab-infra.AC3: Jellyfin runs on horseradish serving local media, accessible externally
- **beanlab-infra.AC3.1 Success:** Jellyfin pod runs on horseradish (verified by `kubectl get pod -o wide`)
- **beanlab-infra.AC3.2 Success:** Jellyfin can browse and play media files from `/srv/media/library/`
- **beanlab-infra.AC3.3 Success:** Adding a file to `/srv/media/library/` on the host makes it visible in Jellyfin after library scan
- **beanlab-infra.AC3.4 Success:** Jellyfin is accessible externally via DDNS domain with valid TLS certificate
- **beanlab-infra.AC3.5 Success:** Jellyfin config and database persist across pod restarts

---

<!-- START_TASK_1 -->
### Task 1: Create apps/jellyfin/ — Deployment with node affinity and volumes

**Verifies:** beanlab-infra.AC3.1, beanlab-infra.AC3.2, beanlab-infra.AC3.5

**Files:**
- Create: `apps/jellyfin/deployment.yaml`

**Step 1: Create the Deployment**

`apps/jellyfin/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jellyfin
  namespace: default
  labels:
    app: jellyfin
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: jellyfin
  template:
    metadata:
      labels:
        app: jellyfin
    spec:
      nodeSelector:
        node-role.beanlab/media: "true"
      containers:
        - name: jellyfin
          image: jellyfin/jellyfin:latest
          ports:
            - name: http
              containerPort: 8096
              protocol: TCP
          volumeMounts:
            - name: config
              mountPath: /config
            - name: cache
              mountPath: /cache
            - name: media
              mountPath: /media
              subPath: library
              readOnly: true
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              memory: 2Gi
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: jellyfin-config
        - name: cache
          emptyDir: {}
        - name: media
          persistentVolumeClaim:
            claimName: jellyfin-media
```

**Step 2: Verify operationally**

```bash
cat apps/jellyfin/deployment.yaml
```

Expected: Valid YAML, `nodeSelector` targets `node-role.beanlab/media=true`, `Recreate` strategy, media mounted read-only at `/media` with `subPath: library`.

**Step 3: Commit**

```bash
git add apps/jellyfin/deployment.yaml
git commit -m "feat: add Jellyfin deployment with node affinity and volume mounts"
```
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create PVCs for Jellyfin config and media

**Verifies:** beanlab-infra.AC3.2, beanlab-infra.AC3.3, beanlab-infra.AC3.5

**Files:**
- Create: `apps/jellyfin/pvc-config.yaml`
- Create: `apps/jellyfin/pvc-media.yaml`

**Step 1: Create PVC for Jellyfin config (uses k3s local-path provisioner)**

`apps/jellyfin/pvc-config.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jellyfin-config
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 5Gi
```

**Step 2: Create PVC for media (binds to the local media PV from Phase 3)**

`apps/jellyfin/pvc-media.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jellyfin-media
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-media
  volumeName: media-local
  resources:
    requests:
      storage: 500Gi
```

**Step 3: Verify operationally**

```bash
cat apps/jellyfin/pvc-config.yaml
cat apps/jellyfin/pvc-media.yaml
```

Expected: Config PVC uses `local-path` (k3s built-in), media PVC explicitly binds to `media-local` PV via `volumeName`.

**Step 4: Commit**

```bash
git add apps/jellyfin/pvc-config.yaml apps/jellyfin/pvc-media.yaml
git commit -m "feat: add Jellyfin PVCs for config and media storage"
```
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Create Service and Ingress for Jellyfin

**Verifies:** beanlab-infra.AC3.4

**Files:**
- Create: `apps/jellyfin/service.yaml`
- Create: `apps/jellyfin/ingress.yaml`

**Step 1: Create Service**

`apps/jellyfin/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: jellyfin
  namespace: default
spec:
  selector:
    app: jellyfin
  ports:
    - name: http
      port: 8096
      targetPort: http
      protocol: TCP
  type: ClusterIP
```

**Step 2: Create Ingress with TLS via cert-manager**

`apps/jellyfin/ingress.yaml`:
```yaml
# NOTE: Replace <YOUR_DOMAIN> with your DDNS domain (e.g., jellyfin.example.com)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jellyfin
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - <YOUR_DOMAIN>
      secretName: jellyfin-tls
  rules:
    - host: <YOUR_DOMAIN>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: jellyfin
                port:
                  number: 8096
```

**Step 3: Verify operationally**

```bash
cat apps/jellyfin/service.yaml
cat apps/jellyfin/ingress.yaml
```

Expected: Service targets port 8096, Ingress uses `letsencrypt-prod` ClusterIssuer and `traefik` ingress class.

**Step 4: Commit**

```bash
git add apps/jellyfin/service.yaml apps/jellyfin/ingress.yaml
git commit -m "feat: add Jellyfin Service and Ingress with TLS"
```
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Create kustomization.yaml and wire into apps/

**Verifies:** None (wiring)

**Files:**
- Create: `apps/jellyfin/kustomization.yaml`
- Modify: `apps/kustomization.yaml`

**Step 1: Create apps/jellyfin/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - pvc-config.yaml
  - pvc-media.yaml
  - service.yaml
  - ingress.yaml
```

**Step 2: Update apps/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - jellyfin/
```

**Step 3: Verify operationally**

```bash
cat apps/jellyfin/kustomization.yaml
cat apps/kustomization.yaml
```

Expected: Jellyfin kustomization lists all 5 resources, root apps kustomization includes jellyfin/.

**Step 4: Commit**

```bash
git add apps/jellyfin/kustomization.yaml apps/kustomization.yaml
git commit -m "chore: wire Jellyfin kustomization into apps layer"
```
<!-- END_TASK_4 -->
