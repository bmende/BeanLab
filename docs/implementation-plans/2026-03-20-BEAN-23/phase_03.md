# LAN DNS Server Implementation Plan

**Goal:** Configure router DHCP to hand out CoreDNS as primary DNS with router fallback

**Architecture:** ASUS ZenWiFi AX Mini DHCP settings updated to use wasabi (`192.168.50.101`) as primary DNS and router (`192.168.50.1`) as fallback. LAN devices get DNS settings automatically on lease renewal.

**Tech Stack:** ASUS ZenWiFi AX Mini router admin UI

**Scope:** 3 phases from original design (phases 1-3)

**Codebase verified:** 2026-03-20

---

## Acceptance Criteria Coverage

This phase implements and verifies:

### BEAN-23.AC4: DHCP failover — cluster down degrades gracefully
- **BEAN-23.AC4.1 Success:** LAN device resolves `jellyfin.beanlab` using DHCP-assigned DNS (no manual `dig @` needed)
- **BEAN-23.AC4.2 Success:** LAN device resolves `google.com` through CoreDNS upstream forwarding
- **BEAN-23.AC4.3 Failure:** When CoreDNS is stopped (`kubectl scale deployment -n dns coredns-lan --replicas=0`), LAN device still resolves `google.com` via router fallback
- **BEAN-23.AC4.4 Failure:** When CoreDNS is stopped, `jellyfin.beanlab` does NOT resolve (expected — no fallback for local zones)

---

**IMPORTANT: This phase is entirely manual — performed via the router admin UI and verified from a LAN device. No files are committed to git.**

<!-- START_TASK_1 -->
### Task 1: Configure router DHCP DNS settings

**Performed on:** Router admin UI (browser)

**Step 1: Access the router admin panel**

Open a browser and navigate to `http://192.168.50.1` (or your router's admin IP). Log in with your admin credentials.

**Step 2: Navigate to DHCP settings**

Go to: **LAN** > **DHCP Server** tab

**Step 3: Set DNS server addresses**

Find the DNS server fields and set:
- **DNS Server 1:** `192.168.50.101` (wasabi — CoreDNS)
- **DNS Server 2:** `192.168.50.1` (router — fallback)

**Step 4: Apply settings**

Click **Apply** to save the DHCP configuration. Existing clients will pick up the new DNS servers on their next DHCP lease renewal.

**Step 5: Force a DHCP lease renewal on a test device**

On a test LAN device (laptop or phone):

**macOS:**
```bash
sudo ipconfig set en0 DHCP
```

**Linux:**
```bash
sudo dhclient -r && sudo dhclient
```

**Windows:**
```cmd
ipconfig /release && ipconfig /renew
```

**Phone/tablet:** Toggle Wi-Fi off and on, or disconnect and reconnect to the network.
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Verify LAN device uses CoreDNS for local resolution

**Performed on:** A LAN device (laptop/phone) that has renewed its DHCP lease

**Step 1: Verify DNS server assignment**

Check that the device received the correct DNS servers:

**macOS:**
```bash
scutil --dns | head -20
```

**Linux:**
```bash
resolvectl status
```

Expected: DNS server list includes `192.168.50.101` as primary.

**Step 2: Resolve a local .beanlab hostname**

```bash
dig jellyfin.beanlab
```

Or if `dig` is not available:

```bash
nslookup jellyfin.beanlab
```

Expected: Returns `192.168.50.102` — resolved via DHCP-assigned DNS, no `@192.168.50.101` needed.

**Verifies:** BEAN-23.AC4.1

**Step 3: Resolve an internet hostname**

```bash
dig google.com
```

Expected: Returns A records for google.com, resolved through CoreDNS upstream forwarding.

**Verifies:** BEAN-23.AC4.2
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Verify graceful degradation when CoreDNS is down

**Step 1: Scale CoreDNS to zero replicas**

From a machine with kubectl access:

```bash
kubectl scale deployment -n dns coredns-lan --replicas=0
```

Wait for the pod to terminate:

```bash
kubectl get pod -n dns
```

Expected: No pods running in the `dns` namespace.

**Step 2: Test internet DNS from a LAN device**

On the test LAN device:

```bash
dig google.com
```

Expected: Still resolves — the device falls back to DNS Server 2 (router at `192.168.50.1`) for internet resolution.

**Verifies:** BEAN-23.AC4.3

Note: The first query may take a few seconds as the device times out trying the primary DNS server before falling back.

**Step 3: Test local DNS from a LAN device**

```bash
dig jellyfin.beanlab
```

Expected: Does NOT resolve (`SERVFAIL` or `NXDOMAIN` from the router, which doesn't know about `.beanlab`). This is the expected behavior — local zones are only available when CoreDNS is running.

**Verifies:** BEAN-23.AC4.4

**Step 4: Restore CoreDNS**

```bash
kubectl scale deployment -n dns coredns-lan --replicas=1
```

Wait for the pod to start:

```bash
kubectl get pod -n dns -o wide
```

Expected: Pod is Running on wasabi.

**Step 5: Verify local DNS works again**

```bash
dig jellyfin.beanlab
```

Expected: Returns `192.168.50.102` — CoreDNS is back and serving local zones.
<!-- END_TASK_3 -->
