# SSH-Tool Nix Implementation Log

## Progress Tracker

| Phase | Name | Status | Started | Completed |
|-------|------|--------|---------|-----------|
| 1 | Project Structure and Constants | **COMPLETE** | 2026-02-09 | 2026-02-09 |
| 2 | Development Shell | **COMPLETE** | 2026-02-09 | 2026-02-09 |
| 3 | MCP Server MicroVM | **COMPLETE** | 2026-02-09 | 2026-02-09 |
| 4 | Multi-SSHD Target MicroVM | **COMPLETE** | 2026-02-09 | 2026-02-09 |
| 5 | Network Setup and VM Scripts | **COMPLETE** | 2026-02-09 | 2026-02-09 |
| 6 | Test Library and Test Scripts | **COMPLETE** | 2026-02-09 | 2026-02-09 |
| 7 | NixOS Test Framework Integration | **COMPLETE** | 2026-02-09 | 2026-02-09 |
| 8 | Comprehensive Integration Testing | **COMPLETE** | 2026-02-10 | 2026-02-10 |
| 9 | Documentation and CI | PENDING | - | - |

---

## Phase 1: Project Structure and Constants

### 2026-02-09

**Status: COMPLETE**

**Step 1.1: Create Directory Structure**
- Status: DONE
- Created: `nix/`, `nix/constants/`, `nix/tests/`

**Step 1.2: Create `nix/constants/network.nix`**
- Status: DONE
- Lines: 24

**Step 1.3: Create `nix/constants/ports.nix`**
- Status: DONE
- Lines: 19

**Step 1.4: Create `nix/constants/timeouts.nix`**
- Status: DONE
- Lines: 28

**Step 1.5: Create `nix/constants/users.nix`**
- Status: DONE
- Lines: 70

**Step 1.6: Create `nix/constants/sshd.nix`**
- Status: DONE
- Lines: 68

**Step 1.7: Create `nix/constants/netem.nix`**
- Status: DONE
- Lines: 80

**Step 1.8: Create `nix/constants/default.nix`**
- Status: DONE
- Lines: 12

**Verification Results:**
```
SSHD count: 7 ✓
Netem count: 7 ✓
Users count: 8 ✓
network.gateway: "10.178.0.1" ✓
ports.sshBase: 2222 ✓
sshd.standard.port: 2222 ✓
netem.latency100.mark: 1 ✓
```

**Total Lines: 301**

---

## Phase 2: Development Shell

### 2026-02-09

**Status: COMPLETE**

**Step 2.1: Create `nix/shell.nix`**
- Status: DONE
- Lines: ~50
- Includes: expect, tcl, curl, jq, sshpass, shellcheck, openssh

**Step 2.2: Create initial `flake.nix`**
- Status: DONE
- Lines: ~107
- Includes: dev shell, MicroVM packages, apps, checks

**Verification:**
- `nix develop` works with all tools available
- All 355 MCP tests + CLI tests pass in nix shell

---

## Phase 3: MCP Server MicroVM

### 2026-02-09

**Status: COMPLETE**

**File:** `nix/mcp-vm.nix`
- Lines: ~147
- Uses `self` for reproducible source access
- MCP server runs on port 3000
- Supports user and TAP networking modes
- Debug mode enables password auth

**Features:**
- QEMU hypervisor with 9p store mount
- Port forwarding: 3000 (MCP), 22 (SSH)
- Testuser with sudo access
- MCP server systemd service

---

## Phase 4: Multi-SSHD Target MicroVM

### 2026-02-09

**Status: COMPLETE**

**File:** `nix/ssh-target-vm.nix`
- Lines: ~344

**SSHD Instances (7 total):**
- Port 2222: standard (password auth)
- Port 2223: keyonly (pubkey only)
- Port 2224: fancyprompt (complex prompts)
- Port 2225: slowauth (2s delay)
- Port 2226: denyall (auth always fails)
- Port 2227: unstable (restarts every 5s)
- Port 2228: rootlogin (root permitted)

**Netem Profiles (7 total):**
- Port 2322: 100ms latency
- Port 2323: 50ms + 5% loss
- Port 2324: 200ms + 10% loss
- Port 2325: 500ms latency
- Port 2326: 1000ms latency
- Port 2327: 100ms + 2% loss
- Port 2328: 50ms latency

**Test Users:** testuser, fancyuser, gituser, zshuser, dashuser, slowuser

---

## Phase 5: Network Setup and VM Scripts

### 2026-02-09

**Status: COMPLETE**

**File:** `nix/network-setup.nix`
- Lines: ~110
- TAP/bridge network setup and teardown
- NAT configuration with nftables

**File:** `nix/vm-scripts.nix`
- Lines: ~60
- VM management: check, stop, sshMcp, sshTarget

**Apps Created:**
- `ssh-vm-check` - Show running VMs
- `ssh-vm-stop` - Stop all VMs
- `ssh-vm-ssh-mcp` - SSH to MCP VM
- `ssh-vm-ssh-target` - SSH to target VM
- `ssh-network-setup` - Create bridge/TAPs
- `ssh-network-teardown` - Remove bridge/TAPs

---

## Phase 6: Test Library and Test Scripts

### 2026-02-09

**Status: COMPLETE**

**File:** `nix/tests/e2e-test.nix`
- Lines: ~450

**Test Suites Created:**
- `ssh-test-e2e` - Basic functionality tests
- `ssh-test-auth` - Authentication edge cases
- `ssh-test-netem` - Network degradation tests
- `ssh-test-stability` - Connection resilience
- `ssh-test-security` - Security controls
- `ssh-test-all` - Master test runner

**Features:**
- Color-coded output (PASS/FAIL/SKIP)
- Port availability checks
- Timing measurements for netem
- Comprehensive coverage of all sshd configs

---

## Phase 7: NixOS Test Framework Integration

### 2026-02-09

**Status: COMPLETE**

**File:** `nix/nixos-test.nix`
- Lines: ~285

**Test Configuration:**
- Two-node setup (mcp + target)
- Python test script with subtests
- Uses `pkgs.testers.nixosTest` (updated API)

**Test Cases:**
- Service availability checks
- MCP health endpoint
- SSH from MCP to target
- Keyonly port rejection
- Root login verification
- Different user shells
- File reading (small and large)

**Verification:**
```
nix eval .#checks.x86_64-linux --apply 'c: builtins.attrNames c'
# Output: [ "integration" ]
```

---

## Phase 8: Comprehensive Integration Testing

### 2026-02-10

**Status: COMPLETE**

**Issues Fixed:**

1. **SSH connection closed during key exchange**
   - Root cause: Missing `sshd` user/group for privilege separation
   - Root cause: Missing PAM configuration (`security.pam.services.sshd`)
   - Fix: Added both to ssh-target-vm.nix and nixos-test.nix

2. **Host key permissions**
   - Fix: Added `mkdir -p /etc/ssh`, `chmod 600` for private keys

**Test Results - All 7 SSHD Ports:**

| Port | Config | Expected | Result |
|------|--------|----------|--------|
| 2222 | standard | Password auth | ✓ PASS |
| 2223 | keyonly | Reject password | ✓ PASS (Permission denied) |
| 2224 | fancyprompt | Password auth | ✓ PASS |
| 2225 | slowauth | Password auth + delay | ✓ PASS |
| 2226 | denyall | Reject all auth | ✓ PASS (Permission denied) |
| 2227 | unstable | Password auth (restarts 5s) | ✓ PASS |
| 2228 | rootlogin | Root login permitted | ✓ PASS |

**Test Results - Root Login:**

| Port | Expected | Result |
|------|----------|--------|
| 2222 | Denied | ✓ PASS (Permission denied) |
| 2228 | Allowed | ✓ PASS (uid=0) |

**Test Results - Netem Degraded Ports:**

| Port | Profile | Expected | Result |
|------|---------|----------|--------|
| 2322 | 100ms latency | Higher latency | ✓ PASS (1313ms) |
| 2323 | → keyonly | Permission denied | ✓ PASS |
| 2324 | 200ms + 10% loss | Higher latency | ✓ PASS (404ms) |
| 2325 | 500ms latency | Higher latency | ✓ PASS (378ms) |
| 2326 | → denyall | Permission denied | ✓ PASS |
| 2327 | 100ms + 2% loss | Higher latency | ✓ PASS (403ms) |
| 2328 | 50ms latency | Higher latency | ✓ PASS (358ms) |

---

## Phase 9: Documentation and CI

**Status: PENDING**

Will create:
- `.github/workflows/nix.yml`
- Updated README.md

---

## Summary

**Files Created:**
| File | Lines | Purpose |
|------|-------|---------|
| `nix/constants/network.nix` | 24 | Network configuration |
| `nix/constants/ports.nix` | 19 | Port assignments |
| `nix/constants/timeouts.nix` | 28 | Timeout values |
| `nix/constants/users.nix` | 70 | User definitions |
| `nix/constants/sshd.nix` | 68 | SSHD configurations |
| `nix/constants/netem.nix` | 80 | Netem profiles |
| `nix/constants/default.nix` | 12 | Constants re-export |
| `nix/shell.nix` | 50 | Development shell |
| `flake.nix` | 107 | Flake orchestrator |
| `nix/mcp-vm.nix` | 147 | MCP Server VM |
| `nix/ssh-target-vm.nix` | 344 | Multi-SSHD Target VM |
| `nix/network-setup.nix` | 110 | TAP network scripts |
| `nix/vm-scripts.nix` | 60 | VM management scripts |
| `nix/tests/e2e-test.nix` | 450 | Test suites |
| `nix/nixos-test.nix` | 285 | NixOS test framework |

**Total Lines: ~1,854**

**Flake Outputs:**
- 8 packages (mcp-vm, ssh-target-vm variants)
- 12 apps (VM management + tests)
- 1 check (integration test)
- 1 devShell

---

## Issues Encountered

1. **Attribute conflict in nixos-test.nix**
   - Error: `attribute 'systemd.services' already defined`
   - Fix: Merged mapAttrs' result with additional services using `//`

2. **Another attribute conflict**
   - Error: `attribute 'environment.etc' already defined`
   - Fix: Merged sshd configs and test files into single `environment.etc`

3. **nixosTest API change**
   - Error: `'nixosTest' has been renamed to 'testers.nixosTest'`
   - Fix: Changed `pkgs.nixosTest` to `pkgs.testers.nixosTest`
