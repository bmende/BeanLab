# BeanLab Infrastructure Implementation Plan

**Goal:** Build a 2-node k3s cluster managed via GitOps with deployments for Jellyfin, media ripping pipeline, Home Assistant, and beanJAMinBOT.

**Architecture:** Two physical nodes (server + agent) joined into a k3s cluster. Flux CD watches the main branch and reconciles cluster state from YAML manifests. Layered Kustomization ordering ensures infrastructure is ready before apps deploy.

**Tech Stack:** k3s, Flux CD, Traefik, cert-manager, NFS, shell scripts (bash)

**Scope:** 7 phases from original design (phases 1-7)

**Codebase verified:** 2026-03-10 — beanJAMinBOT repo investigated at /home/bmende/Projects/beanJAMinBOT

---

## Acceptance Criteria Coverage

This phase implements and verifies:

### beanlab-infra.AC6: beanJAMinBOT is deployed and running
- **beanlab-infra.AC6.1 Success:** beanJAMinBOT pod runs on wasabi
- **beanlab-infra.AC6.2 Success:** Bot connects to Twitch IRC and responds to chat commands
- **beanlab-infra.AC6.3 Success:** Bot config (`config/`) and data (`data/`) persist across pod restarts
- **beanlab-infra.AC6.4 Success:** Credentials are stored as K8s Secret, not in plain text in manifests

---

<!-- START_TASK_1 -->
### Task 1: Create production Dockerfile for beanJAMinBOT

**Verifies:** beanlab-infra.AC6.1

**Files:**
- Create: `apps/beanjaminbot/Dockerfile`

Note: This Dockerfile lives in the BeanLab repo alongside the k8s manifests. The bot source code is pulled from its own repo/image registry. For initial deployment, build the image locally on the cluster node or push to a registry.

**Step 1: Create the Dockerfile**

`apps/beanjaminbot/Dockerfile`:
```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install audio dependencies for pyttsx3/playsound (best-effort in container)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        espeak-ng \
        libespeak-ng1 \
        alsa-utils \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Config and data are mounted as volumes, not baked into the image
VOLUME ["/app/config", "/app/data"]

CMD ["python", "main.py"]
```

**Step 2: Verify operationally**

```bash
cat apps/beanjaminbot/Dockerfile
```

Expected: Python 3.12-slim base, installs audio deps, pip installs requirements, volumes for config and data.

**Step 3: Commit**

```bash
git add apps/beanjaminbot/Dockerfile
git commit -m "feat: add production Dockerfile for beanJAMinBOT"
```
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create beanJAMinBOT Deployment with node affinity

**Verifies:** beanlab-infra.AC6.1, beanlab-infra.AC6.2, beanlab-infra.AC6.3, beanlab-infra.AC6.4

**Files:**
- Create: `apps/beanjaminbot/deployment.yaml`

**Step 1: Create the Deployment**

`apps/beanjaminbot/deployment.yaml`:
```yaml
# NOTE: Replace <BOT_IMAGE> with the built image reference
# (e.g., registry/beanjaminbot:latest or a local image name)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: beanjaminbot
  namespace: default
  labels:
    app: beanjaminbot
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: beanjaminbot
  template:
    metadata:
      labels:
        app: beanjaminbot
    spec:
      nodeSelector:
        node-role.beanlab/streaming: "true"
      containers:
        - name: beanjaminbot
          image: <BOT_IMAGE>
          volumeMounts:
            - name: config
              mountPath: /app/config
            - name: data
              mountPath: /app/data
            - name: auth
              mountPath: /app/config/botjamin_auth.yaml
              subPath: botjamin_auth.yaml
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              memory: 512Mi
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: beanjaminbot-config
        - name: data
          persistentVolumeClaim:
            claimName: beanjaminbot-data
        - name: auth
          secret:
            secretName: beanjaminbot-auth
```

**Step 2: Verify operationally**

```bash
cat apps/beanjaminbot/deployment.yaml
```

Expected: Valid YAML, pinned to `node-role.beanlab/streaming=true`, auth file mounted from Secret as single file via `subPath`, config and data on separate PVCs.

**Step 3: Commit**

```bash
git add apps/beanjaminbot/deployment.yaml
git commit -m "feat: add beanJAMinBOT deployment with Secret-mounted credentials"
```
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Create PVCs for config and data

**Verifies:** beanlab-infra.AC6.3

**Files:**
- Create: `apps/beanjaminbot/pvc-config.yaml`
- Create: `apps/beanjaminbot/pvc-data.yaml`

**Step 1: Create config PVC**

`apps/beanjaminbot/pvc-config.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: beanjaminbot-config
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
```

**Step 2: Create data PVC**

`apps/beanjaminbot/pvc-data.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: beanjaminbot-data
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 5Gi
```

**Step 3: Verify operationally**

```bash
cat apps/beanjaminbot/pvc-config.yaml
cat apps/beanjaminbot/pvc-data.yaml
```

Expected: Both use `local-path` provisioner. Data PVC is larger (5Gi) to accommodate media files (gifs, sfx, videos).

**Step 4: Commit**

```bash
git add apps/beanjaminbot/pvc-config.yaml apps/beanjaminbot/pvc-data.yaml
git commit -m "feat: add beanJAMinBOT PVCs for config and data persistence"
```
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Document Secret creation for credentials

**Verifies:** beanlab-infra.AC6.4

**Files:**
- Create: `apps/beanjaminbot/README-secrets.md`

**Step 1: Create documentation for manual Secret creation**

`apps/beanjaminbot/README-secrets.md`:
```markdown
# beanJAMinBOT Secrets

The bot credentials are stored as a Kubernetes Secret, not in git.

## Create the Secret

Copy your `botjamin_auth.yaml` from the beanJAMinBOT repo's `config/` directory:

    kubectl create secret generic beanjaminbot-auth \
      --from-file=botjamin_auth.yaml=/path/to/your/botjamin_auth.yaml

## Verify

    kubectl get secret beanjaminbot-auth
    kubectl describe secret beanjaminbot-auth

## Update

To update credentials, delete and recreate:

    kubectl delete secret beanjaminbot-auth
    kubectl create secret generic beanjaminbot-auth \
      --from-file=botjamin_auth.yaml=/path/to/your/botjamin_auth.yaml

Then restart the pod:

    kubectl rollout restart deployment beanjaminbot
```

**Step 2: Verify operationally**

```bash
cat apps/beanjaminbot/README-secrets.md
```

Expected: Clear instructions for Secret creation from the auth YAML file.

**Step 3: Commit**

```bash
git add apps/beanjaminbot/README-secrets.md
git commit -m "docs: add beanJAMinBOT secret creation instructions"
```
<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Create kustomization.yaml and wire into apps/

**Verifies:** None (wiring)

**Files:**
- Create: `apps/beanjaminbot/kustomization.yaml`
- Modify: `apps/kustomization.yaml`

**Step 1: Create apps/beanjaminbot/kustomization.yaml**

Note: The Dockerfile and README-secrets.md are not Kubernetes resources — they are not listed in kustomization.yaml.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - pvc-config.yaml
  - pvc-data.yaml
```

**Step 2: Update apps/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - jellyfin/
  - media-pipeline/
  - homeassistant/
  - beanjaminbot/
```

**Step 3: Verify operationally**

```bash
cat apps/beanjaminbot/kustomization.yaml
cat apps/kustomization.yaml
```

Expected: beanjaminbot kustomization lists 3 resources, root apps kustomization includes all four app directories.

**Step 4: Commit**

```bash
git add apps/beanjaminbot/kustomization.yaml apps/kustomization.yaml
git commit -m "chore: wire beanJAMinBOT kustomization into apps layer"
```
<!-- END_TASK_5 -->
