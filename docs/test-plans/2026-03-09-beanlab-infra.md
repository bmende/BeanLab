# BeanLab Infrastructure — Human Test Plan

## Prerequisites

- Two physical nodes available: **wasabi** (server/control plane) and **horseradish** (agent)
- Both nodes running Ubuntu/Debian with network connectivity between them
- A GitHub Personal Access Token with `repo` scope (for Flux bootstrap)
- A DDNS domain pointed at your external IP
- A valid email address for Let's Encrypt registration
- An optical disc (DVD/Blu-ray) for media pipeline testing
- Access to Twitch chat for beanJAMinBOT testing
- All placeholders substituted: `<AGENT_NODE_IP>`, `<YOUR_EMAIL>`, `<YOUR_DOMAIN>`, `<BOT_IMAGE>`
- Shell syntax checks passing: `bash -n scripts/setup-server.sh && bash -n scripts/setup-agent.sh`

## Phase 1: Cluster Provisioning (AC1)

| Step | Action | Expected |
|------|--------|----------|
| 1.1 | SSH into wasabi. Run `export K3S_TOKEN=<your-shared-secret> && ./scripts/setup-server.sh` | Script completes with exit code 0. Output shows "k3s server is ready" and prints kubeconfig path and node token |
| 1.2 | On wasabi, run `systemctl status k3s` | Service is active (running) |
| 1.3 | On wasabi, run `kubectl get nodes --show-labels` | One node listed with `node-role.beanlab/streaming=true` label |
| 1.4 | SSH into horseradish. Run `export K3S_URL=https://<wasabi-ip>:6443 K3S_TOKEN=<same-token> && ./scripts/setup-agent.sh` | Script completes with exit code 0. Output shows NFS export configured and media directories created |
| 1.5 | On wasabi, run `kubectl get nodes` | Two nodes listed, both in `Ready` status |
| 1.6 | On wasabi, run `kubectl get nodes --show-labels` | horseradish has `node-role.beanlab/media=true`, wasabi has `node-role.beanlab/streaming=true` |
| 1.7 | Re-run `./scripts/setup-server.sh` on wasabi (same env vars) | Exit code 0, no errors, `kubectl get nodes` unchanged |
| 1.8 | Re-run `./scripts/setup-agent.sh` on horseradish (same env vars) | Exit code 0, NFS export line not duplicated in `/etc/exports`, `kubectl get nodes` unchanged |

## Phase 2: Flux CD Bootstrap (AC2)

| Step | Action | Expected |
|------|--------|----------|
| 2.1 | On wasabi, run `./scripts/bootstrap-flux.sh` with `GITHUB_TOKEN` and `GITHUB_USER` set | Flux installs successfully, `flux get kustomizations` shows `flux-system`, `infrastructure`, and `apps` all `Ready True` |
| 2.2 | Verify dependency ordering: run `flux get kustomizations` and inspect timestamps | `infrastructure` reconciled before `apps` |
| 2.3 | Push a trivial change (e.g., add annotation to a deployment), commit, and push to master | Within 10 minutes, `flux get kustomizations` shows updated `lastAppliedRevision` matching the pushed commit |
| 2.4 | Push intentionally invalid YAML, commit and push | `flux get kustomizations` shows error status. Existing pods remain running and unaffected |
| 2.5 | Revert the invalid YAML, commit and push | Kustomization returns to `Ready True` |

## Phase 3: Jellyfin (AC3)

| Step | Action | Expected |
|------|--------|----------|
| 3.1 | Run `kubectl get pod -l app=jellyfin -o wide` | Pod is Running, NODE column shows horseradish |
| 3.2 | On horseradish, run `ls /srv/media/library/` | Directory exists |
| 3.3 | Open browser to `http://<horseradish-ip>:8096` | Jellyfin web UI loads |
| 3.4 | On horseradish, copy a sample media file: `cp /path/to/testfile.mkv /srv/media/library/` | File copied |
| 3.5 | In Jellyfin UI, trigger library scan (Dashboard > Libraries > Scan All Libraries) | Test file appears and is playable |
| 3.6 | From an external network, navigate to `https://<your-ddns-domain>` | Jellyfin loads over HTTPS with valid TLS certificate (padlock icon) |
| 3.7 | Run `kubectl delete pod -l app=jellyfin` and wait for replacement | New pod starts. Jellyfin UI shows previously configured libraries and settings |

## Phase 4: Media Pipeline (AC4)

| Step | Action | Expected |
|------|--------|----------|
| 4.1 | Run `kubectl get pod -l app=makemkv -o wide` | Pod is Running, NODE column shows horseradish |
| 4.2 | Run `kubectl exec -it <makemkv-pod> -- ls -la /dev/sr0` | `/dev/sr0` exists as a block device inside the container |
| 4.3 | Open browser to `http://<horseradish-ip>:<makemkv-nodeport>` | MakeMKV web UI loads |
| 4.4 | Insert a disc. In MakeMKV UI, select the drive and start a rip | Ripping begins; progress visible in UI |
| 4.5 | After rip completes, on horseradish run `ls /srv/media/ripping/` | Ripped `.mkv` files appear |
| 4.6 | Run `kubectl get pod -l app=handbrake -o wide` | Pod is Running, NODE column shows wasabi |
| 4.7 | Run `kubectl exec -it <handbrake-pod> -- ls /storage` | Shows ripped files from `/srv/media/ripping/` via NFS |
| 4.8 | Open browser to `http://<wasabi-ip>:<handbrake-nodeport>` | HandBrake web UI loads |
| 4.9 | In HandBrake UI, select a ripped file from `/storage`, encode with output to `/output` | Encoding begins; progress visible |
| 4.10 | After encoding completes, on horseradish run `ls /srv/media/library/` | Encoded file appears in library directory |

## Phase 5: Home Assistant (AC5)

| Step | Action | Expected |
|------|--------|----------|
| 5.1 | Run `kubectl get pod -l app=homeassistant -o wide` | Pod is Running, NODE column shows wasabi |
| 5.2 | Run `kubectl get pod -l app=homeassistant -o yaml` and verify `hostNetwork: true` | `hostNetwork: true` and `dnsPolicy: ClusterFirstWithHostNet` present |
| 5.3 | Open browser to `http://<wasabi-ip>:8123` | Home Assistant onboarding wizard or dashboard loads |
| 5.4 | In Home Assistant, navigate to Settings > Devices & Services > Add Integration. Search for an mDNS-discoverable device | Device appears in the discovery list |
| 5.5 | Run `kubectl delete pod -l app=homeassistant` and wait for replacement | New pod starts. Settings/automations preserved |

## Phase 6: beanJAMinBOT (AC6)

| Step | Action | Expected |
|------|--------|----------|
| 6.1 | Create the auth secret: `kubectl create secret generic beanjaminbot-auth --from-file=botjamin_auth.yaml=<path>` | Secret created successfully |
| 6.2 | Run `kubectl get pod -l app=beanjaminbot -o wide` | Pod is Running, NODE column shows wasabi |
| 6.3 | Run `kubectl logs -l app=beanjaminbot --tail=50` | Logs show successful Twitch/IRC connection, no auth errors |
| 6.4 | In Twitch chat, send a test command the bot recognizes | Bot responds in chat |
| 6.5 | Run `kubectl get secret beanjaminbot-auth` | Secret exists |
| 6.6 | Run `grep -r botjamin_auth /home/bmende/Projects/BeanLab/` | No credentials in plain text (only Secret reference and README) |
| 6.7 | Run `kubectl delete pod -l app=beanjaminbot` and wait for replacement | Bot loads existing config and reconnects |

## End-to-End: Full Media Workflow

1. Insert a disc into horseradish's optical drive
2. Open MakeMKV web UI, rip the disc to `/output` (maps to `/srv/media/ripping/`)
3. Verify ripped file: SSH to horseradish, `ls -lh /srv/media/ripping/`
4. Open HandBrake web UI, verify ripped file visible in `/storage` (NFS mount)
5. Encode the file, output to `/output` (maps to `/srv/media/library/` via NFS)
6. Verify encoded file: SSH to horseradish, `ls -lh /srv/media/library/`
7. Open Jellyfin web UI, trigger library scan, confirm new file appears and is playable
8. Access Jellyfin via DDNS domain from external network, confirm playable over HTTPS

## End-to-End: Cluster Recovery

1. Record current state: `kubectl get pods -o wide`, `flux get kustomizations`
2. On horseradish, re-run `./scripts/setup-agent.sh` (simulating reprovision)
3. Wait for node to rejoin: `kubectl get nodes` shows both nodes Ready
4. Wait for Flux reconciliation (up to 10 minutes or `flux reconcile kustomization apps`)
5. Run `kubectl get pods -o wide` — all pods return to correct nodes
6. Verify Jellyfin UI, MakeMKV UI, and stored media are intact

## Traceability

| Acceptance Criterion | Pre-deploy Check | Manual Step |
|----------------------|------------------|-------------|
| AC1.1 Server provisioning | `bash -n setup-server.sh` PASS | Step 1.1-1.2 |
| AC1.2 Agent provisioning | `bash -n setup-agent.sh` PASS | Step 1.4 |
| AC1.3 Both nodes Ready | — | Step 1.5 |
| AC1.4 Idempotent scripts | `bash -n` both scripts PASS | Steps 1.7-1.8 |
| AC1.5 Node labels | — | Step 1.6 |
| AC2.1 Flux kustomizations Ready | — | Step 2.1 |
| AC2.2 GitOps reconciliation | — | Step 2.3 |
| AC2.3 Dependency ordering | `apps.yaml` has `dependsOn: infrastructure` | Step 2.2 |
| AC2.4 Invalid YAML resilience | — | Step 2.4 |
| AC3.1 Jellyfin on agent node | nodeSelector `media: "true"` | Step 3.1 |
| AC3.2 Media browsable/playable | — | Steps 3.3-3.5 |
| AC3.3 New media detected | — | Steps 3.4-3.5 |
| AC3.4 External HTTPS access | Ingress has `letsencrypt-prod` | Step 3.6 |
| AC3.5 Config persists | — | Step 3.7 |
| AC4.1 MakeMKV on agent with drive | BlockDevice + SYS_ADMIN/SYS_RAWIO | Steps 4.1-4.2 |
| AC4.2 MakeMKV web UI | — | Step 4.3 |
| AC4.3 Rip to ripping dir | — | Steps 4.4-4.5 |
| AC4.4 HandBrake on server with NFS | NFS PVC + subPaths | Steps 4.6-4.7 |
| AC4.5 Encode to library | — | Steps 4.9-4.10 |
| AC4.6 HandBrake web UI | — | Step 4.8 |
| AC5.1 HA on server with hostNetwork | `hostNetwork: true` + nodeSelector | Steps 5.1-5.2 |
| AC5.2 HA web UI | — | Step 5.3 |
| AC5.3 mDNS discovery | — | Step 5.4 |
| AC5.4 Config persists | — | Step 5.5 |
| AC6.1 Bot on server | — | Step 6.2 |
| AC6.2 Bot connects/responds | — | Steps 6.3-6.4 |
| AC6.3 Bot config persists | — | Step 6.7 |
| AC6.4 Secrets not in repo | Secret ref + subPath mount | Steps 6.5-6.6 |
