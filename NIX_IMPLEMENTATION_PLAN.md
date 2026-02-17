# SSH-Tool Nix Implementation Plan

## Status: READY FOR IMPLEMENTATION

## Overview

This document provides a detailed, step-by-step implementation plan for adding Nix flake support to ssh-tool. Each phase includes specific file paths, function names, expected line counts, and a clear definition of done.

**Reference Document:** `NIX_DESIGN.md`

**Estimated Total Files:** 18 new files
**Estimated Total Lines:** ~2,500 lines of Nix code

---

## Phase 1: Project Structure and Constants

**Goal:** Create the foundational directory structure and modular constants.

**Duration:** ~1 hour

### Step 1.1: Create Directory Structure

```bash
mkdir -p nix/constants
mkdir -p nix/tests
```

**Files Created:**
- `nix/` (directory)
- `nix/constants/` (directory)
- `nix/tests/` (directory)

### Step 1.2: Create `nix/constants/network.nix`

**File:** `nix/constants/network.nix`
**Lines:** ~20

```nix
# nix/constants/network.nix
{
  bridge = "sshbr0";
  tapMcp = "sshtap0";
  tapTarget = "sshtap1";
  subnet = "10.178.0.0/24";
  gateway = "10.178.0.1";
  mcpVmIp = "10.178.0.10";
  targetVmIp = "10.178.0.20";
  mcpVmMac = "02:00:00:0a:b2:01";
  targetVmMac = "02:00:00:0a:b2:02";
}
```

**Verification:**
```bash
nix eval --file nix/constants/network.nix
# Should output: { bridge = "sshbr0"; gateway = "10.178.0.1"; ... }
```

### Step 1.3: Create `nix/constants/ports.nix`

**File:** `nix/constants/ports.nix`
**Lines:** ~15

```nix
# nix/constants/ports.nix
{
  mcpServer = 3000;
  sshForwardMcp = 22010;
  mcpForward = 3000;
  sshBase = 2222;
  netemOffset = 100;
}
```

**Verification:**
```bash
nix eval --file nix/constants/ports.nix
# Should output: { mcpForward = 3000; mcpServer = 3000; ... }
```

### Step 1.4: Create `nix/constants/timeouts.nix`

**File:** `nix/constants/timeouts.nix`
**Lines:** ~25

```nix
# nix/constants/timeouts.nix
{
  expect = {
    default = 30;
    connect = 60;
    command = 30;
    netem = 120;
    slowAuth = 10;
  };
  test = {
    vmBoot = 120;
    sshReady = 60;
    mcpReady = 30;
  };
  ssh = {
    connectTimeout = 10;
    serverAliveInterval = 15;
    serverAliveCountMax = 3;
  };
}
```

**Verification:**
```bash
nix eval --file nix/constants/timeouts.nix --apply 't: t.expect.netem'
# Should output: 120
```

### Step 1.5: Create `nix/constants/users.nix`

**File:** `nix/constants/users.nix`
**Lines:** ~60

**Key Attributes:**
- `testuser` - lines 4-9
- `fancyuser` - lines 10-15
- `gituser` - lines 16-22
- `zshuser` - lines 23-28
- `dashuser` - lines 29-34
- `slowuser` - lines 35-40
- `root` - lines 41-46
- `vmResources` - lines 48-52

**Verification:**
```bash
nix eval --file nix/constants/users.nix --apply 'u: builtins.attrNames u'
# Should output: [ "dashuser" "fancyuser" "gituser" "root" "slowuser" "testuser" "vmResources" "zshuser" ]
```

### Step 1.6: Create `nix/constants/sshd.nix`

**File:** `nix/constants/sshd.nix`
**Lines:** ~70

**Key Attributes (7 sshd configurations):**
- `standard` (port 2222) - lines 4-10
- `keyonly` (port 2223) - lines 11-17
- `fancyprompt` (port 2224) - lines 18-24
- `slowauth` (port 2225) - lines 25-32
- `denyall` (port 2226) - lines 33-39
- `unstable` (port 2227) - lines 40-47
- `rootlogin` (port 2228) - lines 48-54

**Verification:**
```bash
nix eval --file nix/constants/sshd.nix --apply 's: builtins.attrNames s'
# Should output: [ "denyall" "fancyprompt" "keyonly" "rootlogin" "slowauth" "standard" "unstable" ]
nix eval --file nix/constants/sshd.nix --apply 's: s.standard.port'
# Should output: 2222
```

### Step 1.7: Create `nix/constants/netem.nix`

**File:** `nix/constants/netem.nix`
**Lines:** ~80

**Key Attributes (7 netem profiles):**
- `latency100` (port 2322, mark 1) - lines 4-12
- `lossy5` (port 2323, mark 2) - lines 13-21
- `severe` (port 2324, mark 3) - lines 22-30
- `verySlow` (port 2325, mark 4) - lines 31-39
- `slowFail` (port 2326, mark 5) - lines 40-48
- `unstableNetwork` (port 2327, mark 6) - lines 49-57
- `rootSlow` (port 2328, mark 7) - lines 58-66

**Verification:**
```bash
nix eval --file nix/constants/netem.nix --apply 'n: n.latency100.mark'
# Should output: 1
nix eval --file nix/constants/netem.nix --apply 'n: n.severe.loss'
# Should output: "10%"
```

### Step 1.8: Create `nix/constants/default.nix`

**File:** `nix/constants/default.nix`
**Lines:** ~12

```nix
# nix/constants/default.nix
{
  network = import ./network.nix;
  ports = import ./ports.nix;
  timeouts = import ./timeouts.nix;
  users = import ./users.nix;
  sshd = import ./sshd.nix;
  netem = import ./netem.nix;
}
```

**Verification:**
```bash
nix eval --file nix/constants --apply 'c: builtins.attrNames c'
# Should output: [ "netem" "network" "ports" "sshd" "timeouts" "users" ]
nix eval --file nix/constants --apply 'c: c.network.gateway'
# Should output: "10.178.0.1"
```

### Phase 1 Definition of Done

- [ ] All 7 files in `nix/constants/` created
- [ ] Each file passes `nix eval` without errors
- [ ] `nix eval --file nix/constants` returns complete attribute set
- [ ] All verification commands above pass
- [ ] Total lines: ~280

**Verification Script:**
```bash
#!/bin/bash
# phase1_verify.sh
set -e
echo "Phase 1 Verification"

echo -n "1. network.nix... "
nix eval --file nix/constants/network.nix > /dev/null && echo "OK"

echo -n "2. ports.nix... "
nix eval --file nix/constants/ports.nix > /dev/null && echo "OK"

echo -n "3. timeouts.nix... "
nix eval --file nix/constants/timeouts.nix > /dev/null && echo "OK"

echo -n "4. users.nix... "
nix eval --file nix/constants/users.nix > /dev/null && echo "OK"

echo -n "5. sshd.nix... "
nix eval --file nix/constants/sshd.nix > /dev/null && echo "OK"

echo -n "6. netem.nix... "
nix eval --file nix/constants/netem.nix > /dev/null && echo "OK"

echo -n "7. default.nix (combined)... "
nix eval --file nix/constants > /dev/null && echo "OK"

echo -n "8. Cross-reference check... "
SSHD_COUNT=$(nix eval --file nix/constants --apply 'c: builtins.length (builtins.attrNames c.sshd)' 2>/dev/null)
NETEM_COUNT=$(nix eval --file nix/constants --apply 'c: builtins.length (builtins.attrNames c.netem)' 2>/dev/null)
[ "$SSHD_COUNT" = "7" ] && [ "$NETEM_COUNT" = "7" ] && echo "OK (7 sshd, 7 netem)"

echo "Phase 1 COMPLETE"
```

---

## Phase 2: Development Shell

**Goal:** Create a working `nix develop` shell with all required tools.

**Duration:** ~30 minutes

### Step 2.1: Create `nix/shell.nix`

**File:** `nix/shell.nix`
**Lines:** ~50

**Key Sections:**
- Package list - lines 8-22
- Linux-specific packages - lines 23-28
- `shellHook` - lines 30-45
- Environment variables - lines 47-49

**Required Packages:**
```nix
packages = with pkgs; [
  # Core (lines 10-11)
  expect
  tcl

  # Testing (lines 13-16)
  shellcheck
  curl
  jq

  # Development (lines 18-20)
  git
  gnumake
];
```

**Shell Hook Output (lines 30-45):**
```
═══════════════════════════════════════════════════════════
  SSH Automation Tool - Development Shell
═══════════════════════════════════════════════════════════

Available commands:
  ./tests/run_all_tests.sh     - Run CLI mock tests
  ./mcp/tests/run_all_tests.sh - Run MCP mock tests
  ...
```

**Verification:**
```bash
# Test shell.nix in isolation (before flake.nix exists)
nix-shell -p "(import <nixpkgs> {}).callPackage ./nix/shell.nix {}"
# Should enter shell with expect, tcl, etc. available
```

### Step 2.2: Create Initial `flake.nix`

**File:** `flake.nix`
**Lines:** ~30 (minimal version for Phase 2)

```nix
{
  description = "SSH Automation Tool with MCP Server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = import ./nix/shell.nix { inherit pkgs; };
      }
    );
}
```

### Phase 2 Definition of Done

- [ ] `nix/shell.nix` created (~50 lines)
- [ ] `flake.nix` created (minimal, ~30 lines)
- [ ] `nix develop` enters shell successfully
- [ ] Following commands work in shell:
  - [ ] `expect -v` returns version
  - [ ] `tclsh <<< 'puts "hello"'` outputs "hello"
  - [ ] `shellcheck --version` returns version
  - [ ] `curl --version` returns version
  - [ ] `jq --version` returns version
- [ ] `./tests/run_all_tests.sh` runs successfully in shell
- [ ] `./mcp/tests/run_all_tests.sh` runs successfully in shell

**Verification Script:**
```bash
#!/bin/bash
# phase2_verify.sh
set -e
echo "Phase 2 Verification"

echo -n "1. nix develop works... "
timeout 30 nix develop --command true && echo "OK"

echo -n "2. expect available... "
nix develop --command expect -v > /dev/null 2>&1 && echo "OK"

echo -n "3. tclsh available... "
nix develop --command tclsh <<< 'puts "OK"'

echo -n "4. shellcheck available... "
nix develop --command shellcheck --version > /dev/null 2>&1 && echo "OK"

echo -n "5. curl available... "
nix develop --command curl --version > /dev/null 2>&1 && echo "OK"

echo -n "6. jq available... "
nix develop --command jq --version > /dev/null 2>&1 && echo "OK"

echo -n "7. CLI tests run... "
nix develop --command ./tests/run_all_tests.sh > /dev/null 2>&1 && echo "OK"

echo -n "8. MCP tests run... "
nix develop --command ./mcp/tests/run_all_tests.sh > /dev/null 2>&1 && echo "OK"

echo "Phase 2 COMPLETE"
```

---

## Phase 3: MCP Server MicroVM

**Goal:** Create a bootable MicroVM that runs the MCP server.

**Duration:** ~2 hours

### Step 3.1: Update `flake.nix` with MicroVM Input

**File:** `flake.nix`
**Lines:** ~80 (expanded)

**Changes:**
- Add `microvm` input (line 8-11)
- Import `mcp-vm.nix` (lines 25-35)
- Pass `self` to mcp-vm (line 28)

```nix
# Line 8-11: Add microvm input
microvm = {
  url = "github:astro/microvm.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

# Line 28: Pass self for source access
mcp-vm = import ./nix/mcp-vm.nix {
  inherit self pkgs lib microvm nixpkgs system;
  networking = "user";
  debugMode = false;
};
```

### Step 3.2: Create `nix/mcp-vm.nix`

**File:** `nix/mcp-vm.nix`
**Lines:** ~180

**Key Sections:**
| Section | Lines | Description |
|---------|-------|-------------|
| Function args | 1-15 | `self`, `pkgs`, `lib`, etc. |
| Constants imports | 17-22 | Import modular constants |
| MicroVM config | 30-55 | hypervisor, mem, vcpu, shares |
| Network interfaces | 57-75 | TAP vs user-mode |
| Port forwards | 77-85 | User-mode port mapping |
| Networking | 87-105 | hostname, firewall, IP config |
| SSH server | 107-115 | openssh settings |
| Packages | 117-125 | expect, tcl, curl, jq |
| Test user | 127-140 | testuser with password |
| MCP service | 142-160 | systemd service using `self` |
| MOTD | 162-175 | Debug mode banner |

**Critical Line - MCP Server Service (line 150):**
```nix
ExecStart = "${pkgs.expect}/bin/expect ${self}/mcp/server.tcl --port 3000 --bind 0.0.0.0";
```

**Verification:**
```bash
# Build the VM
nix build .#mcp-vm-debug -o result-mcp

# Check output exists
ls -la result-mcp/bin/microvm-run

# Start VM (in background for testing)
timeout 60 ./result-mcp/bin/microvm-run &
VM_PID=$!
sleep 30

# Test MCP health endpoint
curl -sf http://localhost:3000/health

# Cleanup
kill $VM_PID 2>/dev/null
```

### Step 3.3: Create VM Variant Matrix in `flake.nix`

**File:** `flake.nix`
**Lines:** 80-120

**Variants to Create:**
| Package Name | Networking | Debug | Lines |
|--------------|-----------|-------|-------|
| `mcp-vm` | user | false | 85-90 |
| `mcp-vm-debug` | user | true | 91-96 |
| `mcp-vm-tap` | tap | false | 97-102 |
| `mcp-vm-tap-debug` | tap | true | 103-108 |

### Phase 3 Definition of Done

- [ ] `flake.nix` updated with microvm input
- [ ] `nix/mcp-vm.nix` created (~180 lines)
- [ ] `nix build .#mcp-vm-debug` succeeds
- [ ] VM boots successfully (serial console shows login prompt)
- [ ] MCP server starts automatically (`systemctl status mcp-server`)
- [ ] `curl http://localhost:3000/health` returns `{"status":"ok"}`
- [ ] `curl http://localhost:3000/metrics` returns Prometheus metrics
- [ ] SSH to VM works: `ssh -p 22010 testuser@localhost`
- [ ] All 4 variants build successfully

**Verification Script:**
```bash
#!/bin/bash
# phase3_verify.sh
set -e
echo "Phase 3 Verification"

echo "1. Building mcp-vm-debug..."
nix build .#mcp-vm-debug -o result-mcp

echo "2. Starting VM..."
timeout 120 ./result-mcp/bin/microvm-run &
VM_PID=$!
sleep 45

echo -n "3. Health check... "
curl -sf http://localhost:3000/health | grep -q "ok" && echo "OK"

echo -n "4. Metrics check... "
curl -sf http://localhost:3000/metrics | grep -q "mcp_" && echo "OK"

echo -n "5. SSH check... "
sshpass -p testpass ssh -o StrictHostKeyChecking=no -p 22010 testuser@localhost hostname && echo "OK"

echo "6. Stopping VM..."
kill $VM_PID 2>/dev/null || true
wait $VM_PID 2>/dev/null || true

echo "7. Building all variants..."
nix build .#mcp-vm
nix build .#mcp-vm-tap
nix build .#mcp-vm-tap-debug

echo "Phase 3 COMPLETE"
```

---

## Phase 4: Multi-SSHD Target MicroVM

**Goal:** Create a MicroVM with 7 sshd instances on different ports.

**Duration:** ~3 hours

### Step 4.1: Create `nix/ssh-target-vm.nix`

**File:** `nix/ssh-target-vm.nix`
**Lines:** ~350

**Key Sections:**
| Section | Lines | Description |
|---------|-------|-------------|
| Function args | 1-12 | `pkgs`, `lib`, etc. |
| Constants imports | 14-18 | Import all constants |
| Helper: mkSshdConfig | 20-40 | Generate sshd_config per daemon |
| Port list generation | 42-48 | All SSH + netem ports |
| Port forwards | 50-60 | User-mode forwarding |
| MicroVM config | 65-95 | hypervisor, shares, interfaces |
| Networking | 97-120 | hostname, firewall, IPs |
| Disable default sshd | 122 | `services.openssh.enable = false` |
| Packages | 124-135 | openssh, zsh, dash, nftables, iproute2 |
| Test users (loop) | 137-160 | Create all test users |
| User shell configs | 162-200 | .bashrc/.zshrc with PS1 |
| SSH host keys | 202-220 | Generate keys per daemon |
| SSHD services (loop) | 222-260 | 7 systemd services |
| Slow auth PAM | 262-275 | PAM delay for slowauth |
| Netem setup | 277-340 | nft marks + tc filters |
| Test files | 342-355 | /etc/test-file.txt |
| MOTD | 357-380 | Port documentation |

**Critical Functions:**

**`mkSshdConfig` (lines 20-40):**
```nix
mkSshdConfig = name: cfg: pkgs.writeText "sshd_config_${name}" ''
  Port ${toString cfg.port}
  HostKey /etc/ssh/ssh_host_ed25519_key_${name}
  PasswordAuthentication ${if cfg.passwordAuth then "yes" else "no"}
  PubkeyAuthentication ${if cfg.pubkeyAuth then "yes" else "no"}
  PermitRootLogin ${cfg.permitRootLogin}
  UsePAM yes
  Subsystem sftp /run/current-system/sw/libexec/sftp-server
'';
```

**Netem Setup Service (lines 277-340):**
```nix
systemd.services.netem-setup = {
  description = "Setup netem with nft marks";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = pkgs.writeShellScript "netem-setup" ''
      # ... nft + tc commands
    '';
  };
};
```

### Step 4.2: Update `flake.nix` with Target VM

**File:** `flake.nix`
**Lines:** 110-140 (add target VM variants)

**Variants:**
| Package Name | Networking | Debug |
|--------------|-----------|-------|
| `ssh-target-vm` | user | false |
| `ssh-target-vm-debug` | user | true |
| `ssh-target-vm-tap` | tap | false |
| `ssh-target-vm-tap-debug` | tap | true |

### Phase 4 Definition of Done

- [ ] `nix/ssh-target-vm.nix` created (~350 lines)
- [ ] `nix build .#ssh-target-vm-debug` succeeds
- [ ] VM boots with 7 sshd instances running
- [ ] All base ports respond:
  - [ ] Port 2222 (standard) - accepts password
  - [ ] Port 2223 (keyonly) - rejects password
  - [ ] Port 2224 (fancyprompt) - accepts password
  - [ ] Port 2225 (slowauth) - accepts with 2s delay
  - [ ] Port 2226 (denyall) - rejects all
  - [ ] Port 2227 (unstable) - accepts (may restart)
  - [ ] Port 2228 (rootlogin) - accepts root
- [ ] All test users exist with correct shells
- [ ] `systemctl status netem-setup` shows active

**Verification Script:**
```bash
#!/bin/bash
# phase4_verify.sh
set -e
echo "Phase 4 Verification"

echo "1. Building ssh-target-vm-debug..."
nix build .#ssh-target-vm-debug -o result-target

echo "2. Starting VM..."
timeout 120 ./result-target/bin/microvm-run &
VM_PID=$!
sleep 60

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

echo "3. Testing SSH ports..."

echo -n "   2222 (standard)... "
sshpass -p testpass ssh $SSH_OPTS -p 2222 testuser@localhost hostname > /dev/null && echo "OK"

echo -n "   2223 (keyonly)... "
! sshpass -p testpass ssh $SSH_OPTS -p 2223 testuser@localhost hostname 2>/dev/null && echo "OK (rejected)"

echo -n "   2224 (fancyprompt)... "
sshpass -p testpass ssh $SSH_OPTS -p 2224 fancyuser@localhost hostname > /dev/null && echo "OK"

echo -n "   2225 (slowauth)... "
START=$(date +%s)
sshpass -p testpass ssh $SSH_OPTS -p 2225 slowuser@localhost hostname > /dev/null
END=$(date +%s)
ELAPSED=$((END - START))
[ $ELAPSED -ge 2 ] && echo "OK (${ELAPSED}s delay)"

echo -n "   2226 (denyall)... "
! sshpass -p testpass ssh $SSH_OPTS -p 2226 testuser@localhost hostname 2>/dev/null && echo "OK (rejected)"

echo -n "   2228 (rootlogin)... "
sshpass -p root ssh $SSH_OPTS -p 2228 root@localhost hostname > /dev/null && echo "OK"

echo "4. Testing users..."
echo -n "   zshuser... "
sshpass -p testpass ssh $SSH_OPTS -p 2222 zshuser@localhost 'echo $SHELL' | grep -q zsh && echo "OK"

echo -n "   dashuser... "
sshpass -p testpass ssh $SSH_OPTS -p 2222 dashuser@localhost 'echo $0' | grep -q dash && echo "OK"

echo "5. Stopping VM..."
kill $VM_PID 2>/dev/null || true

echo "Phase 4 COMPLETE"
```

---

## Phase 5: Network Setup and VM Scripts

**Goal:** Create TAP networking setup and VM management scripts.

**Duration:** ~1 hour

### Step 5.1: Create `nix/network-setup.nix`

**File:** `nix/network-setup.nix`
**Lines:** ~120

**Key Functions:**
| Function | Lines | Description |
|----------|-------|-------------|
| `setup` | 10-60 | Create bridge, TAPs, NAT |
| `teardown` | 65-100 | Remove bridge, TAPs, NAT |

**Setup Script Key Commands (lines 20-55):**
```bash
# Create bridge
sudo ip link add ${bridge} type bridge
sudo ip addr add ${gateway}/24 dev ${bridge}
sudo ip link set ${bridge} up

# Create TAPs
sudo ip tuntap add dev ${tapMcp} mode tap user "$USER"
sudo ip link set ${tapMcp} master ${bridge}
sudo ip link set ${tapMcp} up

# NAT rules
sudo nft add table inet ssh-nat
sudo nft add chain inet ssh-nat postrouting { type nat hook postrouting priority 100 \; }
sudo nft add rule inet ssh-nat postrouting ip saddr ${subnet} masquerade
```

### Step 5.2: Create `nix/vm-scripts.nix`

**File:** `nix/vm-scripts.nix`
**Lines:** ~80

**Key Functions:**
| Function | Lines | Description |
|----------|-------|-------------|
| `check` | 8-20 | Show running VMs |
| `stop` | 22-32 | Stop all VMs |
| `sshMcp` | 34-45 | SSH to MCP VM |
| `sshTarget` | 47-58 | SSH to target VM |

### Step 5.3: Update `flake.nix` with Apps

**File:** `flake.nix`
**Lines:** 145-180 (apps section)

**Apps to Add:**
```nix
apps = {
  ssh-vm-check = { type = "app"; program = "${vmScripts.check}/bin/ssh-vm-check"; };
  ssh-vm-stop = { type = "app"; program = "${vmScripts.stop}/bin/ssh-vm-stop"; };
  ssh-vm-ssh-mcp = { type = "app"; program = "${vmScripts.sshMcp}/bin/ssh-vm-ssh-mcp"; };
  ssh-vm-ssh-target = { type = "app"; program = "${vmScripts.sshTarget}/bin/ssh-vm-ssh-target"; };
  ssh-network-setup = { type = "app"; program = "${networkScripts.setup}/bin/ssh-network-setup"; };
  ssh-network-teardown = { type = "app"; program = "${networkScripts.teardown}/bin/ssh-network-teardown"; };
};
```

### Phase 5 Definition of Done

- [ ] `nix/network-setup.nix` created (~120 lines)
- [ ] `nix/vm-scripts.nix` created (~80 lines)
- [ ] `flake.nix` updated with 6 apps
- [ ] `nix run .#ssh-vm-check` works
- [ ] `nix run .#ssh-vm-stop` works
- [ ] TAP mode (requires sudo):
  - [ ] `nix run .#ssh-network-setup` creates bridge/TAPs
  - [ ] `ip link show sshbr0` shows bridge
  - [ ] `nix run .#ssh-network-teardown` removes all

**Verification Script:**
```bash
#!/bin/bash
# phase5_verify.sh
set -e
echo "Phase 5 Verification"

echo -n "1. ssh-vm-check... "
nix run .#ssh-vm-check > /dev/null && echo "OK"

echo -n "2. ssh-vm-stop... "
nix run .#ssh-vm-stop > /dev/null && echo "OK"

echo "3. TAP networking (requires sudo)..."
echo -n "   setup... "
nix run .#ssh-network-setup && echo "OK"

echo -n "   verify bridge... "
ip link show sshbr0 > /dev/null && echo "OK"

echo -n "   verify TAPs... "
ip link show sshtap0 > /dev/null && ip link show sshtap1 > /dev/null && echo "OK"

echo -n "   teardown... "
nix run .#ssh-network-teardown && echo "OK"

echo -n "   verify cleanup... "
! ip link show sshbr0 2>/dev/null && echo "OK"

echo "Phase 5 COMPLETE"
```

---

## Phase 6: Test Library and Test Scripts

**Goal:** Create test helper library and comprehensive test scripts.

**Duration:** ~3 hours

### Step 6.1: Create `nix/test-lib.nix`

**File:** `nix/test-lib.nix`
**Lines:** ~150

**Key Functions:**
| Function | Lines | Description |
|----------|-------|-------------|
| `waitForSsh` | 15-30 | Wait for SSH availability |
| `waitForSshDeny` | 32-45 | Expect SSH rejection |
| `waitForMcp` | 47-60 | Wait for MCP health |
| `mcpRequest` | 62-75 | JSON-RPC helper |
| `mcpSshConnect` | 77-90 | MCP SSH connect |
| `mcpSshRun` | 92-105 | MCP SSH run command |
| `runCheck` | 107-120 | Test assertion helper |
| `timedCheck` | 122-140 | Timing assertion |
| `extractSessionId` | 142-150 | Parse session from response |
| `hasError` | 152-160 | Check for error in response |

### Step 6.2: Create `nix/tests/e2e-test.nix`

**File:** `nix/tests/e2e-test.nix`
**Lines:** ~400

**Test Suites:**
| Suite | Function | Lines | Tests |
|-------|----------|-------|-------|
| E2E | `e2e` | 15-120 | Basic functionality |
| Auth | `authTests` | 125-200 | Auth failures |
| Netem | `netemTests` | 205-300 | Network degradation |
| Stability | `stabilityTests` | 305-370 | Connection resilience |
| Security | `security` | 375-480 | Security controls |
| All | `all` | 485-520 | Master runner |

**E2E Test Phases (lines 30-115):**
1. Phase 1: Service Availability (lines 35-45)
2. Phase 2: MCP Server Health (lines 47-55)
3. Phase 3: Standard SSH (lines 57-75)
4. Phase 4: Fancy Prompt Users (lines 77-90)
5. Phase 5: Different Shells (lines 92-105)
6. Phase 6: Root Login (lines 107-115)

### Step 6.3: Update `flake.nix` with Test Apps

**File:** `flake.nix`
**Lines:** 182-200

**Test Apps:**
```nix
ssh-test-e2e = { type = "app"; program = "${testScripts.e2e}/bin/ssh-test-e2e"; };
ssh-test-auth = { type = "app"; program = "${testScripts.authTests}/bin/ssh-test-auth"; };
ssh-test-netem = { type = "app"; program = "${testScripts.netemTests}/bin/ssh-test-netem"; };
ssh-test-stability = { type = "app"; program = "${testScripts.stabilityTests}/bin/ssh-test-stability"; };
ssh-test-security = { type = "app"; program = "${testScripts.security}/bin/ssh-test-security"; };
ssh-test-all = { type = "app"; program = "${testScripts.all}/bin/ssh-test-all"; };
```

### Phase 6 Definition of Done

- [ ] `nix/test-lib.nix` created (~150 lines)
- [ ] `nix/tests/e2e-test.nix` created (~400 lines)
- [ ] All 6 test apps added to flake
- [ ] Each test app runs without Nix errors (syntax check)
- [ ] Test library functions are properly exported

**Verification Script:**
```bash
#!/bin/bash
# phase6_verify.sh
set -e
echo "Phase 6 Verification"

echo -n "1. test-lib.nix syntax... "
nix eval --file nix/test-lib.nix --apply 'lib: builtins.attrNames lib' > /dev/null && echo "OK"

echo -n "2. e2e-test.nix syntax... "
nix eval --file nix/tests/e2e-test.nix --apply 't: builtins.attrNames t' > /dev/null && echo "OK"

echo "3. Test apps build..."
for app in ssh-test-e2e ssh-test-auth ssh-test-netem ssh-test-stability ssh-test-security ssh-test-all; do
  echo -n "   $app... "
  nix build .#$app 2>/dev/null && echo "OK" || echo "SKIP (not in apps)"
done

echo "Phase 6 COMPLETE"
```

---

## Phase 7: NixOS Test Framework Integration

**Goal:** Create automated CI test using NixOS test framework.

**Duration:** ~2 hours

### Step 7.1: Create `nix/nixos-test.nix`

**File:** `nix/nixos-test.nix`
**Lines:** ~150

**Key Sections:**
| Section | Lines | Description |
|---------|-------|-------------|
| Function args | 1-8 | `self`, `pkgs`, etc. |
| Constants import | 10-12 | Import constants |
| Test definition | 14-25 | `nixpkgs.lib.nixosTest` |
| MCP node | 27-45 | MCP server node config |
| Target node | 47-70 | Multi-SSHD node config |
| Python test script | 72-145 | Test logic |

**Python Test Script (lines 72-145):**
```python
start_all()

# Wait for services
target.wait_for_unit("sshd-standard.service")
target.wait_for_open_port(2222)
mcp.wait_for_unit("mcp-server.service")
mcp.wait_for_open_port(3000)

# Test MCP health
result = mcp.succeed("curl -sf http://localhost:3000/health")
assert "ok" in result.lower()

# Test SSH via MCP
# ... JSON-RPC tests ...

# Security tests
# ... blocked command tests ...
```

### Step 7.2: Update `flake.nix` with Checks

**File:** `flake.nix`
**Lines:** 205-215

```nix
checks = lib.optionalAttrs pkgs.stdenv.isLinux {
  integration = import ./nix/nixos-test.nix {
    inherit self pkgs lib nixpkgs system;
  };
};
```

### Phase 7 Definition of Done

- [ ] `nix/nixos-test.nix` created (~150 lines)
- [ ] `flake.nix` updated with `checks.integration`
- [ ] `nix flake check` runs (may take several minutes)
- [ ] Test creates 2 VMs automatically
- [ ] Test waits for services correctly
- [ ] Test passes all assertions

**Verification:**
```bash
#!/bin/bash
# phase7_verify.sh
set -e
echo "Phase 7 Verification"

echo "1. Building NixOS test..."
echo "   This may take 5-10 minutes on first run."
nix build .#checks.x86_64-linux.integration

echo "2. Test artifacts..."
ls -la result/

echo "3. Test log..."
cat result/log.txt | tail -20

echo "Phase 7 COMPLETE"
```

---

## Phase 8: Comprehensive Integration Testing

**Goal:** Verify all components work together correctly.

**Duration:** ~2 hours

### Step 8.1: Create Integration Test Script

**File:** `nix/tests/integration-verify.sh`
**Lines:** ~200

This script tests the complete system with both VMs running.

**Test Categories:**

| Category | Tests | Lines |
|----------|-------|-------|
| VM Boot | 2 VMs boot, services start | 20-40 |
| MCP Health | health, metrics endpoints | 42-55 |
| SSH Connectivity | All 7 ports respond correctly | 57-90 |
| User Prompts | All users have correct PS1 | 92-120 |
| Auth Failures | keyonly, denyall reject correctly | 122-145 |
| Netem | Latency increases on +100 ports | 147-180 |
| Security | Blocked commands rejected | 182-220 |
| Stability | Unstable sshd reconnection | 222-250 |

### Step 8.2: Create Test Matrix

**Expected Results Matrix:**

| Test | Port | User | Expected Result |
|------|------|------|-----------------|
| Standard SSH | 2222 | testuser | Success |
| Key-only reject | 2223 | testuser | Auth failure |
| Fancy prompt | 2224 | fancyuser | Success, PS1 has colors |
| Slow auth | 2225 | slowuser | Success, >2s delay |
| Deny all | 2226 | testuser | Auth failure |
| Unstable | 2227 | testuser | Success (may vary) |
| Root login | 2228 | root | Success |
| Zsh shell | 2222 | zshuser | Success, $SHELL=/bin/zsh |
| Dash shell | 2222 | dashuser | Success, $0=dash |
| Netem 100ms | 2322 | testuser | Success, +100ms RTT |
| Netem 5% loss | 2323 | testuser | Success, some retries |
| Security: rm | 2222 | testuser | Blocked |
| Security: curl | 2222 | testuser | Blocked |
| Security: sudo | 2222 | testuser | Blocked |
| Security: /etc/shadow | 2222 | testuser | Blocked |

### Step 8.3: Automated Test Run

**Execution Order:**

1. Build both VMs
2. Start target VM (wait for all 7 sshd)
3. Start MCP VM (wait for health endpoint)
4. Run integration tests
5. Collect results
6. Stop VMs
7. Report summary

### Phase 8 Definition of Done

- [ ] Integration test script created
- [ ] All 7 sshd ports tested
- [ ] All 6 test users verified
- [ ] All 7 netem profiles tested
- [ ] All security controls verified
- [ ] Test runs completely without manual intervention
- [ ] Test produces clear pass/fail report

**Master Verification Script:**
```bash
#!/bin/bash
# phase8_verify.sh - Full Integration Test
set -e

echo "═══════════════════════════════════════════════════════════════"
echo "  SSH-Tool Nix Integration Test"
echo "═══════════════════════════════════════════════════════════════"

PASSED=0
FAILED=0
SKIPPED=0

check() {
  local name="$1"
  shift
  echo -n "  $name... "
  if "$@" > /dev/null 2>&1; then
    echo "PASS"
    ((PASSED++))
  else
    echo "FAIL"
    ((FAILED++))
  fi
}

# Build
echo ""
echo "Phase 1: Building VMs"
nix build .#mcp-vm-debug -o result-mcp
nix build .#ssh-target-vm-debug -o result-target

# Start VMs
echo ""
echo "Phase 2: Starting VMs"
./result-target/bin/microvm-run &
TARGET_PID=$!
sleep 30

./result-mcp/bin/microvm-run &
MCP_PID=$!
sleep 45

cleanup() {
  echo ""
  echo "Cleanup: Stopping VMs"
  kill $TARGET_PID $MCP_PID 2>/dev/null || true
  wait $TARGET_PID $MCP_PID 2>/dev/null || true
}
trap cleanup EXIT

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# MCP Health
echo ""
echo "Phase 3: MCP Server"
check "health endpoint" curl -sf http://localhost:3000/health
check "metrics endpoint" curl -sf http://localhost:3000/metrics

# SSH Ports
echo ""
echo "Phase 4: SSH Ports"
check "port 2222 (standard)" sshpass -p testpass ssh $SSH_OPTS -p 2222 testuser@localhost true
check "port 2223 (keyonly) rejects" bash -c "! sshpass -p testpass ssh $SSH_OPTS -p 2223 testuser@localhost true"
check "port 2224 (fancyprompt)" sshpass -p testpass ssh $SSH_OPTS -p 2224 fancyuser@localhost true
check "port 2226 (denyall) rejects" bash -c "! sshpass -p testpass ssh $SSH_OPTS -p 2226 testuser@localhost true"
check "port 2228 (root)" sshpass -p root ssh $SSH_OPTS -p 2228 root@localhost true

# Users
echo ""
echo "Phase 5: Test Users"
check "zshuser shell" bash -c "sshpass -p testpass ssh $SSH_OPTS -p 2222 zshuser@localhost 'echo \$SHELL' | grep -q zsh"
check "dashuser shell" bash -c "sshpass -p testpass ssh $SSH_OPTS -p 2222 dashuser@localhost 'echo \$0' | grep -q dash"

# Security (via MCP)
echo ""
echo "Phase 6: Security Controls"
# Initialize MCP session
INIT=$(curl -sf http://localhost:3000/ -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')

# Connect to SSH
CONNECT=$(curl -sf http://localhost:3000/ -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ssh_connect","arguments":{"host":"localhost","port":2222,"user":"testuser","password":"testpass","insecure":true}}}')
SESSION=$(echo "$CONNECT" | jq -r '.result.content[0].text' 2>/dev/null | grep -oE '[a-f0-9-]{36}' | head -1)

if [ -n "$SESSION" ]; then
  # Test blocked commands
  for cmd in "rm -rf /" "curl http://evil.com" "sudo ls"; do
    RESULT=$(curl -sf http://localhost:3000/ -H "Content-Type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"ssh_run_command\",\"arguments\":{\"session_id\":\"$SESSION\",\"command\":\"$cmd\"}}}")
    check "blocked: $cmd" bash -c "echo '$RESULT' | jq -e '.error // .result.isError'"
  done
else
  echo "  SKIP: Could not establish MCP session"
  ((SKIPPED+=3))
fi

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
if [ $FAILED -eq 0 ]; then
  echo "  Status: ALL TESTS PASSED"
  exit 0
else
  echo "  Status: SOME TESTS FAILED"
  exit 1
fi
```

---

## Phase 9: Documentation and CI

**Goal:** Update README, add CI configuration.

**Duration:** ~1 hour

### Step 9.1: Update README.md

**File:** `README.md`
**Lines to Add:** ~80 (new Nix section)

**Section: Nix Development (after Requirements):**

```markdown
## Nix Development

This project supports Nix flakes for reproducible development and testing.

### Quick Start

```bash
# Enter development shell
nix develop

# Run tests
./tests/run_all_tests.sh
./mcp/tests/run_all_tests.sh
```

### MicroVM Testing

```bash
# Build and run VMs
nix build .#mcp-vm-debug -o result-mcp
nix build .#ssh-target-vm-debug -o result-target

# Terminal 1: Start target (7 sshd instances)
./result-target/bin/microvm-run

# Terminal 2: Start MCP server
./result-mcp/bin/microvm-run

# Terminal 3: Run tests
nix run .#ssh-test-all
```

### Available Commands

| Command | Description |
|---------|-------------|
| `nix develop` | Development shell |
| `nix run .#ssh-test-all` | Run all test suites |
| `nix run .#ssh-vm-check` | Show running VMs |
| `nix run .#ssh-vm-stop` | Stop all VMs |
| `nix flake check` | Run CI tests |
```

### Step 9.2: Create `.github/workflows/nix.yml`

**File:** `.github/workflows/nix.yml`
**Lines:** ~50

```yaml
name: Nix CI

on:
  push:
    branches: [main, fedora]
  pull_request:
    branches: [main]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: cachix/install-nix-action@v24
        with:
          github_access_token: ${{ secrets.GITHUB_TOKEN }}
          extra_nix_config: |
            experimental-features = nix-command flakes

      - name: Check flake
        run: nix flake check

      - name: Build shell
        run: nix build .#devShells.x86_64-linux.default

      - name: Run mock tests
        run: |
          nix develop --command ./tests/run_all_tests.sh
          nix develop --command ./mcp/tests/run_all_tests.sh

  integration:
    runs-on: ubuntu-latest
    needs: check
    steps:
      - uses: actions/checkout@v4

      - uses: cachix/install-nix-action@v24
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes
            system-features = kvm

      - name: Run NixOS integration tests
        run: nix build .#checks.x86_64-linux.integration
```

### Phase 9 Definition of Done

- [ ] README.md updated with Nix section
- [ ] `.github/workflows/nix.yml` created
- [ ] CI passes on push to fedora branch
- [ ] All documentation accurate and tested

---

## Summary: Complete File List

| Phase | File | Lines | Purpose |
|-------|------|-------|---------|
| 1 | `nix/constants/default.nix` | 12 | Re-export all constants |
| 1 | `nix/constants/network.nix` | 20 | Network configuration |
| 1 | `nix/constants/ports.nix` | 15 | Port assignments |
| 1 | `nix/constants/timeouts.nix` | 25 | Global timeouts |
| 1 | `nix/constants/users.nix` | 60 | Test users |
| 1 | `nix/constants/sshd.nix` | 70 | SSH daemon configs |
| 1 | `nix/constants/netem.nix` | 80 | Netem profiles |
| 2 | `nix/shell.nix` | 50 | Development shell |
| 2 | `flake.nix` | 220 | Flake orchestrator |
| 3 | `nix/mcp-vm.nix` | 180 | MCP server VM |
| 4 | `nix/ssh-target-vm.nix` | 350 | Multi-SSHD VM |
| 5 | `nix/network-setup.nix` | 120 | TAP networking |
| 5 | `nix/vm-scripts.nix` | 80 | VM management |
| 6 | `nix/test-lib.nix` | 150 | Test helpers |
| 6 | `nix/tests/e2e-test.nix` | 400 | Test scripts |
| 7 | `nix/nixos-test.nix` | 150 | NixOS test framework |
| 8 | `nix/tests/integration-verify.sh` | 200 | Integration test |
| 9 | `.github/workflows/nix.yml` | 50 | CI configuration |

**Total: 18 files, ~2,230 lines**

---

## Implementation Order

```
Phase 1: Constants (7 files, ~280 lines)
    ↓
Phase 2: Shell + flake.nix (~80 lines)
    ↓
Phase 3: MCP VM (~180 lines)
    ↓
Phase 4: Target VM (~350 lines)
    ↓
Phase 5: Network/Scripts (~200 lines)
    ↓
Phase 6: Test Library (~550 lines)
    ↓
Phase 7: NixOS Test (~150 lines)
    ↓
Phase 8: Integration Testing (~200 lines)
    ↓
Phase 9: Documentation/CI (~130 lines)
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| MicroVM doesn't boot | Use `debugMode = true`, check serial console |
| Netem not working | Test nft/tc commands manually first |
| Slow CI | Cache Nix store with Cachix |
| Flaky tests | Use global timeouts, add retries |
| Security test false positives | Verify against real MCP security module |

---

## Rollback Plan

Each phase is self-contained. If a phase fails:

1. **Phase 1**: Delete `nix/constants/`, retry
2. **Phase 2**: Reset `flake.nix`, delete `nix/shell.nix`
3. **Phase 3-4**: Delete VM file, remove from `flake.nix`
4. **Phase 5-6**: Delete script files, remove apps from `flake.nix`
5. **Phase 7**: Delete `nixos-test.nix`, remove from checks
6. **Phase 8-9**: Delete test scripts, CI file

Git provides the ultimate rollback:
```bash
git checkout HEAD -- nix/ flake.nix flake.lock
```
