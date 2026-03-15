# BeanLab Infrastructure — Test Requirements

**Plan:** `docs/implementation-plans/2026-03-09-beanlab-infra/`
**Design:** `docs/design-plans/2026-03-09-beanlab-infra.md`
**Generated:** 2026-03-11

---

## beanlab-infra.AC1: Cluster is reproducibly provisioned from shell scripts

| AC | Verification | Type |
|----|-------------|------|
| AC1.1 | Run `setup-server.sh` on server node. Verify k3s server is running: `systemctl status k3s`. Verify node labels: `kubectl get nodes --show-labels \| grep streaming` | Manual (on hardware) |
| AC1.2 | Run `setup-agent.sh` on agent node. Verify agent joins: `kubectl get nodes` shows 2 nodes | Manual (on hardware) |
| AC1.3 | `kubectl get nodes` — both nodes show `Ready` status | Manual (on hardware) |
| AC1.4 | Re-run both scripts. Verify exit code 0, no errors in output, `kubectl get nodes` unchanged | Manual (on hardware) |
| AC1.5 | `kubectl get nodes --show-labels` — verify `node-role.beanlab/media=true` on agent, `node-role.beanlab/streaming=true` on server | Manual (on hardware) |

**Pre-deploy verification:** `bash -n scripts/setup-server.sh && bash -n scripts/setup-agent.sh` (syntax check only)

---

## beanlab-infra.AC2: Apps deployed and updated via Flux CD

| AC | Verification | Type |
|----|-------------|------|
| AC2.1 | After bootstrap: `flux get kustomizations` — all show `Ready True` | Manual (on cluster) |
| AC2.2 | Push a trivial change (e.g., add annotation to a deployment). Wait for interval. Verify `flux get kustomizations` shows recent `lastAppliedRevision` matching pushed commit | Manual (on cluster) |
| AC2.3 | `flux get kustomizations` — verify `infrastructure` reconciles before `apps` (check timestamps, or verify apps Kustomization has `dependsOn: infrastructure`) | Manifest inspection + manual |
| AC2.4 | Push intentionally invalid YAML. Verify `flux get kustomizations` shows error for that kustomization. Verify existing pods unaffected: `kubectl get pods` unchanged | Manual (on cluster) |

**Pre-deploy verification:** Validate Flux Kustomization manifests: verify `clusters/beanlab/apps.yaml` contains `dependsOn: [{name: infrastructure}]`

---

## beanlab-infra.AC3: Jellyfin runs on horseradish serving local media, accessible externally

| AC | Verification | Type |
|----|-------------|------|
| AC3.1 | `kubectl get pod -l app=jellyfin -o wide` — NODE column shows agent node | Manual (on cluster) |
| AC3.2 | Open Jellyfin web UI, navigate to library. Verify media files from `/srv/media/library/` are browsable and playable | Manual (browser) |
| AC3.3 | On agent node: `cp testfile.mkv /srv/media/library/`. Trigger Jellyfin library scan. Verify file appears in UI | Manual (on hardware + browser) |
| AC3.4 | Access Jellyfin via DDNS domain over HTTPS. Verify valid TLS certificate (browser padlock, or `curl -vI https://<domain>`) | Manual (external network) |
| AC3.5 | `kubectl delete pod -l app=jellyfin`. Wait for replacement pod. Verify Jellyfin config/libraries still present in UI | Manual (on cluster + browser) |

**Pre-deploy verification:** Validate manifest: nodeSelector targets `node-role.beanlab/media: "true"`, PVC references correct storageClass, Ingress has TLS annotation with `letsencrypt-prod` ClusterIssuer

---

## beanlab-infra.AC4: Media ripping pipeline runs on horseradish

| AC | Verification | Type |
|----|-------------|------|
| AC4.1 | `kubectl get pod -l app=makemkv -o wide` — runs on agent node. `kubectl exec` into pod, verify `/dev/sr0` exists | Manual (on cluster) |
| AC4.2 | Access MakeMKV web UI via `http://<agent-node-ip>:<nodeport>` | Manual (browser) |
| AC4.3 | Insert a disc, rip via MakeMKV UI. On agent node: `ls /srv/media/ripping/` — verify ripped files appear | Manual (on hardware + browser) |
| AC4.4 | `kubectl get pod -l app=handbrake -o wide` — runs on server node. `kubectl exec` into pod, verify `/storage` (NFS) is readable | Manual (on cluster) |
| AC4.5 | Encode a file via HandBrake UI (input from `/storage`, output to `/output`). On agent node: `ls /srv/media/library/` — verify encoded file appears | Manual (on hardware + browser) |
| AC4.6 | Access HandBrake web UI via `http://<server-node-ip>:<nodeport>` | Manual (browser) |

**Pre-deploy verification:** Validate manifests: MakeMKV has BlockDevice hostPath for `/dev/sr0`, SYS_ADMIN + SYS_RAWIO capabilities; HandBrake has NFS PVC with subPaths `ripping` and `library`

---

## beanlab-infra.AC5: Home Assistant is deployed and accessible

| AC | Verification | Type |
|----|-------------|------|
| AC5.1 | `kubectl get pod -l app=homeassistant -o wide` — runs on server node. `kubectl get pod -o yaml` — verify `hostNetwork: true` | Manual (on cluster) |
| AC5.2 | Access `http://<server-node-ip>:8123` in browser. Verify Home Assistant onboarding or dashboard loads | Manual (browser) |
| AC5.3 | In Home Assistant, go to Settings > Devices & Services > Add Integration > search for an mDNS-discoverable device on the LAN (e.g., Chromecast, smart speaker). Verify it appears in discovery | Manual (browser + LAN devices) |
| AC5.4 | `kubectl delete pod -l app=homeassistant`. Wait for replacement. Verify config/automations still present in UI | Manual (on cluster + browser) |

**Pre-deploy verification:** Validate manifest: `hostNetwork: true`, `dnsPolicy: ClusterFirstWithHostNet`, nodeSelector targets `node-role.beanlab/streaming: "true"`, PVC uses `local-path`

---

## beanlab-infra.AC6: beanJAMinBOT is deployed and running

| AC | Verification | Type |
|----|-------------|------|
| AC6.1 | `kubectl get pod -l app=beanjaminbot -o wide` — runs on server node | Manual (on cluster) |
| AC6.2 | `kubectl logs -l app=beanjaminbot` — verify IRC connection success messages. Send a test command in Twitch chat, verify bot responds | Manual (on cluster + Twitch) |
| AC6.3 | `kubectl delete pod -l app=beanjaminbot`. Wait for replacement. `kubectl logs` — verify bot loads existing config without errors | Manual (on cluster) |
| AC6.4 | `kubectl get secret beanjaminbot-auth` — exists. `grep -r botjamin_auth` in repo — no credentials in plain text. Verify deployment mounts secret via `subPath` | Manual (on cluster) + manifest inspection |

**Pre-deploy verification:** Validate manifest: deployment references `beanjaminbot-auth` Secret, auth mounted as `subPath` (not full directory), PVCs use `local-path`

---

## Notes

- All ACs require physical hardware and a running cluster — no automated tests are possible for deployment verification
- "Pre-deploy verification" steps can be run during implementation to validate manifests before cluster deployment
- Shell script syntax checks (`bash -n`) serve as the only automated pre-deploy gate
- Post-deploy verification follows a linear order: AC1 (cluster) → AC2 (Flux) → AC3-AC6 (apps)
