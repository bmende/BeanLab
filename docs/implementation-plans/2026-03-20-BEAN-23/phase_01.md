# LAN DNS Server Implementation Plan

**Goal:** Deploy a standalone CoreDNS instance in k3s to serve LAN DNS queries for local zones

**Architecture:** CoreDNS Deployment in `dns` namespace on wasabi, hostPort 53, hostPath mount for zone files, Corefile in ConfigMap. Forward plugin handles upstream resolution. Flux-managed via existing infrastructure Kustomization.

**Tech Stack:** CoreDNS 1.14.2, Kubernetes (k3s), Flux CD, Kustomize

**Scope:** 3 phases from original design (phases 1-3)

**Codebase verified:** 2026-03-20

---

## Acceptance Criteria Coverage

This phase implements and verifies:

### BEAN-23.AC1: LAN-facing DNS server runs in k3s serving local zones
- **BEAN-23.AC1.1 Success:** CoreDNS pod is Running on wasabi (`kubectl get pod -n dns -o wide` shows wasabi in NODE column)

### BEAN-23.AC3: DNS deployment is Flux-managed
- **BEAN-23.AC3.1 Success:** CoreDNS manifests exist in `infrastructure/coredns-lan/` and are listed in `infrastructure/kustomization.yaml`
- **BEAN-23.AC3.2 Success:** `flux get kustomizations` shows infrastructure reconciled with coredns-lan resources
- **BEAN-23.AC3.3 Success:** Deleting the CoreDNS pod causes Kubernetes to recreate it; zone files persist across pod restart (hostPath survives)

---

<!-- START_TASK_1 -->
### Task 1: Create dns namespace manifest

**Files:**
- Create: `infrastructure/coredns-lan/namespace.yaml`

**Step 1: Create the file**

Create `infrastructure/coredns-lan/namespace.yaml` with this exact content:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dns
```

This follows the existing pattern used by `infrastructure/headlamp/namespace.yaml` and `infrastructure/cert-manager/namespace.yaml`.

**Step 2: Verify**

Run: `kubectl apply --dry-run=client -f infrastructure/coredns-lan/namespace.yaml`
Expected: `namespace/dns created (dry run)`

**Step 3: Commit**

```bash
git add infrastructure/coredns-lan/namespace.yaml
git commit -m "feat(dns): add dns namespace manifest for CoreDNS LAN"
```
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create CoreDNS Corefile ConfigMap

**Files:**
- Create: `infrastructure/coredns-lan/configmap.yaml`

**Step 1: Create the file**

Create `infrastructure/coredns-lan/configmap.yaml` with this exact content:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-lan
  namespace: dns
data:
  Corefile: |
    . {
      auto {
        directory /data/zones db\.(.*) {1}
        reload 10s
      }
      forward . 8.8.8.8 8.8.4.4
      cache 30
      log
      errors
    }
```

**Key configuration details:**
- The `auto` plugin scans `/data/zones` for files matching `db.*` (e.g., `db.beanlab` serves the `beanlab` zone)
- `reload 10s` checks for new/changed zone files every 10 seconds
- `db\.(.*) {1}` extracts the zone name from the filename (e.g., `db.beanlab` → zone `beanlab`)
- `forward . 8.8.8.8 8.8.4.4` sends non-local queries to Google DNS
- `cache 30` caches upstream responses for 30 seconds
- `log` and `errors` enable query logging and error reporting

**Step 2: Verify**

Run: `kubectl apply --dry-run=client -f infrastructure/coredns-lan/configmap.yaml`
Expected: `configmap/coredns-lan created (dry run)`

**Step 3: Commit**

```bash
git add infrastructure/coredns-lan/configmap.yaml
git commit -m "feat(dns): add CoreDNS Corefile ConfigMap with auto and forward plugins"
```
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Create CoreDNS Deployment

**Files:**
- Create: `infrastructure/coredns-lan/deployment.yaml`

**Step 1: Create the file**

Create `infrastructure/coredns-lan/deployment.yaml` with this exact content:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns-lan
  namespace: dns
  labels:
    app: coredns-lan
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: coredns-lan
  template:
    metadata:
      labels:
        app: coredns-lan
    spec:
      nodeSelector:
        node-role.beanlab/streaming: "true"
      containers:
        - name: coredns
          image: coredns/coredns:1.14.2
          args:
            - -conf
            - /etc/coredns/Corefile
          ports:
            - name: dns-udp
              containerPort: 53
              hostPort: 53
              protocol: UDP
            - name: dns-tcp
              containerPort: 53
              hostPort: 53
              protocol: TCP
          volumeMounts:
            - name: config
              mountPath: /etc/coredns
              readOnly: true
            - name: zones
              mountPath: /data/zones
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              memory: 128Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              add:
                - NET_BIND_SERVICE
              drop:
                - ALL
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 65534
      volumes:
        - name: config
          configMap:
            name: coredns-lan
        - name: zones
          hostPath:
            path: /etc/coredns-lan/zones
            type: DirectoryOrCreate
```

**Key design decisions:**
- `strategy: Recreate` follows existing pattern (single-replica with volumes)
- `nodeSelector: node-role.beanlab/streaming: "true"` pins to wasabi (same label as Home Assistant and beanJAMinBOT)
- `hostPort: 53` on both UDP and TCP makes CoreDNS reachable at wasabi's LAN IP (`192.168.50.101`)
- `hostPath` with `type: DirectoryOrCreate` mounts `/etc/coredns-lan/zones/` from wasabi into the pod at `/data/zones` — zone files survive pod restarts
- `readOnly: true` on the zones mount prevents CoreDNS from modifying zone files
- Security context drops all capabilities except `NET_BIND_SERVICE`, runs as nobody (65534), read-only root filesystem
- Corefile is mounted from the ConfigMap at `/etc/coredns` and referenced via `-conf /etc/coredns/Corefile`

**Step 2: Verify**

Run: `kubectl apply --dry-run=client -f infrastructure/coredns-lan/deployment.yaml`
Expected: `deployment.apps/coredns-lan created (dry run)`

**Step 3: Commit**

```bash
git add infrastructure/coredns-lan/deployment.yaml
git commit -m "feat(dns): add CoreDNS LAN Deployment with hostPort 53 and hostPath zones"
```
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Create coredns-lan Kustomization and register in infrastructure

**Files:**
- Create: `infrastructure/coredns-lan/kustomization.yaml`
- Modify: `infrastructure/kustomization.yaml` (add `coredns-lan/` to resources list after `headlamp/`)

**Step 1: Create the component kustomization**

Create `infrastructure/coredns-lan/kustomization.yaml` with this exact content:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - configmap.yaml
  - deployment.yaml
```

This follows the pattern used by existing infrastructure components (headlamp, cert-manager, storage).

**Step 2: Register in the parent kustomization**

Modify `infrastructure/kustomization.yaml` to add `coredns-lan/` to the resources list. The file should become:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - storage/
  - cert-manager/
  - traefik/
  - headlamp/
  - coredns-lan/
```

**Step 3: Verify all manifests together**

Run: `kubectl apply --dry-run=client -k infrastructure/coredns-lan/`
Expected: Three resources created (dry run): `namespace/dns`, `configmap/coredns-lan`, `deployment.apps/coredns-lan`

Run: `kubectl apply --dry-run=client -k infrastructure/`
Expected: All existing infrastructure resources plus the three new coredns-lan resources created (dry run), no errors

**Step 4: Commit**

```bash
git add infrastructure/coredns-lan/kustomization.yaml infrastructure/kustomization.yaml
git commit -m "feat(dns): add coredns-lan Kustomization and register in infrastructure"
```
<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Push and verify Flux reconciliation

**Step 1: Push to remote**

```bash
git push origin HEAD
```

Note: Push your working branch and open a PR to merge to `master` (branch protections). Until merged to `master`, Flux will not reconcile these changes. If you want to test before merging, you can manually apply:

```bash
kubectl apply -k infrastructure/coredns-lan/
```

**Step 2: After merge to master — verify Flux reconciliation**

Run: `flux reconcile kustomization infrastructure --with-source`
Expected: Flux reconciles and applies the coredns-lan resources

Run: `flux get kustomizations`
Expected: `infrastructure` shows `Ready` status with recent revision

**Step 3: Verify CoreDNS pod is Running on wasabi**

Run: `kubectl get pod -n dns -o wide`
Expected: `coredns-lan-*` pod in `Running` state with `NODE` column showing wasabi

**Step 4: Verify pod restarts preserve zone directory**

Run: `kubectl delete pod -n dns -l app=coredns-lan`
Wait for pod to restart, then run: `kubectl get pod -n dns -o wide`
Expected: New pod is Running. The hostPath directory `/etc/coredns-lan/zones/` on wasabi still exists (verify via SSH: `ls -la /etc/coredns-lan/zones/`)

**Verifies:** BEAN-23.AC1.1, BEAN-23.AC3.1, BEAN-23.AC3.2, BEAN-23.AC3.3
<!-- END_TASK_5 -->
