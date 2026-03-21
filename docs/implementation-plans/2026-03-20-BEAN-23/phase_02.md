# LAN DNS Server Implementation Plan

**Goal:** Create the seed zone file on wasabi and verify end-to-end DNS resolution

**Architecture:** Zone file at `/etc/coredns-lan/zones/db.beanlab` on wasabi, edited via SSH. CoreDNS auto plugin detects it automatically. Verification via `dig` for local and upstream queries.

**Tech Stack:** CoreDNS (running from Phase 1), RFC 1035 zone files, dig

**Scope:** 3 phases from original design (phases 1-3)

**Codebase verified:** 2026-03-20

---

## Acceptance Criteria Coverage

This phase implements and verifies:

### BEAN-23.AC1: LAN-facing DNS server runs in k3s serving local zones
- **BEAN-23.AC1.1 Success:** CoreDNS pod is Running on wasabi (`kubectl get pod -n dns -o wide` shows wasabi in NODE column)
- **BEAN-23.AC1.2 Success:** `dig @192.168.50.101 jellyfin.beanlab` returns the correct A record from the seed zone file
- **BEAN-23.AC1.3 Success:** Adding a second zone file `db.testzone` causes CoreDNS to serve `testzone` records without any Corefile or Deployment changes
- **BEAN-23.AC1.4 Failure:** Zone file with syntax error is skipped; other zones and upstream forwarding continue working

### BEAN-23.AC2: DNS records stored locally, managed by editing a file
- **BEAN-23.AC2.1 Success:** Zone files exist at `/etc/coredns-lan/zones/` on wasabi and are editable via SSH
- **BEAN-23.AC2.2 Success:** Editing a zone file and incrementing the SOA serial causes CoreDNS to serve updated records within 10 seconds
- **BEAN-23.AC2.3 Success:** `grep -r 'db\.beanlab' /home/bmende/Projects/BeanLab/` finds no zone file content in the git repo
- **BEAN-23.AC2.4 Failure:** Editing a zone file WITHOUT incrementing the SOA serial does NOT update served records (stale until serial bumped)

### BEAN-23.AC5: Record format supports arbitrary A records
- **BEAN-23.AC5.1 Success:** Zone file can map any hostname to any LAN IP (not limited to k3s service IPs)
- **BEAN-23.AC5.2 Success:** Zone file supports multiple A records for different hostnames in the same zone

---

**IMPORTANT: This phase is entirely operational — performed via SSH on wasabi. No files are committed to git. Zone files must NOT be added to the repository.**

<!-- START_TASK_1 -->
### Task 1: Create zone directory on wasabi

**Performed on:** wasabi (via SSH)

**Step 1: SSH into wasabi**

```bash
ssh wasabi
```

**Step 2: Create the zone directory**

```bash
sudo mkdir -p /etc/coredns-lan/zones
```

The directory may already exist if the CoreDNS pod was deployed with `type: DirectoryOrCreate` from Phase 1. This command is idempotent.

**Step 3: Verify the directory exists and is accessible**

```bash
ls -la /etc/coredns-lan/zones/
```

Expected: Empty directory listing.
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create seed zone file for beanlab

**Performed on:** wasabi (via SSH)

**Step 1: Create the zone file**

Create `/etc/coredns-lan/zones/db.beanlab` with this exact content:

```bash
sudo tee /etc/coredns-lan/zones/db.beanlab << 'EOF'
; Zone file for beanlab
; IMPORTANT: Increment the SOA serial (YYYYMMDDNN format) after every edit,
; or CoreDNS will NOT pick up changes.

$ORIGIN beanlab.
$TTL 3600

@  IN  SOA  ns.beanlab. hostmaster.beanlab. (
         2026032001  ; Serial — MUST increment on every change (YYYYMMDDNN)
         10800       ; Refresh (3h)
         3600        ; Retry (1h)
         604800      ; Expire (7d)
         3600 )      ; Minimum TTL (1h)

   IN  NS   ns.beanlab.

; --- Infrastructure ---
ns          IN  A  192.168.50.101  ; wasabi (DNS server itself)
wasabi      IN  A  192.168.50.101
horseradish IN  A  192.168.50.102

; --- Services ---
jellyfin    IN  A  192.168.50.102  ; media server on horseradish
ha          IN  A  192.168.50.101  ; Home Assistant on wasabi
EOF
```

**Key details:**
- `$ORIGIN beanlab.` sets the zone origin (trailing dot is required)
- SOA serial `2026032001` means first edit on 2026-03-20. Bump to `2026032002` for the next change, etc.
- The comment about serial incrementing is intentional — this is the most common operational mistake per the design
- IPs shown are based on the design plan (`192.168.50.101` = wasabi, `192.168.50.102` = horseradish). Adjust if your actual IPs differ.
- Records map arbitrary hostnames to arbitrary LAN IPs — not limited to k3s service IPs (verifies BEAN-23.AC5.1)
- Multiple A records for different hostnames in the same zone (verifies BEAN-23.AC5.2)

**Step 2: Verify the file was written correctly**

```bash
cat /etc/coredns-lan/zones/db.beanlab
```

Expected: The zone file content shown above.
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Verify CoreDNS picks up the zone file and serves local records

**Performed on:** wasabi (via SSH)

**Step 1: Wait for CoreDNS to detect the zone file**

The `auto` plugin scans every 10 seconds. Wait ~15 seconds after creating the file.

**Step 2: Check CoreDNS logs for zone loading**

```bash
kubectl logs -n dns -l app=coredns-lan --tail=20
```

Expected: Log line indicating the `beanlab` zone was loaded (e.g., a log entry showing queries being served or zone detection).

**Step 3: Query for a local record**

```bash
dig @192.168.50.101 jellyfin.beanlab
```

Expected output should include:
- `status: NOERROR`
- An `ANSWER SECTION` with `jellyfin.beanlab. 3600 IN A 192.168.50.102`

**Verifies:** BEAN-23.AC1.2

**Step 4: Query for another local record**

```bash
dig @192.168.50.101 wasabi.beanlab
```

Expected: `ANSWER SECTION` with `wasabi.beanlab. 3600 IN A 192.168.50.101`

**Step 5: Query for upstream forwarding**

```bash
dig @192.168.50.101 google.com
```

Expected output should include:
- `status: NOERROR`
- An `ANSWER SECTION` with one or more A records for google.com
- This proves the `forward` plugin is working correctly
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Verify zone file editing and SOA serial reload behavior

**Performed on:** wasabi (via SSH)

**Step 1: Edit the zone file WITHOUT incrementing the serial**

Add a test record to the zone file but do NOT change the serial:

```bash
sudo sed -i '/^ha /a test-stale   IN  A  192.168.50.200' /etc/coredns-lan/zones/db.beanlab
```

**Step 2: Wait 15 seconds and query the new record**

```bash
sleep 15
dig @192.168.50.101 test-stale.beanlab
```

Expected: `status: NXDOMAIN` — the record should NOT resolve because the SOA serial was not incremented.

**Verifies:** BEAN-23.AC2.4

**Step 3: Now increment the SOA serial**

Edit `/etc/coredns-lan/zones/db.beanlab` and change the serial from `2026032001` to `2026032002`:

```bash
sudo sed -i 's/2026032001/2026032002/' /etc/coredns-lan/zones/db.beanlab
```

**Step 4: Wait 15 seconds and query again**

```bash
sleep 15
dig @192.168.50.101 test-stale.beanlab
```

Expected: `ANSWER SECTION` with `test-stale.beanlab. 3600 IN A 192.168.50.200`

**Verifies:** BEAN-23.AC2.2

**Step 5: Clean up the test record**

Remove the test record and bump the serial again:

```bash
sudo sed -i '/^test-stale/d' /etc/coredns-lan/zones/db.beanlab
sudo sed -i 's/2026032002/2026032003/' /etc/coredns-lan/zones/db.beanlab
```
<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Verify adding a second zone (auto-discovery)

**Performed on:** wasabi (via SSH)

**Step 1: Create a second zone file**

```bash
sudo tee /etc/coredns-lan/zones/db.testzone << 'EOF'
$ORIGIN testzone.
$TTL 3600

@  IN  SOA  ns.testzone. hostmaster.testzone. (
         2026032001
         10800
         3600
         604800
         3600 )

   IN  NS   ns.testzone.

ns    IN  A  192.168.50.101
hello IN  A  192.168.50.200
EOF
```

**Step 2: Wait for auto-discovery (15 seconds)**

```bash
sleep 15
```

**Step 3: Query the new zone**

```bash
dig @192.168.50.101 hello.testzone
```

Expected: `ANSWER SECTION` with `hello.testzone. 3600 IN A 192.168.50.200`

**Verifies:** BEAN-23.AC1.3 — new zone served without any Corefile or Deployment changes

**Step 4: Verify the original zone still works**

```bash
dig @192.168.50.101 jellyfin.beanlab
```

Expected: Still returns `192.168.50.102`

**Step 5: Clean up the test zone**

```bash
sudo rm /etc/coredns-lan/zones/db.testzone
```
<!-- END_TASK_5 -->

<!-- START_TASK_6 -->
### Task 6: Verify zone file syntax error handling

**Performed on:** wasabi (via SSH)

**Step 1: Create a zone file with intentional syntax errors**

```bash
sudo tee /etc/coredns-lan/zones/db.badzone << 'EOF'
this is not a valid zone file
completely broken syntax
EOF
```

**Step 2: Wait 15 seconds and check CoreDNS logs**

```bash
sleep 15
kubectl logs -n dns -l app=coredns-lan --tail=10
```

Expected: Error log line about failing to parse `db.badzone`. CoreDNS should NOT crash.

**Step 3: Verify other zones still work**

```bash
dig @192.168.50.101 jellyfin.beanlab
```

Expected: Still returns `192.168.50.102` — the beanlab zone is unaffected.

**Step 4: Verify upstream forwarding still works**

```bash
dig @192.168.50.101 google.com
```

Expected: Still returns A records for google.com.

**Verifies:** BEAN-23.AC1.4

**Step 5: Clean up the bad zone**

```bash
sudo rm /etc/coredns-lan/zones/db.badzone
```
<!-- END_TASK_6 -->

<!-- START_TASK_7 -->
### Task 7: Verify zone files are not in git

**Performed on:** local machine (not wasabi)

**Step 1: Search the git repo for zone file content**

```bash
grep -r 'db\.beanlab' /home/bmende/Projects/BeanLab/
```

Expected: No matches referencing actual zone file content. Matches in design docs and implementation plan docs (referencing the filename) are acceptable — but no file containing SOA records, A records, or zone file syntax should exist in the repo.

**Verifies:** BEAN-23.AC2.3

**Step 2: Verify zone files exist on wasabi**

```bash
ssh wasabi ls -la /etc/coredns-lan/zones/
```

Expected: `db.beanlab` file listed.

**Verifies:** BEAN-23.AC2.1
<!-- END_TASK_7 -->
