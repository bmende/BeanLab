# Test Requirements: BEAN-23 LAN DNS Server

This document maps each acceptance criterion from the [design plan](../../design-plans/2026-03-20-BEAN-23.md) to manual verification steps. There are no automated tests — all verification is performed manually via kubectl, dig, SSH, browser, or LAN device commands.

---

## Verification Types

| Type | Description |
|------|-------------|
| Manual (on cluster) | kubectl or flux commands from a machine with cluster access |
| Manual (on hardware) | SSH into wasabi and run commands directly on the node |
| Manual (browser) | Router admin UI in a web browser |
| Manual (LAN device) | Commands or actions on a phone, laptop, or other LAN client |
| Manual (local repo) | Commands run against the local git checkout |

---

## AC1: LAN-facing DNS server runs in k3s serving local zones

### BEAN-23.AC1.1 — CoreDNS pod is Running on wasabi

- **Criterion:** `kubectl get pod -n dns -o wide` shows CoreDNS pod in Running state with wasabi in the NODE column
- **Verification type:** Manual (on cluster)
- **Phase/Task:** Phase 1, Task 5
- **Steps:**
  1. Run: `kubectl get pod -n dns -o wide`
  2. Verify the `coredns-lan-*` pod shows `STATUS: Running`
  3. Verify the `NODE` column shows `wasabi`
- **Expected output:** One pod in Running state scheduled on wasabi

### BEAN-23.AC1.2 — dig resolves local A record from seed zone file

- **Criterion:** `dig @192.168.50.101 jellyfin.beanlab` returns the correct A record from the seed zone file
- **Verification type:** Manual (on hardware)
- **Phase/Task:** Phase 2, Task 3
- **Steps:**
  1. SSH into wasabi: `ssh wasabi`
  2. Run: `dig @192.168.50.101 jellyfin.beanlab`
  3. Verify response contains `status: NOERROR`
  4. Verify ANSWER SECTION contains `jellyfin.beanlab. 3600 IN A 192.168.50.102`
- **Expected output:** NOERROR status with correct A record in the answer section

### BEAN-23.AC1.3 — Adding a second zone file auto-discovers without config changes

- **Criterion:** Adding a second zone file `db.testzone` causes CoreDNS to serve `testzone` records without any Corefile or Deployment changes
- **Verification type:** Manual (on hardware)
- **Phase/Task:** Phase 2, Task 5
- **Steps:**
  1. SSH into wasabi: `ssh wasabi`
  2. Create `/etc/coredns-lan/zones/db.testzone` with a valid zone file containing `hello IN A 192.168.50.200`
  3. Wait 15 seconds for the auto plugin to detect the new file
  4. Run: `dig @192.168.50.101 hello.testzone`
  5. Verify ANSWER SECTION contains `hello.testzone. 3600 IN A 192.168.50.200`
  6. Verify the original zone still works: `dig @192.168.50.101 jellyfin.beanlab` still returns `192.168.50.102`
  7. Clean up: `sudo rm /etc/coredns-lan/zones/db.testzone`
- **Expected output:** New zone resolves correctly; existing zone unaffected; no Corefile or Deployment changes made

### BEAN-23.AC1.4 — Zone file with syntax error is skipped gracefully

- **Criterion:** Zone file with syntax error is skipped; other zones and upstream forwarding continue working
- **Verification type:** Manual (on hardware) + Manual (on cluster)
- **Phase/Task:** Phase 2, Task 6
- **Steps:**
  1. SSH into wasabi: `ssh wasabi`
  2. Create a malformed zone file: `sudo tee /etc/coredns-lan/zones/db.badzone <<< "this is not a valid zone file"`
  3. Wait 15 seconds
  4. Check CoreDNS logs: `kubectl logs -n dns -l app=coredns-lan --tail=10`
  5. Verify logs contain an error about parsing `db.badzone`
  6. Verify CoreDNS pod is still Running: `kubectl get pod -n dns`
  7. Verify beanlab zone still works: `dig @192.168.50.101 jellyfin.beanlab` returns `192.168.50.102`
  8. Verify upstream forwarding still works: `dig @192.168.50.101 google.com` returns A records
  9. Clean up: `sudo rm /etc/coredns-lan/zones/db.badzone`
- **Expected output:** Error in logs for bad zone; pod still Running; other zones and forwarding unaffected

---

## AC2: DNS records stored locally, managed by editing a file

### BEAN-23.AC2.1 — Zone files exist on wasabi and are editable via SSH

- **Criterion:** Zone files exist at `/etc/coredns-lan/zones/` on wasabi and are editable via SSH
- **Verification type:** Manual (on hardware)
- **Phase/Task:** Phase 2, Task 7
- **Steps:**
  1. SSH into wasabi: `ssh wasabi`
  2. Run: `ls -la /etc/coredns-lan/zones/`
  3. Verify `db.beanlab` is listed
  4. Run: `cat /etc/coredns-lan/zones/db.beanlab`
  5. Verify the file contains valid zone records (SOA, NS, A records)
  6. Verify the file is writable: `sudo touch /etc/coredns-lan/zones/db.beanlab` (should succeed without error)
- **Expected output:** Zone file exists, contains DNS records, and is writable via sudo

### BEAN-23.AC2.2 — Editing zone file with serial increment updates records within 10 seconds

- **Criterion:** Editing a zone file and incrementing the SOA serial causes CoreDNS to serve updated records within 10 seconds
- **Verification type:** Manual (on hardware)
- **Phase/Task:** Phase 2, Task 4
- **Steps:**
  1. SSH into wasabi: `ssh wasabi`
  2. Add a test A record to `/etc/coredns-lan/zones/db.beanlab` (e.g., `test-stale IN A 192.168.50.200`)
  3. Increment the SOA serial (e.g., `2026032001` to `2026032002`)
  4. Wait 15 seconds
  5. Run: `dig @192.168.50.101 test-stale.beanlab`
  6. Verify ANSWER SECTION contains the new A record
  7. Clean up: remove the test record and bump serial again
- **Expected output:** New record resolves after serial increment and reload interval

### BEAN-23.AC2.3 — Zone file content is not in the git repo

- **Criterion:** `grep -r 'db\.beanlab' /home/bmende/Projects/BeanLab/` finds no zone file content in the git repo
- **Verification type:** Manual (local repo)
- **Phase/Task:** Phase 2, Task 7
- **Steps:**
  1. Run: `grep -r 'db\.beanlab' /home/bmende/Projects/BeanLab/`
  2. Review any matches
  3. Verify that matches only appear in documentation files (design plans, implementation plans, test-requirements) as filename references — NOT as actual zone file content with SOA records, A records, or zone syntax
- **Expected output:** No zone file content committed to git. References to the filename `db.beanlab` in docs are acceptable.
- **Requires human judgment:** Yes — must distinguish between filename references in docs and actual zone file content

### BEAN-23.AC2.4 — Editing without serial increment does NOT update records

- **Criterion:** Editing a zone file WITHOUT incrementing the SOA serial does NOT update served records (stale until serial bumped)
- **Verification type:** Manual (on hardware)
- **Phase/Task:** Phase 2, Task 4
- **Steps:**
  1. SSH into wasabi: `ssh wasabi`
  2. Add a test A record to `/etc/coredns-lan/zones/db.beanlab` (e.g., `test-stale IN A 192.168.50.200`) WITHOUT changing the SOA serial
  3. Wait 15 seconds
  4. Run: `dig @192.168.50.101 test-stale.beanlab`
  5. Verify response is `NXDOMAIN` — the record is NOT served because the serial was not incremented
- **Expected output:** NXDOMAIN — CoreDNS ignores the change until the serial is bumped

---

## AC3: DNS deployment is Flux-managed

### BEAN-23.AC3.1 — Manifests exist in infrastructure/coredns-lan/ and are listed in infrastructure kustomization

- **Criterion:** CoreDNS manifests exist in `infrastructure/coredns-lan/` and are listed in `infrastructure/kustomization.yaml`
- **Verification type:** Manual (local repo)
- **Phase/Task:** Phase 1, Task 4
- **Steps:**
  1. Verify the following files exist:
     - `infrastructure/coredns-lan/namespace.yaml`
     - `infrastructure/coredns-lan/configmap.yaml`
     - `infrastructure/coredns-lan/deployment.yaml`
     - `infrastructure/coredns-lan/kustomization.yaml`
  2. Run: `grep 'coredns-lan' /home/bmende/Projects/BeanLab/infrastructure/kustomization.yaml`
  3. Verify `coredns-lan/` appears in the resources list
- **Expected output:** All four manifest files exist; `coredns-lan/` is listed in the parent kustomization

### BEAN-23.AC3.2 — Flux shows infrastructure reconciled with coredns-lan resources

- **Criterion:** `flux get kustomizations` shows infrastructure reconciled with coredns-lan resources
- **Verification type:** Manual (on cluster)
- **Phase/Task:** Phase 1, Task 5
- **Steps:**
  1. Run: `flux reconcile kustomization infrastructure --with-source`
  2. Run: `flux get kustomizations`
  3. Verify `infrastructure` shows `Ready: True` with a recent revision
  4. Run: `kubectl get all -n dns`
  5. Verify the coredns-lan Deployment and Pod are listed
- **Expected output:** Infrastructure kustomization is Ready; dns namespace contains the coredns-lan resources

### BEAN-23.AC3.3 — Pod restart preserves zone files (hostPath survives)

- **Criterion:** Deleting the CoreDNS pod causes Kubernetes to recreate it; zone files persist across pod restart (hostPath survives)
- **Verification type:** Manual (on cluster) + Manual (on hardware)
- **Phase/Task:** Phase 1, Task 5
- **Steps:**
  1. Run: `kubectl delete pod -n dns -l app=coredns-lan`
  2. Wait for the replacement pod: `kubectl get pod -n dns -o wide -w` (watch until Running)
  3. Verify new pod is Running on wasabi
  4. SSH into wasabi: `ssh wasabi`
  5. Verify zone files survived: `ls -la /etc/coredns-lan/zones/`
  6. Verify DNS still works: `dig @192.168.50.101 jellyfin.beanlab` (returns correct A record, assuming Phase 2 seed zone is in place)
- **Expected output:** New pod starts automatically; zone directory and files on wasabi are intact

---

## AC4: DHCP failover — cluster down degrades gracefully

### BEAN-23.AC4.1 — LAN device resolves local hostname using DHCP-assigned DNS

- **Criterion:** LAN device resolves `jellyfin.beanlab` using DHCP-assigned DNS (no manual `dig @` needed)
- **Verification type:** Manual (LAN device)
- **Phase/Task:** Phase 3, Task 2
- **Steps:**
  1. On a LAN device that has renewed its DHCP lease after router configuration:
     - macOS: `scutil --dns | head -20` to verify DNS server is `192.168.50.101`
     - Linux: `resolvectl status` to verify DNS server is `192.168.50.101`
  2. Run: `dig jellyfin.beanlab` (no `@` server specified)
  3. Verify the response returns `192.168.50.102`
- **Expected output:** Local hostname resolves using the DHCP-assigned DNS server without explicit server targeting
- **Requires human judgment:** Yes — if `dig` is unavailable on the test device, use `nslookup jellyfin.beanlab` or try opening `http://jellyfin.beanlab` in a browser (only works if Jellyfin is running)

### BEAN-23.AC4.2 — LAN device resolves internet hostname through CoreDNS forwarding

- **Criterion:** LAN device resolves `google.com` through CoreDNS upstream forwarding
- **Verification type:** Manual (LAN device)
- **Phase/Task:** Phase 3, Task 2
- **Steps:**
  1. On the same LAN device, run: `dig google.com`
  2. Verify the response contains A records for google.com
  3. Optionally verify the SERVER line shows `192.168.50.101` (confirming it went through CoreDNS)
- **Expected output:** Internet hostname resolves successfully through CoreDNS forward plugin

### BEAN-23.AC4.3 — When CoreDNS is stopped, internet DNS still works via router fallback

- **Criterion:** When CoreDNS is stopped (`kubectl scale deployment -n dns coredns-lan --replicas=0`), LAN device still resolves `google.com` via router fallback
- **Verification type:** Manual (on cluster) + Manual (LAN device)
- **Phase/Task:** Phase 3, Task 3
- **Steps:**
  1. From a machine with kubectl access, run: `kubectl scale deployment -n dns coredns-lan --replicas=0`
  2. Verify no pods remain: `kubectl get pod -n dns`
  3. On a LAN device, run: `dig google.com`
  4. Verify the response still contains A records for google.com (resolved via router fallback)
  5. Note: the first query may take a few seconds as the device times out on the primary DNS before falling back
  6. **Restore CoreDNS after testing:** `kubectl scale deployment -n dns coredns-lan --replicas=1`
- **Expected output:** Internet DNS continues working via router fallback when CoreDNS is down
- **Requires human judgment:** Yes — fallback timeout behavior varies by OS and DNS resolver implementation. Some devices may take 5-30 seconds for the first fallback query. This is acceptable.

### BEAN-23.AC4.4 — When CoreDNS is stopped, local zones do NOT resolve

- **Criterion:** When CoreDNS is stopped, `jellyfin.beanlab` does NOT resolve (expected — no fallback for local zones)
- **Verification type:** Manual (LAN device)
- **Phase/Task:** Phase 3, Task 3
- **Steps:**
  1. With CoreDNS still scaled to zero (from AC4.3 testing), run on a LAN device: `dig jellyfin.beanlab`
  2. Verify the response is `NXDOMAIN` or `SERVFAIL` (the router does not know about `.beanlab`)
  3. **Restore CoreDNS after testing:** `kubectl scale deployment -n dns coredns-lan --replicas=1`
  4. Wait for the pod to start, then verify local DNS works again: `dig jellyfin.beanlab` returns `192.168.50.102`
- **Expected output:** Local zone does not resolve when CoreDNS is down; resolves again after CoreDNS restarts

---

## AC5: Record format supports arbitrary A records

### BEAN-23.AC5.1 — Zone file maps any hostname to any LAN IP

- **Criterion:** Zone file can map any hostname to any LAN IP (not limited to k3s service IPs)
- **Verification type:** Manual (on hardware)
- **Phase/Task:** Phase 2, Task 2
- **Steps:**
  1. SSH into wasabi: `ssh wasabi`
  2. Examine the seed zone file: `cat /etc/coredns-lan/zones/db.beanlab`
  3. Verify it contains A records mapping hostnames to different LAN IPs, including IPs that are NOT k3s service ClusterIPs. For example:
     - `wasabi IN A 192.168.50.101` (node IP, not a service IP)
     - `horseradish IN A 192.168.50.102` (node IP, not a service IP)
  4. Run: `dig @192.168.50.101 horseradish.beanlab`
  5. Verify the response returns `192.168.50.102`
- **Expected output:** Zone file contains and serves A records pointing to arbitrary LAN IPs, not just Kubernetes service IPs
- **Requires human judgment:** Yes — must confirm the IPs in the zone file are actual node/device LAN IPs, not Kubernetes ClusterIP addresses (which are in the `10.x.x.x` range)

### BEAN-23.AC5.2 — Zone file supports multiple A records for different hostnames

- **Criterion:** Zone file supports multiple A records for different hostnames in the same zone
- **Verification type:** Manual (on hardware)
- **Phase/Task:** Phase 2, Task 2 and Task 3
- **Steps:**
  1. SSH into wasabi: `ssh wasabi`
  2. Examine the seed zone file: `cat /etc/coredns-lan/zones/db.beanlab`
  3. Verify it contains multiple distinct A records (at minimum: wasabi, horseradish, jellyfin, ha)
  4. Query each record:
     - `dig @192.168.50.101 wasabi.beanlab` — expect `192.168.50.101`
     - `dig @192.168.50.101 horseradish.beanlab` — expect `192.168.50.102`
     - `dig @192.168.50.101 jellyfin.beanlab` — expect `192.168.50.102`
     - `dig @192.168.50.101 ha.beanlab` — expect `192.168.50.101`
  5. Verify all return correct, distinct results
- **Expected output:** Multiple hostnames in the same zone each resolve to their respective IPs

---

## Summary: Criteria Requiring Human Judgment

| Criterion | Reason |
|-----------|--------|
| BEAN-23.AC2.3 | Must distinguish between zone file filename references in documentation and actual zone file content committed to git |
| BEAN-23.AC4.1 | If `dig` is unavailable on the test device, alternative verification methods (nslookup, browser) may be needed |
| BEAN-23.AC4.3 | DNS fallback timeout behavior varies by OS and resolver; a delay of 5-30 seconds on the first query is acceptable |
| BEAN-23.AC5.1 | Must confirm that IPs in the zone file are LAN IPs (192.168.x.x), not Kubernetes ClusterIPs (10.x.x.x) |

---

## Phase-to-Criteria Traceability Matrix

| Phase | Task(s) | Criteria Verified |
|-------|---------|-------------------|
| Phase 1 | Tasks 1-4 | BEAN-23.AC3.1 (manifests exist) |
| Phase 1 | Task 5 | BEAN-23.AC1.1, BEAN-23.AC3.2, BEAN-23.AC3.3 |
| Phase 2 | Tasks 1-2 | BEAN-23.AC2.1, BEAN-23.AC5.1, BEAN-23.AC5.2 |
| Phase 2 | Task 3 | BEAN-23.AC1.2 |
| Phase 2 | Task 4 | BEAN-23.AC2.2, BEAN-23.AC2.4 |
| Phase 2 | Task 5 | BEAN-23.AC1.3 |
| Phase 2 | Task 6 | BEAN-23.AC1.4 |
| Phase 2 | Task 7 | BEAN-23.AC2.1, BEAN-23.AC2.3 |
| Phase 3 | Task 1 | (router configuration — prerequisite for AC4) |
| Phase 3 | Task 2 | BEAN-23.AC4.1, BEAN-23.AC4.2 |
| Phase 3 | Task 3 | BEAN-23.AC4.3, BEAN-23.AC4.4 |
