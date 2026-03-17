# BeanLab Infrastructure Implementation Plan

**Goal:** Build a 2-node k3s cluster managed via GitOps with deployments for Jellyfin, media ripping pipeline, Home Assistant, and beanJAMinBOT.

**Architecture:** Two physical nodes (server + agent) joined into a k3s cluster. Flux CD watches the main branch and reconciles cluster state from YAML manifests. Layered Kustomization ordering ensures infrastructure is ready before apps deploy.

**Tech Stack:** k3s, Flux CD, Traefik, cert-manager, NFS, shell scripts (bash)

**Scope:** 7 phases from original design (phases 1-7)

**Codebase verified:** 2026-03-10 — greenfield repo confirmed

---

## Acceptance Criteria Coverage

This phase implements and verifies:

### beanlab-infra.AC5: Home Assistant is deployed and accessible
- **beanlab-infra.AC5.1 Success:** Home Assistant pod runs on wasabi with host networking
- **beanlab-infra.AC5.2 Success:** Home Assistant web UI accessible on LAN at wasabi's IP:8123
- **beanlab-infra.AC5.3 Success:** mDNS device discovery finds WiFi devices on the LAN
- **beanlab-infra.AC5.4 Success:** Home Assistant config persists across pod restarts

---

<!-- START_TASK_1 -->
### Task 1: Create Home Assistant Deployment with hostNetwork

**Verifies:** beanlab-infra.AC5.1, beanlab-infra.AC5.3, beanlab-infra.AC5.4

**Files:**
- Create: `apps/homeassistant/deployment.yaml`

**Step 1: Create the Deployment**

`apps/homeassistant/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: homeassistant
  namespace: default
  labels:
    app: homeassistant
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: homeassistant
  template:
    metadata:
      labels:
        app: homeassistant
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      nodeSelector:
        node-role.beanlab/streaming: "true"
      containers:
        - name: homeassistant
          image: ghcr.io/home-assistant/home-assistant:stable
          ports:
            - name: http
              containerPort: 8123
              hostPort: 8123
              protocol: TCP
          volumeMounts:
            - name: config
              mountPath: /config
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              memory: 1Gi
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: homeassistant-config
```

**Step 2: Verify operationally**

```bash
cat apps/homeassistant/deployment.yaml
```

Expected: Valid YAML, `hostNetwork: true`, `dnsPolicy: ClusterFirstWithHostNet`, pinned to server node.

**Step 3: Commit**

```bash
git add apps/homeassistant/deployment.yaml
git commit -m "feat: add Home Assistant deployment with hostNetwork for mDNS"
```
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create Home Assistant PVC and Service

**Verifies:** beanlab-infra.AC5.2, beanlab-infra.AC5.4

**Files:**
- Create: `apps/homeassistant/pvc.yaml`
- Create: `apps/homeassistant/service.yaml`

**Step 1: Create config PVC**

`apps/homeassistant/pvc.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: homeassistant-config
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 5Gi
```

**Step 2: Create Service**

With `hostNetwork: true`, Home Assistant is directly accessible at the node's IP:8123. A ClusterIP Service is still useful for internal cluster references.

`apps/homeassistant/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: homeassistant
  namespace: default
spec:
  selector:
    app: homeassistant
  ports:
    - name: http
      port: 8123
      targetPort: http
      protocol: TCP
  type: ClusterIP
```

**Step 3: Verify operationally**

```bash
cat apps/homeassistant/pvc.yaml
cat apps/homeassistant/service.yaml
```

Expected: PVC uses `local-path`, Service is ClusterIP (direct access via node IP:8123 due to hostNetwork).

**Step 4: Commit**

```bash
git add apps/homeassistant/pvc.yaml apps/homeassistant/service.yaml
git commit -m "feat: add Home Assistant PVC and Service"
```
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Create kustomization.yaml and wire into apps/

**Verifies:** None (wiring)

**Files:**
- Create: `apps/homeassistant/kustomization.yaml`
- Modify: `apps/kustomization.yaml`

**Step 1: Create apps/homeassistant/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - pvc.yaml
  - service.yaml
```

**Step 2: Update apps/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - jellyfin/
  - media-pipeline/
  - homeassistant/
```

**Step 3: Verify operationally**

```bash
cat apps/homeassistant/kustomization.yaml
cat apps/kustomization.yaml
```

Expected: Homeassistant kustomization lists all 3 resources, root apps kustomization includes all three app directories.

**Step 4: Commit**

```bash
git add apps/homeassistant/kustomization.yaml apps/kustomization.yaml
git commit -m "chore: wire Home Assistant kustomization into apps layer"
```
<!-- END_TASK_3 -->
