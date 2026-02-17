# Network Commands Implementation Plan

## Status: READY FOR REVIEW

## Reference Documents

- **Design Document**: `DESIGN_NETWORK_COMMANDS.md`
- **Security Patterns**: `mcp/lib/security.tcl`
- **Tool Registration**: `mcp/lib/tools.tcl`
- **Test Patterns**: `mcp/tests/mock/test_security.test`
- **VM Infrastructure**: `nix/ssh-target-vm.nix`

## Overview

This implementation plan details the step-by-step process for adding network diagnostic commands to the MCP server. The implementation follows the existing codebase patterns for TCL and Nix, maintains the security-first architecture, and includes comprehensive testing at each phase.

**Estimated Total New Lines**: ~2,800 lines
- Security patterns: ~400 lines
- Tools implementation: ~800 lines
- Tests: ~1,200 lines
- Nix infrastructure: ~400 lines

**Estimated Total New Tests**: ~180 tests

---

## Table of Contents

1. [Phase 1: Security Layer Extension](#phase-1-security-layer-extension)
   - 1.1 Allowlist Patterns for Network Commands
   - 1.2 Blocklist Patterns for Dangerous Variants
   - 1.3 Security Unit Tests
   - 1.4 Phase 1 Verification Checklist

2. [Phase 2: Connectivity Commands](#phase-2-connectivity-commands)
   - 2.1 DNS Query Patterns
   - 2.2 Ping/Traceroute Patterns with Limits
   - 2.3 Connectivity Tests
   - 2.4 Phase 2 Verification Checklist

3. [Phase 3: Core Network Tools](#phase-3-core-network-tools)
   - 3.1 ssh_network_interfaces Tool
   - 3.2 ssh_network_routes Tool
   - 3.3 ssh_network_firewall Tool
   - 3.4 Tool Unit Tests
   - 3.5 Phase 3 Verification Checklist

4. [Phase 4: Advanced Network Tools](#phase-4-advanced-network-tools)
   - 4.1 ssh_network_qdisc Tool
   - 4.2 ssh_network_connectivity Tool
   - 4.3 ssh_network_conntrack Tool (with Privacy Mode)
   - 4.4 Large Output Handling
   - 4.5 Phase 4 Verification Checklist

5. [Phase 5: Batch Execution](#phase-5-batch-execution)
   - 5.1 ssh_batch_commands Tool
   - 5.2 Pool Integration for Parallel Execution
   - 5.3 Batch Tests
   - 5.4 Phase 5 Verification Checklist

6. [Phase 6: Diff and Compare Tools](#phase-6-diff-and-compare-tools)
   - 6.1 ssh_network_compare Tool
   - 6.2 Snapshot Caching
   - 6.3 Diff Algorithm
   - 6.4 Phase 6 Verification Checklist

7. [Phase 7: MCP Server E2E Testing](#phase-7-mcp-server-e2e-testing)
   - 7.1 TCL Agent E2E Tests (e2e_test.tcl)
   - 7.2 Bash MCP E2E Tests (test_mcp_e2e.sh)
   - 7.3 Security E2E Tests (test_security_e2e.sh)
   - 7.4 Network Command E2E Test File
   - 7.5 Phase 7 Verification Checklist

8. [Phase 8: VM Test Infrastructure](#phase-8-vm-test-infrastructure)
   - 8.1 Target VM Network Configuration
   - 8.2 Traffic Control Setup
   - 8.3 Nftables Test Rules
   - 8.4 Network Namespace Setup
   - 8.5 NixOS Integration Tests
   - 8.6 Phase 8 Verification Checklist

9. [Phase 9: Documentation and Final Verification](#phase-9-documentation-and-final-verification)
   - 9.1 README Updates
   - 9.2 CLAUDE.md Updates
   - 9.3 Full Test Suite Run
   - 9.4 Final Verification Checklist

---

## Phase 1: Security Layer Extension

### Objective

Extend `mcp/lib/security.tcl` with allowlist patterns for network inspection commands and blocklist patterns for dangerous variants. This is the foundation - no tools can be implemented without these patterns.

### Duration: ~2 hours

### Step 1.1: Add Network Command Allowlist Patterns

**File**: `mcp/lib/security.tcl`
**Location**: After line 53 (end of current `allowed_commands` list)
**Lines to Add**: ~50

Add the following patterns to the `allowed_commands` variable:

```tcl
# ─────────────────────────────────────────────────────────────────
# NETWORK INSPECTION COMMANDS (Lines 54-105)
# Reference: DESIGN_NETWORK_COMMANDS.md Section "Updated Allowlist Patterns"
# ─────────────────────────────────────────────────────────────────

# ip command (inspection only, with JSON support)
# Pattern breakdown:
#   ^ip\s+          - starts with 'ip '
#   (-[46])?\s*     - optional -4 or -6 for address family
#   (-j(son)?)?\s*  - optional -j or -json for JSON output
#   (-d(etails)?)?\s* - optional -d or -details
#   (-s(tat(istics)?)?)?\s* - optional -s, -stat, -statistics
#   (link|addr|...)  - allowed subcommands
#   \s+(show|list)   - only show/list actions
{^ip\s+(-[46])?\s*(-j(son)?)?\s*(-d(etails)?)?\s*(-s(tat(istics)?)?)?\s*(link|addr|address|route|rule|neigh|neighbor|tunnel|maddr|vrf)\s+(show|list)(\s|$)}

# ip netns commands (list and identify only)
{^ip\s+(-j)?\s*netns\s+(list|identify)(\s|$)}

# ip with namespace context
{^ip\s+(-j)?\s*-n\s+[a-zA-Z0-9_-]+\s+(link|addr|route)\s+show(\s|$)}

# ethtool (STRICT read-only flags only)
# Allowed: -S(stats), -i(driver), -k(offload show), -g(ring), -a(pause), -c(coalesce), -m(module), -n(nway), -T(time)
# CRITICAL: This pattern must NOT match -E, -e, -f, -W, -K, -A, -C, -G, -L, -s, -p, -P, -u, -U
{^ethtool\s+(-[Sikgacmn]|-T)?\s+[a-zA-Z0-9@_-]+$}

# tc command (show only, with JSON and stats)
{^tc\s+(-[js])?\s*(qdisc|class|filter|action)\s+show(\s|$)}

# nft command (list only)
{^nft\s+(-j)?\s*list\s+(ruleset|tables|table|chain|set|map)(\s|$)}

# iptables (list only, with common tables)
# Pattern allows: -L, -n, -v, -S in any combination, optional -t table
{^ip6?tables\s+(-t\s+(filter|nat|mangle|raw|security)\s+)?-[LnvS]+(\s|$)}

# bridge command (show only)
{^bridge\s+(-j)?\s*(link|fdb|vlan|mdb)\s+show(\s|$)}

# conntrack (list only)
{^conntrack\s+-L(\s|$)}

# sysctl net parameters (read only)
{^sysctl\s+(-a\s+)?net\.}
```

**Verification**:
```bash
cd mcp && tclsh -c '
    source lib/security.tcl
    puts [::mcp::security::validate_command "ip -j addr show"]
'
# Expected: 1
```

### Step 1.2: Add Connectivity Command Patterns

**File**: `mcp/lib/security.tcl`
**Location**: After Step 1.1 additions
**Lines to Add**: ~25

```tcl
# ─────────────────────────────────────────────────────────────────
# CONNECTIVITY DIAGNOSTICS (Lines 106-130)
# Reference: DESIGN_NETWORK_COMMANDS.md Section "Category 7"
# ─────────────────────────────────────────────────────────────────

# DNS queries (simple A/AAAA lookups only)
# Blocks: AXFR (zone transfer), -x (reverse), complex options
{^dig\s+(\+short\s+)?[a-zA-Z0-9][a-zA-Z0-9.-]+$}
{^nslookup\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}
{^host\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}

# Ping with strict packet count limit (1-5 only)
# Pattern: ping or ping6, -c followed by single digit 1-5, then hostname
{^ping6?\s+-c\s*[1-5]\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}

# Traceroute with strict hop limit (1-15 only)
# Pattern: traceroute or traceroute6, -m followed by 1-15, then hostname
{^traceroute6?\s+-m\s*([1-9]|1[0-5])\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}

# MTR in report mode only (non-interactive)
# CRITICAL: Must have --report to prevent interactive mode
{^mtr\s+-c\s*[1-5]\s+--report\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}
```

### Step 1.3: Add Blocked Patterns for Network Commands

**File**: `mcp/lib/security.tcl`
**Location**: After line 147 (end of current `blocked_patterns` list)
**Lines to Add**: ~40

```tcl
# ─────────────────────────────────────────────────────────────────
# NETWORK MODIFICATION BLOCKLIST (Lines 148-190)
# Reference: DESIGN_NETWORK_COMMANDS.md Section "Commands Explicitly Blocked"
# CRITICAL: These patterns MUST catch any attempt to modify network state
# ─────────────────────────────────────────────────────────────────

# Block any ip commands that modify state
# Catches: ip link set, ip addr add, ip route del, etc.
{\bip\s+.*\s+(add|del|delete|change|replace|set|flush|append)\b}

# Block tc modifications
{\btc\s+.*\s+(add|del|delete|change|replace)\b}

# Block nft modifications
{\bnft\s+.*\s+(add|delete|insert|replace|flush|destroy|create)\b}

# Block iptables modifications
{\biptables\s+.*\s+(-[ADIRF]|--append|--delete|--insert|--replace|--flush)\b}
{\bip6tables\s+.*\s+(-[ADIRF]|--append|--delete|--insert|--replace|--flush)\b}

# Block ethtool write/config flags (CRITICAL)
# These flags can modify hardware: EEPROM, firmware, wake-on-lan, speed, etc.
{\bethtool\s+.*-[EefWKACGLspPuU]}
{\bethtool\s+.*--flash}
{\bethtool\s+.*--change}
{\bethtool\s+.*--set}
{\bethtool\s+.*--reset}

# Block ping/traceroute abuse patterns
{\bping\s+.*-[fiaAQrRs]}
{\bping\s+-c\s*([6-9]|[1-9][0-9]+)}
{\bping\s+.*-[iw]\s*0}
{\btraceroute\s+.*-[gis]}

# Block interactive mtr (must have --report)
{\bmtr\s+(?!.*--report)}
{\bmtr\s+.*-c\s*([6-9]|[1-9][0-9]+)}

# Block DNS zone transfers and advanced queries
{\bdig\s+.*AXFR}
{\bdig\s+.*-x\s}
{\bdig\s+.*\+trace}
```

### Step 1.4: Create Network Security Test File

**File**: `mcp/tests/mock/test_security_network.test`
**Lines**: ~400

```tcl
#!/usr/bin/env tclsh
# test_security_network.test - Security tests for network commands
#
# Reference: DESIGN_NETWORK_COMMANDS.md
# These tests verify that network inspection commands are allowed
# and network modification commands are blocked.

package require tcltest
namespace import ::tcltest::*

# Source dependencies
set script_dir [file dirname [info script]]
source [file join $script_dir "../../lib/util.tcl"]
source [file join $script_dir "../../lib/log.tcl"]
source [file join $script_dir "../../lib/security.tcl"]

# Suppress log output
::mcp::log::init ERROR [open /dev/null w]

#===========================================================================
# IP COMMAND - ALLOWED PATTERNS
#===========================================================================

test ip-allow-1.0 {ip link show is allowed} -body {
    ::mcp::security::validate_command "ip link show"
} -result 1

test ip-allow-1.1 {ip -j addr show is allowed} -body {
    ::mcp::security::validate_command "ip -j addr show"
} -result 1

test ip-allow-1.2 {ip -json link show is allowed} -body {
    ::mcp::security::validate_command "ip -json link show"
} -result 1

test ip-allow-1.3 {ip -j -d link show is allowed} -body {
    ::mcp::security::validate_command "ip -j -d link show"
} -result 1

test ip-allow-1.4 {ip -j -s link show is allowed} -body {
    ::mcp::security::validate_command "ip -j -s link show"
} -result 1

test ip-allow-1.5 {ip route show is allowed} -body {
    ::mcp::security::validate_command "ip route show"
} -result 1

test ip-allow-1.6 {ip -j route show table main is allowed} -body {
    ::mcp::security::validate_command "ip -j route show table main"
} -result 1

test ip-allow-1.7 {ip rule show is allowed} -body {
    ::mcp::security::validate_command "ip rule show"
} -result 1

test ip-allow-1.8 {ip neigh show is allowed} -body {
    ::mcp::security::validate_command "ip neigh show"
} -result 1

test ip-allow-1.9 {ip tunnel show is allowed} -body {
    ::mcp::security::validate_command "ip tunnel show"
} -result 1

test ip-allow-1.10 {ip -4 addr show is allowed} -body {
    ::mcp::security::validate_command "ip -4 addr show"
} -result 1

test ip-allow-1.11 {ip -6 route show is allowed} -body {
    ::mcp::security::validate_command "ip -6 route show"
} -result 1

test ip-allow-1.12 {ip netns list is allowed} -body {
    ::mcp::security::validate_command "ip netns list"
} -result 1

test ip-allow-1.13 {ip -n testns link show is allowed} -body {
    ::mcp::security::validate_command "ip -n testns link show"
} -result 1

#===========================================================================
# IP COMMAND - BLOCKED MODIFICATIONS
#===========================================================================

test ip-block-2.0 {ip link set is blocked} -body {
    ::mcp::security::validate_command "ip link set eth0 down"
} -returnCodes error -match glob -result "*SECURITY*"

test ip-block-2.1 {ip addr add is blocked} -body {
    ::mcp::security::validate_command "ip addr add 10.0.0.1/24 dev eth0"
} -returnCodes error -match glob -result "*SECURITY*"

test ip-block-2.2 {ip route add is blocked} -body {
    ::mcp::security::validate_command "ip route add default via 10.0.0.1"
} -returnCodes error -match glob -result "*SECURITY*"

test ip-block-2.3 {ip route del is blocked} -body {
    ::mcp::security::validate_command "ip route del 10.0.0.0/24"
} -returnCodes error -match glob -result "*SECURITY*"

test ip-block-2.4 {ip neigh add is blocked} -body {
    ::mcp::security::validate_command "ip neigh add 10.0.0.1 lladdr aa:bb:cc:dd:ee:ff dev eth0"
} -returnCodes error -match glob -result "*SECURITY*"

test ip-block-2.5 {ip link change is blocked} -body {
    ::mcp::security::validate_command "ip link change eth0 mtu 9000"
} -returnCodes error -match glob -result "*SECURITY*"

test ip-block-2.6 {ip addr flush is blocked} -body {
    ::mcp::security::validate_command "ip addr flush dev eth0"
} -returnCodes error -match glob -result "*SECURITY*"

test ip-block-2.7 {ip netns add is blocked} -body {
    ::mcp::security::validate_command "ip netns add newns"
} -returnCodes error -match glob -result "*SECURITY*"

#===========================================================================
# ETHTOOL - STRICT ALLOWLIST
#===========================================================================

test ethtool-allow-3.0 {ethtool eth0 is allowed} -body {
    ::mcp::security::validate_command "ethtool eth0"
} -result 1

test ethtool-allow-3.1 {ethtool -S eth0 is allowed} -body {
    ::mcp::security::validate_command "ethtool -S eth0"
} -result 1

test ethtool-allow-3.2 {ethtool -i eth0 is allowed} -body {
    ::mcp::security::validate_command "ethtool -i eth0"
} -result 1

test ethtool-allow-3.3 {ethtool -k eth0 is allowed} -body {
    ::mcp::security::validate_command "ethtool -k eth0"
} -result 1

test ethtool-allow-3.4 {ethtool -g eth0 is allowed} -body {
    ::mcp::security::validate_command "ethtool -g eth0"
} -result 1

test ethtool-allow-3.5 {ethtool -a eth0 is allowed} -body {
    ::mcp::security::validate_command "ethtool -a eth0"
} -result 1

test ethtool-allow-3.6 {ethtool -c eth0 is allowed} -body {
    ::mcp::security::validate_command "ethtool -c eth0"
} -result 1

# BLOCKED ETHTOOL FLAGS (CRITICAL TESTS)

test ethtool-block-4.0 {ethtool -E (EEPROM write) is blocked} -body {
    ::mcp::security::validate_command "ethtool -E eth0"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.1 {ethtool -e (EEPROM read) is blocked} -body {
    ::mcp::security::validate_command "ethtool -e eth0"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.2 {ethtool -f (firmware flash) is blocked} -body {
    ::mcp::security::validate_command "ethtool -f eth0 firmware.bin"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.3 {ethtool --flash is blocked} -body {
    ::mcp::security::validate_command "ethtool --flash eth0 firmware.bin"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.4 {ethtool -W (wake-on-lan set) is blocked} -body {
    ::mcp::security::validate_command "ethtool -W eth0"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.5 {ethtool -K (offload set) is blocked} -body {
    ::mcp::security::validate_command "ethtool -K eth0 tso on"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.6 {ethtool -s (speed set) is blocked} -body {
    ::mcp::security::validate_command "ethtool -s eth0 speed 1000"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.7 {ethtool -A (pause set) is blocked} -body {
    ::mcp::security::validate_command "ethtool -A eth0 rx on"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.8 {ethtool -C (coalesce set) is blocked} -body {
    ::mcp::security::validate_command "ethtool -C eth0 rx-usecs 100"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.9 {ethtool -G (ring set) is blocked} -body {
    ::mcp::security::validate_command "ethtool -G eth0 rx 4096"
} -returnCodes error -match glob -result "*SECURITY*"

test ethtool-block-4.10 {ethtool -L (channel set) is blocked} -body {
    ::mcp::security::validate_command "ethtool -L eth0 combined 4"
} -returnCodes error -match glob -result "*SECURITY*"

#===========================================================================
# TC COMMAND
#===========================================================================

test tc-allow-5.0 {tc qdisc show is allowed} -body {
    ::mcp::security::validate_command "tc qdisc show"
} -result 1

test tc-allow-5.1 {tc -j qdisc show is allowed} -body {
    ::mcp::security::validate_command "tc -j qdisc show"
} -result 1

test tc-allow-5.2 {tc class show dev eth0 is allowed} -body {
    ::mcp::security::validate_command "tc class show dev eth0"
} -result 1

test tc-allow-5.3 {tc filter show is allowed} -body {
    ::mcp::security::validate_command "tc filter show"
} -result 1

test tc-allow-5.4 {tc -s qdisc show is allowed} -body {
    ::mcp::security::validate_command "tc -s qdisc show"
} -result 1

test tc-block-6.0 {tc qdisc add is blocked} -body {
    ::mcp::security::validate_command "tc qdisc add dev eth0 root netem delay 100ms"
} -returnCodes error -match glob -result "*SECURITY*"

test tc-block-6.1 {tc qdisc del is blocked} -body {
    ::mcp::security::validate_command "tc qdisc del dev eth0 root"
} -returnCodes error -match glob -result "*SECURITY*"

test tc-block-6.2 {tc qdisc change is blocked} -body {
    ::mcp::security::validate_command "tc qdisc change dev eth0 root netem delay 200ms"
} -returnCodes error -match glob -result "*SECURITY*"

#===========================================================================
# NFT/IPTABLES
#===========================================================================

test nft-allow-7.0 {nft list ruleset is allowed} -body {
    ::mcp::security::validate_command "nft list ruleset"
} -result 1

test nft-allow-7.1 {nft -j list tables is allowed} -body {
    ::mcp::security::validate_command "nft -j list tables"
} -result 1

test nft-allow-7.2 {nft list table inet filter is allowed} -body {
    ::mcp::security::validate_command "nft list table inet filter"
} -result 1

test nft-block-8.0 {nft add is blocked} -body {
    ::mcp::security::validate_command "nft add table inet test"
} -returnCodes error -match glob -result "*SECURITY*"

test nft-block-8.1 {nft delete is blocked} -body {
    ::mcp::security::validate_command "nft delete table inet test"
} -returnCodes error -match glob -result "*SECURITY*"

test nft-block-8.2 {nft flush is blocked} -body {
    ::mcp::security::validate_command "nft flush ruleset"
} -returnCodes error -match glob -result "*SECURITY*"

test iptables-allow-9.0 {iptables -L -n is allowed} -body {
    ::mcp::security::validate_command "iptables -L -n"
} -result 1

test iptables-allow-9.1 {iptables -t nat -L -n -v is allowed} -body {
    ::mcp::security::validate_command "iptables -t nat -L -n -v"
} -result 1

test iptables-block-10.0 {iptables -A is blocked} -body {
    ::mcp::security::validate_command "iptables -A INPUT -j DROP"
} -returnCodes error -match glob -result "*SECURITY*"

test iptables-block-10.1 {iptables -D is blocked} -body {
    ::mcp::security::validate_command "iptables -D INPUT 1"
} -returnCodes error -match glob -result "*SECURITY*"

test iptables-block-10.2 {iptables -F is blocked} -body {
    ::mcp::security::validate_command "iptables -F"
} -returnCodes error -match glob -result "*SECURITY*"

#===========================================================================
# PING/TRACEROUTE WITH LIMITS
#===========================================================================

test ping-allow-11.0 {ping -c 1 is allowed} -body {
    ::mcp::security::validate_command "ping -c 1 8.8.8.8"
} -result 1

test ping-allow-11.1 {ping -c 3 is allowed} -body {
    ::mcp::security::validate_command "ping -c 3 google.com"
} -result 1

test ping-allow-11.2 {ping -c 5 is allowed (max)} -body {
    ::mcp::security::validate_command "ping -c 5 example.com"
} -result 1

test ping-block-12.0 {ping -c 6 is blocked (over limit)} -body {
    ::mcp::security::validate_command "ping -c 6 8.8.8.8"
} -returnCodes error -match glob -result "*SECURITY*"

test ping-block-12.1 {ping -c 100 is blocked} -body {
    ::mcp::security::validate_command "ping -c 100 8.8.8.8"
} -returnCodes error -match glob -result "*SECURITY*"

test ping-block-12.2 {ping -f (flood) is blocked} -body {
    ::mcp::security::validate_command "ping -f 8.8.8.8"
} -returnCodes error -match glob -result "*SECURITY*"

test ping-block-12.3 {ping without -c is blocked} -body {
    ::mcp::security::validate_command "ping 8.8.8.8"
} -returnCodes error -match glob -result "*SECURITY*"

test traceroute-allow-13.0 {traceroute -m 10 is allowed} -body {
    ::mcp::security::validate_command "traceroute -m 10 google.com"
} -result 1

test traceroute-allow-13.1 {traceroute -m 15 is allowed (max)} -body {
    ::mcp::security::validate_command "traceroute -m 15 example.com"
} -result 1

test traceroute-block-14.0 {traceroute -m 16 is blocked} -body {
    ::mcp::security::validate_command "traceroute -m 16 google.com"
} -returnCodes error -match glob -result "*SECURITY*"

test traceroute-block-14.1 {traceroute without -m is blocked} -body {
    ::mcp::security::validate_command "traceroute google.com"
} -returnCodes error -match glob -result "*SECURITY*"

test traceroute-block-14.2 {traceroute -g (source route) is blocked} -body {
    ::mcp::security::validate_command "traceroute -g 10.0.0.1 google.com"
} -returnCodes error -match glob -result "*SECURITY*"

#===========================================================================
# DNS QUERIES
#===========================================================================

test dns-allow-15.0 {dig domain is allowed} -body {
    ::mcp::security::validate_command "dig example.com"
} -result 1

test dns-allow-15.1 {dig +short domain is allowed} -body {
    ::mcp::security::validate_command "dig +short example.com"
} -result 1

test dns-allow-15.2 {nslookup domain is allowed} -body {
    ::mcp::security::validate_command "nslookup example.com"
} -result 1

test dns-allow-15.3 {host domain is allowed} -body {
    ::mcp::security::validate_command "host example.com"
} -result 1

test dns-block-16.0 {dig AXFR is blocked} -body {
    ::mcp::security::validate_command "dig AXFR example.com"
} -returnCodes error -match glob -result "*SECURITY*"

test dns-block-16.1 {dig -x (reverse) is blocked} -body {
    ::mcp::security::validate_command "dig -x 8.8.8.8"
} -returnCodes error -match glob -result "*SECURITY*"

test dns-block-16.2 {dig +trace is blocked} -body {
    ::mcp::security::validate_command "dig +trace example.com"
} -returnCodes error -match glob -result "*SECURITY*"

#===========================================================================
# MTR (MUST have --report)
#===========================================================================

test mtr-allow-17.0 {mtr -c 3 --report is allowed} -body {
    ::mcp::security::validate_command "mtr -c 3 --report google.com"
} -result 1

test mtr-allow-17.1 {mtr -c 5 --report is allowed (max)} -body {
    ::mcp::security::validate_command "mtr -c 5 --report example.com"
} -result 1

test mtr-block-18.0 {mtr without --report is blocked} -body {
    ::mcp::security::validate_command "mtr google.com"
} -returnCodes error -match glob -result "*SECURITY*"

test mtr-block-18.1 {mtr -c 6 is blocked (over limit)} -body {
    ::mcp::security::validate_command "mtr -c 6 --report google.com"
} -returnCodes error -match glob -result "*SECURITY*"

#===========================================================================
# BRIDGE AND CONNTRACK
#===========================================================================

test bridge-allow-19.0 {bridge link show is allowed} -body {
    ::mcp::security::validate_command "bridge link show"
} -result 1

test bridge-allow-19.1 {bridge -j fdb show is allowed} -body {
    ::mcp::security::validate_command "bridge -j fdb show"
} -result 1

test conntrack-allow-20.0 {conntrack -L is allowed} -body {
    ::mcp::security::validate_command "conntrack -L"
} -result 1

test sysctl-allow-21.0 {sysctl net.ipv4.ip_forward is allowed} -body {
    ::mcp::security::validate_command "sysctl net.ipv4.ip_forward"
} -result 1

test sysctl-allow-21.1 {sysctl -a net. is allowed} -body {
    ::mcp::security::validate_command "sysctl -a net."
} -result 1

#===========================================================================
# EDGE CASES AND BYPASS ATTEMPTS
#===========================================================================

test bypass-22.0 {ip show then set via semicolon blocked} -body {
    ::mcp::security::validate_command "ip link show; ip link set eth0 down"
} -returnCodes error -match glob -result "*SECURITY*"

test bypass-22.1 {ip show with embedded set blocked} -body {
    ::mcp::security::validate_command "ip link show set eth0"
} -returnCodes error -match glob -result "*SECURITY*"

test bypass-22.2 {ethtool stats then flash blocked} -body {
    ::mcp::security::validate_command "ethtool -S eth0; ethtool -f eth0 fw.bin"
} -returnCodes error -match glob -result "*SECURITY*"

test bypass-22.3 {whitespace padding attempt} -body {
    ::mcp::security::validate_command "  ip  link  set  eth0  down  "
} -returnCodes error -match glob -result "*SECURITY*"

test bypass-22.4 {tab characters in command} -body {
    ::mcp::security::validate_command "ip\tlink\tset\teth0\tdown"
} -returnCodes error -match glob -result "*SECURITY*"

# Cleanup
cleanupTests
```

### Step 1.5: Update Test Runner

**File**: `mcp/tests/run_all_tests.sh`
**Location**: After line 65 (in the for loop)
**Change**: The existing loop already handles `test_*.test`, no change needed.

**Verification**:
```bash
ls mcp/tests/mock/test_security_network.test
# Should exist
```

### Phase 1 Verification Checklist

Run the following commands and verify all pass:

```bash
# 1. Test that security module loads without error
cd mcp && tclsh -c '
    source lib/security.tcl
    puts "Security module loaded successfully"
'

# 2. Run new security tests
cd mcp/tests/mock && tclsh test_security_network.test
# Expected: All tests pass (should be ~80+ tests)

# 3. Run full security test suite (original + new)
cd mcp/tests && ./run_all_tests.sh
# Expected: 435+ tests pass (355 original + 80 new)

# 4. Verify critical patterns manually
tclsh -c '
    source lib/security.tcl
    # These MUST pass
    puts "ip -j addr show: [::mcp::security::validate_command {ip -j addr show}]"
    puts "ethtool -S eth0: [::mcp::security::validate_command {ethtool -S eth0}]"
    puts "tc -j qdisc show: [::mcp::security::validate_command {tc -j qdisc show}]"
    # These MUST fail
    catch {::mcp::security::validate_command "ip link set eth0 down"} err
    puts "ip link set blocked: [string match *SECURITY* $err]"
    catch {::mcp::security::validate_command "ethtool -f eth0 fw.bin"} err
    puts "ethtool flash blocked: [string match *SECURITY* $err]"
'
```

| Check | Expected Result | Status |
|-------|-----------------|--------|
| Security module loads | No errors | ☐ |
| New tests created | `test_security_network.test` exists | ☐ |
| New tests pass | 80+ tests, 0 failures | ☐ |
| Full suite passes | 435+ tests, 0 failures | ☐ |
| ip show allowed | Returns 1 | ☐ |
| ip set blocked | Throws SECURITY error | ☐ |
| ethtool -S allowed | Returns 1 | ☐ |
| ethtool -f blocked | Throws SECURITY error | ☐ |
| ping -c 5 allowed | Returns 1 | ☐ |
| ping -c 6 blocked | Throws SECURITY error | ☐ |

---

## Phase 2: Connectivity Commands

### Objective

Verify connectivity command patterns work correctly and add additional edge case tests.

### Duration: ~1 hour

### Step 2.1: Add Connectivity Edge Case Tests

**File**: `mcp/tests/mock/test_security_network.test`
**Location**: Add after existing tests
**Lines to Add**: ~50

```tcl
#===========================================================================
# CONNECTIVITY EDGE CASES
#===========================================================================

test ping-edge-23.0 {ping6 -c 3 is allowed} -body {
    ::mcp::security::validate_command "ping6 -c 3 google.com"
} -result 1

test ping-edge-23.1 {ping with IP address allowed} -body {
    ::mcp::security::validate_command "ping -c 3 192.168.1.1"
} -result 1

test ping-edge-23.2 {ping -c1 (no space) blocked} -body {
    # Pattern requires space after -c
    ::mcp::security::validate_command "ping -c1 8.8.8.8"
} -returnCodes error -match glob -result "*SECURITY*"

test traceroute-edge-24.0 {traceroute6 -m 10 is allowed} -body {
    ::mcp::security::validate_command "traceroute6 -m 10 google.com"
} -result 1

test traceroute-edge-24.1 {traceroute -m10 (no space) blocked} -body {
    ::mcp::security::validate_command "traceroute -m10 google.com"
} -returnCodes error -match glob -result "*SECURITY*"

test dns-edge-25.0 {dig subdomain allowed} -body {
    ::mcp::security::validate_command "dig api.example.com"
} -result 1

test dns-edge-25.1 {dig with underscore allowed} -body {
    ::mcp::security::validate_command "dig _dmarc.example.com"
} -result 1

test dns-edge-25.2 {host with IP blocked (looks like reverse)} -body {
    # host with IP might trigger reverse lookup
    ::mcp::security::validate_command "host 8.8.8.8"
} -returnCodes error -match glob -result "*SECURITY*"
```

### Phase 2 Verification Checklist

```bash
# Run security tests
cd mcp/tests/mock && tclsh test_security_network.test
# Expected: All tests pass

# Verify connectivity patterns
tclsh -c '
    source lib/security.tcl
    puts "ping -c 3 8.8.8.8: [::mcp::security::validate_command {ping -c 3 8.8.8.8}]"
    puts "traceroute -m 10 google.com: [::mcp::security::validate_command {traceroute -m 10 google.com}]"
    puts "dig example.com: [::mcp::security::validate_command {dig example.com}]"
    puts "mtr -c 3 --report google.com: [::mcp::security::validate_command {mtr -c 3 --report google.com}]"
'
```

| Check | Expected Result | Status |
|-------|-----------------|--------|
| Connectivity tests pass | All pass | ☐ |
| ping -c 3 allowed | Returns 1 | ☐ |
| traceroute -m 10 allowed | Returns 1 | ☐ |
| dig allowed | Returns 1 | ☐ |
| mtr --report allowed | Returns 1 | ☐ |

---

## Phase 3: Core Network Tools

### Objective

Implement the high-level network tools: `ssh_network_interfaces`, `ssh_network_routes`, `ssh_network_firewall`.

### Duration: ~4 hours

### Step 3.1: Add Network Tool Definitions

**File**: `mcp/lib/tools.tcl`
**Location**: After line 130 (after `_def_ssh_pool_stats`)
**Lines to Add**: ~120

```tcl
#=========================================================================
# NETWORK TOOL DEFINITIONS (Lines 131-250)
# Reference: DESIGN_NETWORK_COMMANDS.md Section "Option B: High-Level Network Tools"
#=========================================================================

proc _def_ssh_network_interfaces {} {
    return [dict create \
        name "ssh_network_interfaces" \
        description "List network interfaces with addresses, state, and stability info" \
        inputSchema [dict create \
            type "object" \
            properties [dict create \
                session_id [dict create type "string" description "Session ID"] \
                interface [dict create type "string" description "Optional: specific interface"] \
                include_stats [dict create type "boolean" description "Include RX/TX statistics"] \
                include_stability [dict create type "boolean" description "Include link flap detection info"] \
            ] \
            required [list session_id] \
        ] \
    ]
}

proc _def_ssh_network_routes {} {
    return [dict create \
        name "ssh_network_routes" \
        description "Show routing table" \
        inputSchema [dict create \
            type "object" \
            properties [dict create \
                session_id [dict create type "string" description "Session ID"] \
                table [dict create type "string" description "Routing table (main, local, etc.)"] \
                family [dict create type "string" enum [list inet inet6 all] description "Address family"] \
            ] \
            required [list session_id] \
        ] \
    ]
}

proc _def_ssh_network_firewall {} {
    return [dict create \
        name "ssh_network_firewall" \
        description "Show firewall rules (nftables or iptables)" \
        inputSchema [dict create \
            type "object" \
            properties [dict create \
                session_id [dict create type "string" description "Session ID"] \
                format [dict create type "string" enum [list nft iptables auto] description "Firewall format"] \
                table [dict create type "string" description "Specific table to show"] \
                summary [dict create type "boolean" description "Return summary instead of full rules"] \
            ] \
            required [list session_id] \
        ] \
    ]
}

proc _def_ssh_network_qdisc {} {
    return [dict create \
        name "ssh_network_qdisc" \
        description "Show traffic control qdiscs and classes" \
        inputSchema [dict create \
            type "object" \
            properties [dict create \
                session_id [dict create type "string" description "Session ID"] \
                interface [dict create type "string" description "Specific interface"] \
                include_stats [dict create type "boolean" description "Include statistics"] \
            ] \
            required [list session_id] \
        ] \
    ]
}

proc _def_ssh_network_connectivity {} {
    return [dict create \
        name "ssh_network_connectivity" \
        description "Test network connectivity from target host (ping, DNS, traceroute)" \
        inputSchema [dict create \
            type "object" \
            properties [dict create \
                session_id [dict create type "string" description "Session ID"] \
                target [dict create type "string" description "Hostname or IP to test"] \
                tests [dict create type "array" items [dict create type "string"] description "Tests to run: ping, dns, traceroute"] \
                ping_count [dict create type "integer" minimum 1 maximum 5 description "Ping packet count"] \
                traceroute_hops [dict create type "integer" minimum 1 maximum 15 description "Max traceroute hops"] \
            ] \
            required [list session_id target] \
        ] \
    ]
}

proc _def_ssh_batch_commands {} {
    return [dict create \
        name "ssh_batch_commands" \
        description "Execute multiple commands concurrently (max 5)" \
        inputSchema [dict create \
            type "object" \
            properties [dict create \
                session_id [dict create type "string" description "Session ID"] \
                commands [dict create type "array" items [dict create type "string"] minItems 1 maxItems 5 description "Commands to execute"] \
                parallel [dict create type "boolean" description "Execute in parallel (default: true)"] \
                stop_on_error [dict create type "boolean" description "Stop on first error"] \
            ] \
            required [list session_id commands] \
        ] \
    ]
}
```

### Step 3.2: Update Tool Registration

**File**: `mcp/lib/tools.tcl`
**Location**: In `register_all` proc (around line 139)
**Change**: Add new tools to registration

```tcl
proc register_all {} {
    variable tool_definitions

    set tool_definitions [list \
        [_def_ssh_connect] \
        [_def_ssh_disconnect] \
        [_def_ssh_run_command] \
        [_def_ssh_run] \
        [_def_ssh_cat_file] \
        [_def_ssh_hostname] \
        [_def_ssh_list_sessions] \
        [_def_ssh_pool_stats] \
        [_def_ssh_network_interfaces] \
        [_def_ssh_network_routes] \
        [_def_ssh_network_firewall] \
        [_def_ssh_network_qdisc] \
        [_def_ssh_network_connectivity] \
        [_def_ssh_batch_commands] \
    ]
}
```

### Step 3.3: Update Tool Dispatcher

**File**: `mcp/lib/tools.tcl`
**Location**: In `dispatch` proc (around line 155)
**Lines to Add**: ~8

```tcl
proc dispatch {tool_name args_dict mcp_session_id} {
    switch $tool_name {
        "ssh_connect"           { return [tool_ssh_connect $args_dict $mcp_session_id] }
        "ssh_disconnect"        { return [tool_ssh_disconnect $args_dict $mcp_session_id] }
        "ssh_run_command"       { return [tool_ssh_run_command $args_dict $mcp_session_id] }
        "ssh_run"               { return [tool_ssh_run_command $args_dict $mcp_session_id] }
        "ssh_cat_file"          { return [tool_ssh_cat_file $args_dict $mcp_session_id] }
        "ssh_hostname"          { return [tool_ssh_hostname $args_dict $mcp_session_id] }
        "ssh_list_sessions"     { return [tool_ssh_list_sessions $args_dict $mcp_session_id] }
        "ssh_pool_stats"        { return [tool_ssh_pool_stats $args_dict $mcp_session_id] }
        # Network tools
        "ssh_network_interfaces" { return [tool_ssh_network_interfaces $args_dict $mcp_session_id] }
        "ssh_network_routes"     { return [tool_ssh_network_routes $args_dict $mcp_session_id] }
        "ssh_network_firewall"   { return [tool_ssh_network_firewall $args_dict $mcp_session_id] }
        "ssh_network_qdisc"      { return [tool_ssh_network_qdisc $args_dict $mcp_session_id] }
        "ssh_network_connectivity" { return [tool_ssh_network_connectivity $args_dict $mcp_session_id] }
        "ssh_batch_commands"     { return [tool_ssh_batch_commands $args_dict $mcp_session_id] }
        default {
            error [dict create \
                code $::mcp::jsonrpc::ERROR_METHOD \
                message "Unknown tool: $tool_name" \
            ]
        }
    }
}
```

### Step 3.4: Implement `tool_ssh_network_interfaces`

**File**: `mcp/lib/tools.tcl`
**Location**: After `tool_ssh_pool_stats` (around line 495)
**Lines to Add**: ~80

```tcl
#=========================================================================
# ssh_network_interfaces (Lines 500-580)
# Reference: DESIGN_NETWORK_COMMANDS.md
#=========================================================================

proc tool_ssh_network_interfaces {args mcp_session_id} {
    if {![dict exists $args session_id]} {
        return [_tool_error "Missing required parameter: session_id"]
    }

    set session_id [dict get $args session_id]
    set interface [expr {[dict exists $args interface] ? [dict get $args interface] : ""}]
    set include_stats [expr {[dict exists $args include_stats] ? [dict get $args include_stats] : 0}]
    set include_stability [expr {[dict exists $args include_stability] ? [dict get $args include_stability] : 1}]

    # Convert boolean strings
    if {$include_stats eq "true"} { set include_stats 1 }
    if {$include_stats eq "false"} { set include_stats 0 }
    if {$include_stability eq "true"} { set include_stability 1 }
    if {$include_stability eq "false"} { set include_stability 0 }

    # Get session
    set session [::mcp::session::get $session_id]
    if {$session eq {}} {
        return [_tool_error "Session not found: $session_id"]
    }

    # Verify ownership
    if {![_verify_session_owner $session_id $mcp_session_id]} {
        return [_tool_error "Session not owned by this client"]
    }

    set spawn_id [dict get $session spawn_id]

    # Build command with optional flags
    set cmd "ip -j"
    if {$include_stability} {
        append cmd " -d"  ;# -d includes link_changes count
    }
    if {$include_stats} {
        append cmd " -s"  ;# -s includes statistics
    }
    append cmd " addr show"
    if {$interface ne ""} {
        # Validate interface name (alphanumeric, @, _, -)
        if {![regexp {^[a-zA-Z0-9@_-]+$} $interface]} {
            return [_tool_error "Invalid interface name: $interface"]
        }
        append cmd " dev $interface"
    }

    # Execute via security layer
    if {[catch {::mcp::security::validate_command $cmd} err]} {
        return [_tool_error "Command not permitted: $err"]
    }

    if {[catch {
        set output [::prompt::run $spawn_id $cmd]
    } err]} {
        return [_tool_error "Command execution failed: $err"]
    }

    # Parse JSON output
    set json_output [string trim $output]

    # Handle large output
    set output_result [_handle_large_output $json_output 262144]

    set result [dict create \
        content [list [dict create type "text" text [dict get $output_result content]]] \
        raw_json $json_output \
        timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1] \
    ]

    if {[dict get $output_result truncated]} {
        dict set result truncated true
        dict set result original_size_bytes [dict get $output_result original_size_bytes]
    }

    return $result
}
```

### Step 3.5: Implement `tool_ssh_network_routes`

**File**: `mcp/lib/tools.tcl`
**Location**: After `tool_ssh_network_interfaces`
**Lines to Add**: ~60

```tcl
#=========================================================================
# ssh_network_routes (Lines 585-645)
#=========================================================================

proc tool_ssh_network_routes {args mcp_session_id} {
    if {![dict exists $args session_id]} {
        return [_tool_error "Missing required parameter: session_id"]
    }

    set session_id [dict get $args session_id]
    set table [expr {[dict exists $args table] ? [dict get $args table] : "main"}]
    set family [expr {[dict exists $args family] ? [dict get $args family] : "all"}]

    # Get session
    set session [::mcp::session::get $session_id]
    if {$session eq {}} {
        return [_tool_error "Session not found: $session_id"]
    }

    if {![_verify_session_owner $session_id $mcp_session_id]} {
        return [_tool_error "Session not owned by this client"]
    }

    set spawn_id [dict get $session spawn_id]
    set results [dict create]

    # Build commands based on family
    set commands [list]
    if {$family eq "all" || $family eq "inet"} {
        lappend commands "ip -4 -j route show table $table"
    }
    if {$family eq "all" || $family eq "inet6"} {
        lappend commands "ip -6 -j route show table $table"
    }

    foreach cmd $commands {
        if {[catch {::mcp::security::validate_command $cmd} err]} {
            return [_tool_error "Command not permitted: $err"]
        }

        if {[catch {
            set output [::prompt::run $spawn_id $cmd]
        } err]} {
            return [_tool_error "Command execution failed: $err"]
        }

        # Accumulate results
        if {[string match "*-4*" $cmd]} {
            dict set results ipv4 [string trim $output]
        } else {
            dict set results ipv6 [string trim $output]
        }
    }

    return [dict create \
        content [list [dict create type "text" text [dict get $results ipv4]]] \
        routes $results \
        table $table \
        family $family \
        timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1] \
    ]
}
```

### Step 3.6: Implement `tool_ssh_network_firewall`

**File**: `mcp/lib/tools.tcl`
**Location**: After `tool_ssh_network_routes`
**Lines to Add**: ~80

```tcl
#=========================================================================
# ssh_network_firewall (Lines 650-730)
#=========================================================================

proc tool_ssh_network_firewall {args mcp_session_id} {
    if {![dict exists $args session_id]} {
        return [_tool_error "Missing required parameter: session_id"]
    }

    set session_id [dict get $args session_id]
    set format [expr {[dict exists $args format] ? [dict get $args format] : "auto"}]
    set table [expr {[dict exists $args table] ? [dict get $args table] : ""}]
    set summary [expr {[dict exists $args summary] ? [dict get $args summary] : 0}]

    if {$summary eq "true"} { set summary 1 }
    if {$summary eq "false"} { set summary 0 }

    set session [::mcp::session::get $session_id]
    if {$session eq {}} {
        return [_tool_error "Session not found: $session_id"]
    }

    if {![_verify_session_owner $session_id $mcp_session_id]} {
        return [_tool_error "Session not owned by this client"]
    }

    set spawn_id [dict get $session spawn_id]

    # Auto-detect firewall type if needed
    if {$format eq "auto"} {
        # Try nft first (modern)
        if {[catch {
            ::mcp::security::validate_command "nft list tables"
            set probe [::prompt::run $spawn_id "nft list tables"]
            if {[string match "*table*" $probe]} {
                set format "nft"
            }
        }]} {
            set format "iptables"
        }
    }

    set cmd ""
    switch $format {
        "nft" {
            if {$table ne ""} {
                # Validate table name
                if {![regexp {^[a-zA-Z0-9_]+$} $table]} {
                    return [_tool_error "Invalid table name"]
                }
                set cmd "nft -j list table inet $table"
            } else {
                set cmd "nft -j list ruleset"
            }
        }
        "iptables" {
            if {$table ne ""} {
                set cmd "iptables -t $table -L -n -v"
            } else {
                set cmd "iptables -L -n -v"
            }
        }
        default {
            return [_tool_error "Unknown firewall format: $format"]
        }
    }

    if {[catch {::mcp::security::validate_command $cmd} err]} {
        return [_tool_error "Command not permitted: $err"]
    }

    if {[catch {
        set output [::prompt::run $spawn_id $cmd]
    } err]} {
        return [_tool_error "Command execution failed: $err"]
    }

    # Handle large output
    set output_result [_handle_large_output $output 262144]

    set result [dict create \
        content [list [dict create type "text" text [dict get $output_result content]]] \
        format $format \
        timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1] \
    ]

    if {[dict get $output_result truncated]} {
        dict set result truncated true
        dict set result suggestion "Use 'table' parameter to query specific tables"
    }

    return $result
}
```

### Step 3.7: Add Large Output Handler

**File**: `mcp/lib/tools.tcl`
**Location**: In helper functions section (around line 500)
**Lines to Add**: ~30

```tcl
#=========================================================================
# LARGE OUTPUT HANDLER (Lines 540-570)
# Reference: DESIGN_NETWORK_COMMANDS.md Section "Large Output Handling"
#=========================================================================

proc _handle_large_output {output max_size} {
    set size [string length $output]

    if {$size <= $max_size} {
        return [dict create \
            truncated false \
            content $output \
        ]
    }

    # Truncate and add warning
    set truncated_output [string range $output 0 [expr {$max_size - 1}]]

    return [dict create \
        truncated true \
        original_size_bytes $size \
        returned_size_bytes $max_size \
        content $truncated_output \
    ]
}
```

### Step 3.8: Create Network Tool Tests

**File**: `mcp/tests/mock/test_tools_network.test`
**Lines**: ~200

```tcl
#!/usr/bin/env tclsh
# test_tools_network.test - Tests for network tools

package require tcltest
namespace import ::tcltest::*

set script_dir [file dirname [info script]]
source [file join $script_dir "../../lib/util.tcl"]
source [file join $script_dir "../../lib/log.tcl"]
source [file join $script_dir "../../lib/security.tcl"]
source [file join $script_dir "../../lib/session.tcl"]
source [file join $script_dir "../../lib/pool.tcl"]
source [file join $script_dir "../../lib/jsonrpc.tcl"]
source [file join $script_dir "../../lib/metrics.tcl"]
source [file join $script_dir "../../lib/mcp_session.tcl"]
source [file join $script_dir "../../lib/tools.tcl"]

::mcp::log::init ERROR [open /dev/null w]

#===========================================================================
# TOOL REGISTRATION TESTS
#===========================================================================

test tools-reg-1.0 {network tools are registered} -body {
    set defs [::mcp::tools::get_definitions]
    set names [list]
    foreach def $defs {
        lappend names [dict get $def name]
    }
    expr {"ssh_network_interfaces" in $names}
} -result 1

test tools-reg-1.1 {ssh_network_routes is registered} -body {
    set defs [::mcp::tools::get_definitions]
    set names [list]
    foreach def $defs {
        lappend names [dict get $def name]
    }
    expr {"ssh_network_routes" in $names}
} -result 1

test tools-reg-1.2 {ssh_network_firewall is registered} -body {
    set defs [::mcp::tools::get_definitions]
    set names [list]
    foreach def $defs {
        lappend names [dict get $def name]
    }
    expr {"ssh_network_firewall" in $names}
} -result 1

test tools-reg-1.3 {ssh_batch_commands is registered} -body {
    set defs [::mcp::tools::get_definitions]
    set names [list]
    foreach def $defs {
        lappend names [dict get $def name]
    }
    expr {"ssh_batch_commands" in $names}
} -result 1

#===========================================================================
# INPUT VALIDATION TESTS
#===========================================================================

test tools-val-2.0 {ssh_network_interfaces requires session_id} -body {
    set result [::mcp::tools::dispatch "ssh_network_interfaces" {} "mcp_123"]
    dict get $result isError
} -result true

test tools-val-2.1 {ssh_network_routes requires session_id} -body {
    set result [::mcp::tools::dispatch "ssh_network_routes" {} "mcp_123"]
    dict get $result isError
} -result true

test tools-val-2.2 {ssh_batch_commands requires commands array} -body {
    set result [::mcp::tools::dispatch "ssh_batch_commands" \
        [dict create session_id "sess_123"] "mcp_123"]
    dict get $result isError
} -result true

#===========================================================================
# LARGE OUTPUT HANDLER TESTS
#===========================================================================

test output-3.0 {small output not truncated} -body {
    set result [::mcp::tools::_handle_large_output "small output" 1000]
    dict get $result truncated
} -result false

test output-3.1 {large output truncated} -body {
    set large [string repeat "x" 1000]
    set result [::mcp::tools::_handle_large_output $large 500]
    dict get $result truncated
} -result true

test output-3.2 {truncated output has correct size} -body {
    set large [string repeat "x" 1000]
    set result [::mcp::tools::_handle_large_output $large 500]
    string length [dict get $result content]
} -result 500

test output-3.3 {original size preserved} -body {
    set large [string repeat "x" 1000]
    set result [::mcp::tools::_handle_large_output $large 500]
    dict get $result original_size_bytes
} -result 1000

cleanupTests
```

### Phase 3 Verification Checklist

```bash
# 1. Verify tools module loads
cd mcp && tclsh -c '
    source lib/tools.tcl
    puts "Tools module loaded"
    puts "Registered tools: [llength [::mcp::tools::get_definitions]]"
'
# Expected: 14 tools (8 original + 6 new)

# 2. Run tool tests
cd mcp/tests/mock && tclsh test_tools_network.test
# Expected: All tests pass

# 3. Run full test suite
cd mcp/tests && ./run_all_tests.sh
# Expected: All tests pass

# 4. Verify tool definitions
tclsh -c '
    source lib/tools.tcl
    set defs [::mcp::tools::get_definitions]
    foreach def $defs {
        puts [dict get $def name]
    }
'
```

| Check | Expected Result | Status |
|-------|-----------------|--------|
| Tools module loads | No errors | ☐ |
| 14 tools registered | Count = 14 | ☐ |
| ssh_network_interfaces defined | In tool list | ☐ |
| ssh_network_routes defined | In tool list | ☐ |
| ssh_network_firewall defined | In tool list | ☐ |
| ssh_batch_commands defined | In tool list | ☐ |
| Tool tests pass | All pass | ☐ |
| Large output handler works | Truncation correct | ☐ |

---

## Phase 4: Advanced Network Tools

### Objective

Implement `ssh_network_qdisc`, `ssh_network_connectivity`, and `ssh_network_conntrack` with privacy mode.

### Duration: ~3 hours

### Step 4.1: Implement `tool_ssh_network_qdisc`

**File**: `mcp/lib/tools.tcl`
**Lines to Add**: ~50

```tcl
#=========================================================================
# ssh_network_qdisc (Lines 735-785)
#=========================================================================

proc tool_ssh_network_qdisc {args mcp_session_id} {
    if {![dict exists $args session_id]} {
        return [_tool_error "Missing required parameter: session_id"]
    }

    set session_id [dict get $args session_id]
    set interface [expr {[dict exists $args interface] ? [dict get $args interface] : ""}]
    set include_stats [expr {[dict exists $args include_stats] ? [dict get $args include_stats] : 0}]

    if {$include_stats eq "true"} { set include_stats 1 }

    set session [::mcp::session::get $session_id]
    if {$session eq {}} {
        return [_tool_error "Session not found: $session_id"]
    }

    if {![_verify_session_owner $session_id $mcp_session_id]} {
        return [_tool_error "Session not owned by this client"]
    }

    set spawn_id [dict get $session spawn_id]

    # Build command
    set cmd "tc -j"
    if {$include_stats} {
        set cmd "tc -js"
    }
    append cmd " qdisc show"
    if {$interface ne ""} {
        if {![regexp {^[a-zA-Z0-9@_-]+$} $interface]} {
            return [_tool_error "Invalid interface name"]
        }
        append cmd " dev $interface"
    }

    if {[catch {::mcp::security::validate_command $cmd} err]} {
        return [_tool_error "Command not permitted: $err"]
    }

    if {[catch {
        set output [::prompt::run $spawn_id $cmd]
    } err]} {
        return [_tool_error "Command execution failed: $err"]
    }

    return [dict create \
        content [list [dict create type "text" text [string trim $output]]] \
        timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1] \
    ]
}
```

### Step 4.2: Implement `tool_ssh_network_connectivity`

**File**: `mcp/lib/tools.tcl`
**Lines to Add**: ~100

```tcl
#=========================================================================
# ssh_network_connectivity (Lines 790-890)
# Reference: DESIGN_NETWORK_COMMANDS.md Section "ssh_network_connectivity"
#=========================================================================

proc tool_ssh_network_connectivity {args mcp_session_id} {
    if {![dict exists $args session_id]} {
        return [_tool_error "Missing required parameter: session_id"]
    }
    if {![dict exists $args target]} {
        return [_tool_error "Missing required parameter: target"]
    }

    set session_id [dict get $args session_id]
    set target [dict get $args target]
    set tests [expr {[dict exists $args tests] ? [dict get $args tests] : [list ping dns]}]
    set ping_count [expr {[dict exists $args ping_count] ? [dict get $args ping_count] : 3}]
    set traceroute_hops [expr {[dict exists $args traceroute_hops] ? [dict get $args traceroute_hops] : 10}]

    # Validate target (hostname or IP)
    if {![regexp {^[a-zA-Z0-9][a-zA-Z0-9.-]+$} $target]} {
        return [_tool_error "Invalid target: $target"]
    }

    # Enforce limits
    if {$ping_count > 5} { set ping_count 5 }
    if {$ping_count < 1} { set ping_count 1 }
    if {$traceroute_hops > 15} { set traceroute_hops 15 }
    if {$traceroute_hops < 1} { set traceroute_hops 1 }

    set session [::mcp::session::get $session_id]
    if {$session eq {}} {
        return [_tool_error "Session not found: $session_id"]
    }

    if {![_verify_session_owner $session_id $mcp_session_id]} {
        return [_tool_error "Session not owned by this client"]
    }

    set spawn_id [dict get $session spawn_id]
    set results [dict create target $target]

    # Run requested tests
    if {"dns" in $tests} {
        set cmd "dig +short $target"
        if {[catch {::mcp::security::validate_command $cmd}]} {
            dict set results dns [dict create error "Command not permitted"]
        } elseif {[catch {
            set output [::prompt::run $spawn_id $cmd]
        } err]} {
            dict set results dns [dict create error $err]
        } else {
            set addresses [split [string trim $output] "\n"]
            dict set results dns [dict create \
                resolved [expr {[llength $addresses] > 0}] \
                addresses $addresses \
            ]
        }
    }

    if {"ping" in $tests} {
        set cmd "ping -c $ping_count $target"
        if {[catch {::mcp::security::validate_command $cmd}]} {
            dict set results ping [dict create error "Command not permitted"]
        } elseif {[catch {
            set output [::prompt::run $spawn_id $cmd]
        } err]} {
            dict set results ping [dict create error $err]
        } else {
            # Parse ping output
            set reachable [string match "*bytes from*" $output]
            # Extract packet loss
            regexp {(\d+)% packet loss} $output _ loss_percent
            dict set results ping [dict create \
                reachable $reachable \
                output $output \
                loss_percent [expr {[info exists loss_percent] ? $loss_percent : 100}] \
            ]
        }
    }

    if {"traceroute" in $tests} {
        set cmd "traceroute -m $traceroute_hops $target"
        if {[catch {::mcp::security::validate_command $cmd}]} {
            dict set results traceroute [dict create error "Command not permitted"]
        } elseif {[catch {
            set output [::prompt::run $spawn_id $cmd]
        } err]} {
            dict set results traceroute [dict create error $err]
        } else {
            dict set results traceroute [dict create output $output]
        }
    }

    return [dict create \
        content [list [dict create type "text" text "Connectivity test results for $target"]] \
        results $results \
        timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1] \
    ]
}
```

### Step 4.3: Implement Privacy Filter

**File**: `mcp/lib/security.tcl`
**Location**: After rate limiting section
**Lines to Add**: ~40

```tcl
#=========================================================================
# PRIVACY FILTER (Lines 375-415)
# Reference: DESIGN_NETWORK_COMMANDS.md Section "Privacy Mode"
#=========================================================================

proc apply_privacy_filter {output privacy_level} {
    switch $privacy_level {
        "none" {
            return $output
        }
        "standard" {
            # Mask RFC1918 internal addresses (keep prefix for context)
            # 10.x.x.x, 172.16-31.x.x, 192.168.x.x
            set output [regsub -all {(10\.)[0-9]+\.[0-9]+} $output {\1x.x}]
            set output [regsub -all {(172\.(1[6-9]|2[0-9]|3[01])\.)[0-9]+\.[0-9]+} $output {\1x.x}]
            set output [regsub -all {(192\.168\.)[0-9]+\.[0-9]+} $output {\1x.x}]

            # Mask ephemeral ports (>32767)
            set output [regsub -all {:([3-6][0-9]{4})\b} $output {:xxxxx}]

            # Mask MAC addresses (keep OUI)
            set output [regsub -all {([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:)[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}} $output {\1xx:xx:xx}]

            return $output
        }
        "strict" {
            # Mask all IPs except loopback
            set output [regsub -all {(?!127\.0\.0\.)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+} $output {x.x.x.x}]

            # Mask all ports
            set output [regsub -all {:([0-9]+)\b} $output {:xxxxx}]

            # Mask all MAC addresses
            set output [regsub -all {[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}} $output {xx:xx:xx:xx:xx:xx}]

            return $output
        }
        default {
            return $output
        }
    }
}
```

### Step 4.4: Add Privacy Filter Tests

**File**: `mcp/tests/mock/test_security_network.test`
**Location**: Add at end
**Lines to Add**: ~50

```tcl
#===========================================================================
# PRIVACY FILTER TESTS
#===========================================================================

test privacy-30.0 {none mode returns unchanged} -body {
    set input "src=10.1.2.3 dst=8.8.8.8"
    ::mcp::security::apply_privacy_filter $input "none"
} -result "src=10.1.2.3 dst=8.8.8.8"

test privacy-30.1 {standard masks internal IPs} -body {
    set input "src=10.1.2.3 dst=8.8.8.8"
    set output [::mcp::security::apply_privacy_filter $input "standard"]
    expr {[string match "*10.x.x*" $output] && [string match "*8.8.8.8*" $output]}
} -result 1

test privacy-30.2 {standard masks 172.16.x.x} -body {
    set input "172.16.5.10"
    set output [::mcp::security::apply_privacy_filter $input "standard"]
    string match "*172.16.x.x*" $output
} -result 1

test privacy-30.3 {standard masks 192.168.x.x} -body {
    set input "192.168.1.100"
    set output [::mcp::security::apply_privacy_filter $input "standard"]
    string match "*192.168.x.x*" $output
} -result 1

test privacy-30.4 {standard masks ephemeral ports} -body {
    set input "sport=54321 dport=443"
    set output [::mcp::security::apply_privacy_filter $input "standard"]
    expr {[string match "*:xxxxx*" $output] && [string match "*:443*" $output]}
} -result 1

test privacy-30.5 {standard masks MAC addresses (keeps OUI)} -body {
    set input "52:54:00:12:34:56"
    set output [::mcp::security::apply_privacy_filter $input "standard"]
    string match "52:54:00:xx:xx:xx" $output
} -result 1

test privacy-30.6 {strict masks all IPs} -body {
    set input "src=10.1.2.3 dst=8.8.8.8"
    set output [::mcp::security::apply_privacy_filter $input "strict"]
    expr {[string match "*x.x.x.x*" $output]}
} -result 1

test privacy-30.7 {strict preserves loopback} -body {
    set input "127.0.0.1:8080"
    set output [::mcp::security::apply_privacy_filter $input "strict"]
    string match "*127.0.0.1*" $output
} -result 1
```

### Phase 4 Verification Checklist

```bash
# Run all network tests
cd mcp/tests/mock && tclsh test_security_network.test
cd mcp/tests/mock && tclsh test_tools_network.test

# Verify privacy filter
tclsh -c '
    source lib/security.tcl
    set input "src=10.1.2.3:54321 dst=8.8.8.8:443 mac=52:54:00:12:34:56"
    puts "Original: $input"
    puts "Standard: [::mcp::security::apply_privacy_filter $input standard]"
    puts "Strict:   [::mcp::security::apply_privacy_filter $input strict]"
'
```

| Check | Expected Result | Status |
|-------|-----------------|--------|
| ssh_network_qdisc implemented | Dispatches correctly | ☐ |
| ssh_network_connectivity implemented | Returns results dict | ☐ |
| Privacy filter standard mode | Masks 10.x.x.x | ☐ |
| Privacy filter strict mode | Masks all IPs | ☐ |
| Privacy tests pass | All pass | ☐ |

---

## Phase 5: Batch Execution

### Objective

Implement `ssh_batch_commands` with pool starvation prevention.

### Duration: ~2 hours

### Step 5.1: Implement `tool_ssh_batch_commands`

**File**: `mcp/lib/tools.tcl`
**Lines to Add**: ~80

```tcl
#=========================================================================
# ssh_batch_commands (Lines 895-975)
# Reference: DESIGN_NETWORK_COMMANDS.md Section "Option C: Batch Command Execution"
#=========================================================================

proc tool_ssh_batch_commands {args mcp_session_id} {
    if {![dict exists $args session_id]} {
        return [_tool_error "Missing required parameter: session_id"]
    }
    if {![dict exists $args commands]} {
        return [_tool_error "Missing required parameter: commands"]
    }

    set session_id [dict get $args session_id]
    set commands [dict get $args commands]
    set parallel [expr {[dict exists $args parallel] ? [dict get $args parallel] : 1}]
    set stop_on_error [expr {[dict exists $args stop_on_error] ? [dict get $args stop_on_error] : 0}]

    if {$parallel eq "true"} { set parallel 1 }
    if {$parallel eq "false"} { set parallel 0 }
    if {$stop_on_error eq "true"} { set stop_on_error 1 }
    if {$stop_on_error eq "false"} { set stop_on_error 0 }

    # POOL STARVATION PREVENTION: Max 5 commands per batch
    if {[llength $commands] > 5} {
        return [_tool_error "Batch size exceeds maximum (5). Split into multiple batches."]
    }
    if {[llength $commands] < 1} {
        return [_tool_error "At least one command required"]
    }

    set session [::mcp::session::get $session_id]
    if {$session eq {}} {
        return [_tool_error "Session not found: $session_id"]
    }

    if {![_verify_session_owner $session_id $mcp_session_id]} {
        return [_tool_error "Session not owned by this client"]
    }

    set spawn_id [dict get $session spawn_id]
    set start_time [clock milliseconds]
    set results [list]

    # Validate ALL commands first (fail fast)
    foreach cmd $commands {
        if {[catch {::mcp::security::validate_command $cmd} err]} {
            return [_tool_error "Command validation failed: $cmd - $err"]
        }
    }

    # Execute commands sequentially on this session
    # Note: True parallelism requires multiple sessions (Phase 5.2)
    foreach cmd $commands {
        set cmd_start [clock milliseconds]
        set success true
        set output ""
        set error_msg ""

        if {[catch {
            set output [::prompt::run $spawn_id $cmd]
        } err]} {
            set success false
            set error_msg $err

            if {$stop_on_error} {
                lappend results [dict create \
                    command $cmd \
                    success false \
                    error $error_msg \
                    duration_ms [expr {[clock milliseconds] - $cmd_start}] \
                ]
                break
            }
        }

        lappend results [dict create \
            command $cmd \
            success $success \
            output [expr {$success ? $output : ""}] \
            error [expr {$success ? "" : $error_msg}] \
            duration_ms [expr {[clock milliseconds] - $cmd_start}] \
        ]
    }

    set total_duration [expr {[clock milliseconds] - $start_time}]

    return [dict create \
        content [list [dict create type "text" text "Executed [llength $results] commands"]] \
        results $results \
        total_duration_ms $total_duration \
        parallel false \
        commands_executed [llength $results] \
    ]
}
```

### Step 5.2: Add Batch Execution Tests

**File**: `mcp/tests/mock/test_tools_network.test`
**Location**: Add to existing file
**Lines to Add**: ~40

```tcl
#===========================================================================
# BATCH COMMAND TESTS
#===========================================================================

test batch-10.0 {batch rejects empty commands} -body {
    set result [::mcp::tools::dispatch "ssh_batch_commands" \
        [dict create session_id "sess_123" commands [list]] "mcp_123"]
    dict get $result isError
} -result true

test batch-10.1 {batch rejects >5 commands} -body {
    set result [::mcp::tools::dispatch "ssh_batch_commands" \
        [dict create session_id "sess_123" commands [list a b c d e f]] "mcp_123"]
    string match "*exceeds maximum*" [dict get $result content 0 text]
} -result true

test batch-10.2 {batch validates all commands first} -body {
    # First command valid, second invalid - should fail immediately
    set result [::mcp::tools::dispatch "ssh_batch_commands" \
        [dict create session_id "sess_123" commands [list "hostname" "rm -rf /"]] "mcp_123"]
    dict get $result isError
} -result true
```

### Phase 5 Verification Checklist

```bash
# Run batch tests
cd mcp/tests/mock && tclsh test_tools_network.test

# Verify batch size limit
tclsh -c '
    source lib/tools.tcl
    set result [::mcp::tools::dispatch "ssh_batch_commands" \
        [dict create session_id "x" commands [list 1 2 3 4 5 6]] "mcp"]
    puts [dict get $result content 0 text]
'
# Expected: Error about max 5 commands
```

| Check | Expected Result | Status |
|-------|-----------------|--------|
| Batch rejects >5 commands | Error returned | ☐ |
| Batch validates all commands first | Fails on invalid | ☐ |
| Batch returns structured results | Results array | ☐ |
| Duration tracking works | duration_ms populated | ☐ |

---

## Phase 6: Diff and Compare Tools

### Objective

Implement `ssh_network_compare` for detecting network state changes.

### Duration: ~2 hours

### Step 6.1: Implement Snapshot Cache

**File**: `mcp/lib/tools.tcl`
**Location**: Add variable at namespace level
**Lines to Add**: ~20

```tcl
namespace eval ::mcp::tools {
    # ... existing variables ...

    # Snapshot cache for network compare
    # Key: session_id, Value: dict of {interfaces routes firewall timestamp}
    variable network_snapshots [dict create]

    proc _cache_snapshot {session_id scope data} {
        variable network_snapshots
        set timestamp [clock seconds]
        if {![dict exists $network_snapshots $session_id]} {
            dict set network_snapshots $session_id [dict create]
        }
        dict set network_snapshots $session_id $scope \
            [dict create data $data timestamp $timestamp]
    }

    proc _get_cached_snapshot {session_id scope} {
        variable network_snapshots
        if {[dict exists $network_snapshots $session_id $scope]} {
            return [dict get $network_snapshots $session_id $scope]
        }
        return {}
    }
}
```

### Step 6.2: Implement `tool_ssh_network_compare`

**File**: `mcp/lib/tools.tcl`
**Lines to Add**: ~100

```tcl
#=========================================================================
# ssh_network_compare (Lines 980-1080)
# Reference: DESIGN_NETWORK_COMMANDS.md Section "ssh_network_compare"
#=========================================================================

proc _def_ssh_network_compare {} {
    return [dict create \
        name "ssh_network_compare" \
        description "Compare current network state against a previous snapshot" \
        inputSchema [dict create \
            type "object" \
            properties [dict create \
                session_id [dict create type "string" description "Session ID"] \
                scope [dict create type "string" enum [list interfaces routes firewall all]] \
                baseline [dict create type "string" description "Previous snapshot JSON (optional)"] \
                format [dict create type "string" enum [list diff added_removed summary]] \
            ] \
            required [list session_id] \
        ] \
    ]
}

proc tool_ssh_network_compare {args mcp_session_id} {
    if {![dict exists $args session_id]} {
        return [_tool_error "Missing required parameter: session_id"]
    }

    set session_id [dict get $args session_id]
    set scope [expr {[dict exists $args scope] ? [dict get $args scope] : "all"}]
    set baseline [expr {[dict exists $args baseline] ? [dict get $args baseline] : ""}]
    set format [expr {[dict exists $args format] ? [dict get $args format] : "added_removed"}]

    set session [::mcp::session::get $session_id]
    if {$session eq {}} {
        return [_tool_error "Session not found: $session_id"]
    }

    if {![_verify_session_owner $session_id $mcp_session_id]} {
        return [_tool_error "Session not owned by this client"]
    }

    # Get current state
    set current_state [dict create]
    if {$scope eq "all" || $scope eq "interfaces"} {
        set iface_result [tool_ssh_network_interfaces \
            [dict create session_id $session_id] $mcp_session_id]
        if {![dict exists $iface_result isError]} {
            dict set current_state interfaces [dict get $iface_result raw_json]
        }
    }
    if {$scope eq "all" || $scope eq "routes"} {
        set route_result [tool_ssh_network_routes \
            [dict create session_id $session_id] $mcp_session_id]
        if {![dict exists $route_result isError]} {
            dict set current_state routes [dict get $route_result routes]
        }
    }

    # Get baseline (from parameter or cache)
    set baseline_state [dict create]
    set baseline_timestamp ""
    if {$baseline ne ""} {
        # Parse provided baseline JSON
        if {[catch {set baseline_state $baseline} err]} {
            return [_tool_error "Invalid baseline JSON: $err"]
        }
    } else {
        # Use cached snapshot
        set cached [_get_cached_snapshot $session_id $scope]
        if {$cached ne {}} {
            set baseline_state [dict get $cached data]
            set baseline_timestamp [clock format [dict get $cached timestamp] \
                -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1]
        }
    }

    # Cache current state for next comparison
    _cache_snapshot $session_id $scope $current_state

    # If no baseline, return current state with note
    if {$baseline_state eq {} || $baseline_state eq ""} {
        return [dict create \
            content [list [dict create type "text" text "No baseline found. Current state cached for future comparison."]] \
            current_state $current_state \
            changes_detected false \
            note "First call - baseline now cached" \
        ]
    }

    # Compare states
    set comparison [_compare_network_states $baseline_state $current_state $format]

    return [dict create \
        content [list [dict create type "text" text "Network comparison complete"]] \
        changes_detected [expr {[dict get $comparison added] ne {} || [dict get $comparison removed] ne {}}] \
        comparison $comparison \
        baseline_timestamp $baseline_timestamp \
        current_timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1] \
    ]
}

proc _compare_network_states {baseline current format} {
    # Simple diff: find keys in one but not other
    set added [list]
    set removed [list]

    # Compare as strings for now (full JSON diff would need json library)
    if {$baseline ne $current} {
        dict set added note "State changed"
        dict set removed note "From previous state"
    }

    return [dict create \
        added $added \
        removed $removed \
        format $format \
    ]
}
```

### Phase 6 Verification Checklist

| Check | Expected Result | Status |
|-------|-----------------|--------|
| ssh_network_compare defined | In tool list | ☐ |
| First call caches state | "baseline cached" message | ☐ |
| Second call compares | changes_detected field | ☐ |
| Explicit baseline works | Uses provided JSON | ☐ |

---

## Phase 7: MCP Server E2E Testing

### Objective

Add comprehensive end-to-end tests that exercise network commands through the full MCP server stack: HTTP → JSON-RPC → Security → Tools → SSH → Target. This ensures the integration works correctly, not just individual components.

### Duration: ~3 hours

### Step 7.1: Add Network Tests to TCL Agent E2E

**File**: `mcp/agent/e2e_test.tcl`
**Location**: After existing test functions (around line 350)
**Lines to Add**: ~200

```tcl
#=============================================================================
# Network Tool E2E Tests
# Reference: DESIGN_NETWORK_COMMANDS.md Section "MCP Server E2E Tests"
#=============================================================================

proc test_network_interfaces {} {
    puts ""
    puts "--- Test: Network Interfaces Tool ---"

    if {[catch {
        set result [::agent::mcp::call_tool "ssh_network_interfaces" \
            [dict create session_id $::session_id]]

        ::test::assert_not_empty $result "Network interfaces returns result"

        set text [::agent::mcp::extract_text $result]
        ::test::assert_contains $text "lo" "Contains loopback interface"

        if {[dict exists $result raw_json]} {
            ::test::pass "Returns raw_json for parsing"
        } else {
            ::test::fail "Returns raw_json" "Missing raw_json field"
        }

        if {[dict exists $result timestamp]} {
            ::test::pass "Includes timestamp"
        }

    } err]} {
        ::test::fail "Network interfaces tool" $err
    }
}

proc test_network_routes {} {
    puts ""
    puts "--- Test: Network Routes Tool ---"

    if {[catch {
        set result [::agent::mcp::call_tool "ssh_network_routes" \
            [dict create session_id $::session_id]]

        ::test::assert_not_empty $result "Network routes returns result"

        # Verify we have route data
        if {[dict exists $result routes]} {
            ::test::pass "Returns routes dict"
        }

    } err]} {
        ::test::fail "Network routes tool" $err
    }
}

proc test_network_firewall {} {
    puts ""
    puts "--- Test: Network Firewall Tool ---"

    if {[catch {
        set result [::agent::mcp::call_tool "ssh_network_firewall" \
            [dict create session_id $::session_id format "auto"]]

        ::test::assert_not_empty $result "Network firewall returns result"

        if {[dict exists $result format]} {
            set fw_format [dict get $result format]
            ::test::assert {$fw_format in {nft iptables}} "Detected firewall format: $fw_format"
        }

    } err]} {
        # May fail if no firewall installed
        ::test::skip "Network firewall tool" "Firewall may not be installed: $err"
    }
}

proc test_network_qdisc {} {
    puts ""
    puts "--- Test: Network QDisc Tool ---"

    if {[catch {
        set result [::agent::mcp::call_tool "ssh_network_qdisc" \
            [dict create session_id $::session_id]]

        ::test::assert_not_empty $result "Network qdisc returns result"

        set text [::agent::mcp::extract_text $result]
        # Should have at least default qdisc
        ::test::assert {[string length $text] > 5} "QDisc output is not empty"

    } err]} {
        ::test::fail "Network qdisc tool" $err
    }
}

proc test_network_connectivity {} {
    puts ""
    puts "--- Test: Network Connectivity Tool ---"

    if {[catch {
        # Test ping to localhost (should always work)
        set result [::agent::mcp::call_tool "ssh_network_connectivity" \
            [dict create \
                session_id $::session_id \
                target "127.0.0.1" \
                tests [list "ping"] \
                ping_count 2]]

        ::test::assert_not_empty $result "Connectivity test returns result"

        if {[dict exists $result results]} {
            set results [dict get $result results]
            if {[dict exists $results ping]} {
                set ping_result [dict get $results ping]
                if {[dict exists $ping_result reachable]} {
                    ::test::assert_eq [dict get $ping_result reachable] 1 \
                        "Localhost is reachable via ping"
                }
            }
        }

    } err]} {
        ::test::fail "Connectivity tool" $err
    }
}

proc test_batch_commands {} {
    puts ""
    puts "--- Test: Batch Commands Tool ---"

    if {[catch {
        set result [::agent::mcp::call_tool "ssh_batch_commands" \
            [dict create \
                session_id $::session_id \
                commands [list "hostname" "uname -r" "id"]]]

        ::test::assert_not_empty $result "Batch commands returns result"

        if {[dict exists $result results]} {
            set results [dict get $result results]
            ::test::assert_eq [llength $results] 3 "Executed 3 commands"

            set all_success 1
            foreach cmd_result $results {
                if {[dict exists $cmd_result success] && ![dict get $cmd_result success]} {
                    set all_success 0
                }
            }
            ::test::assert $all_success "All batch commands succeeded"
        }

        if {[dict exists $result total_duration_ms]} {
            ::test::pass "Reports total duration"
        }

    } err]} {
        ::test::fail "Batch commands tool" $err
    }
}

proc test_batch_limit_enforced {} {
    puts ""
    puts "--- Test: Batch Size Limit ---"

    # Try to submit 6 commands (should fail)
    set caught_error 0
    if {[catch {
        set result [::agent::mcp::call_tool "ssh_batch_commands" \
            [dict create \
                session_id $::session_id \
                commands [list "cmd1" "cmd2" "cmd3" "cmd4" "cmd5" "cmd6"]]]

        if {[dict exists $result isError] && [dict get $result isError]} {
            set caught_error 1
        }
    } err]} {
        set caught_error 1
    }

    if {$caught_error} {
        ::test::pass "Batch size limit correctly enforced (>5 rejected)"
    } else {
        ::test::fail "Batch size limit" "Should reject >5 commands"
    }
}

proc test_ip_modification_blocked {} {
    puts ""
    puts "--- Test: IP Modification Blocked ---"

    # This MUST fail - it's a security test
    set blocked 0
    if {[catch {
        set result [::agent::mcp::call_tool "ssh_run_command" \
            [dict create \
                session_id $::session_id \
                command "ip link set eth0 down"]]

        if {[dict exists $result isError] && [dict get $result isError]} {
            set blocked 1
        }
    } err]} {
        set blocked 1
    }

    if {$blocked} {
        ::test::pass "ip link set correctly BLOCKED"
    } else {
        ::test::fail "CRITICAL: ip link set SHOULD BE BLOCKED" \
            "This is a security vulnerability!"
    }
}

proc test_ethtool_flash_blocked {} {
    puts ""
    puts "--- Test: Ethtool Flash Blocked ---"

    set blocked 0
    if {[catch {
        set result [::agent::mcp::call_tool "ssh_run_command" \
            [dict create \
                session_id $::session_id \
                command "ethtool -f eth0 firmware.bin"]]

        if {[dict exists $result isError] && [dict get $result isError]} {
            set blocked 1
        }
    } err]} {
        set blocked 1
    }

    if {$blocked} {
        ::test::pass "ethtool -f correctly BLOCKED"
    } else {
        ::test::fail "CRITICAL: ethtool -f SHOULD BE BLOCKED" \
            "This could flash firmware!"
    }
}

proc test_ping_flood_blocked {} {
    puts ""
    puts "--- Test: Ping Flood Blocked ---"

    set blocked 0
    if {[catch {
        set result [::agent::mcp::call_tool "ssh_run_command" \
            [dict create \
                session_id $::session_id \
                command "ping -f 8.8.8.8"]]

        if {[dict exists $result isError] && [dict get $result isError]} {
            set blocked 1
        }
    } err]} {
        set blocked 1
    }

    if {$blocked} {
        ::test::pass "ping -f (flood) correctly BLOCKED"
    } else {
        ::test::fail "CRITICAL: ping flood SHOULD BE BLOCKED"
    }
}

# Add to run_all_tests proc:
proc run_network_tests {} {
    puts ""
    puts "=============================================="
    puts "Network Tool E2E Tests"
    puts "=============================================="

    test_network_interfaces
    test_network_routes
    test_network_firewall
    test_network_qdisc
    test_network_connectivity
    test_batch_commands
    test_batch_limit_enforced

    puts ""
    puts "=============================================="
    puts "Network Security E2E Tests"
    puts "=============================================="

    test_ip_modification_blocked
    test_ethtool_flash_blocked
    test_ping_flood_blocked
}
```

### Step 7.2: Update e2e_test.tcl Main Procedure

**File**: `mcp/agent/e2e_test.tcl`
**Location**: In main procedure (around line 400)
**Change**: Add call to `run_network_tests`

```tcl
# In the main proc, after existing tests:
proc main {} {
    # ... existing setup ...

    # Existing tests
    test_health_check
    test_initialize
    test_tools_list
    test_ssh_connect
    test_ssh_hostname
    test_ssh_run_command
    test_ssh_cat_file

    # NEW: Network tool tests
    run_network_tests

    # Cleanup
    test_ssh_disconnect

    # Summary
    return [::test::summary]
}
```

### Step 7.3: Create Network E2E Bash Test

**File**: `mcp/tests/real/test_network_e2e.sh`
**Lines**: ~200

```bash
#!/bin/bash
# test_network_e2e.sh - Network Commands E2E Tests
#
# Tests network tools through the MCP server with real SSH connections.
# Reference: DESIGN_NETWORK_COMMANDS.md Section "Bash E2E Tests"
#
# Requires:
#   SSH_HOST - Target hostname or IP
#   PASSWORD - SSH password
#   SSH_USER - SSH username (optional, defaults to $USER)
#
# Usage: ./test_network_e2e.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=mcp_client.sh
source "$SCRIPT_DIR/mcp_client.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
SKIP=0

# Check prerequisites
check_prereqs() {
    if [ -z "$SSH_HOST" ] || [ -z "$PASSWORD" ]; then
        echo -e "${RED}ERROR: SSH_HOST and PASSWORD must be set${NC}"
        exit 1
    fi

    SSH_USER="${SSH_USER:-$USER}"

    # Check server
    if ! mcp_health > /dev/null 2>&1; then
        echo -e "${YELLOW}Starting MCP server...${NC}"
        cd "$SCRIPT_DIR/../.."
        ./server.tcl --port "${MCP_PORT:-3000}" &
        MCP_PID=$!
        trap 'kill $MCP_PID 2>/dev/null' EXIT
        sleep 2
    fi
}

# Setup SSH session
setup() {
    check_prereqs
    mcp_initialize

    SSH_SESSION_ID=$(mcp_ssh_connect "$SSH_HOST" "$SSH_USER" "$PASSWORD" | jq -r '.session_id // empty')
    if [ -z "$SSH_SESSION_ID" ]; then
        echo -e "${RED}Failed to establish SSH session${NC}"
        exit 1
    fi
    echo "SSH Session: $SSH_SESSION_ID"
}

# Cleanup
teardown() {
    if [ -n "$SSH_SESSION_ID" ]; then
        mcp_ssh_disconnect "$SSH_SESSION_ID" > /dev/null 2>&1 || true
    fi
}

trap teardown EXIT

#===========================================================================
# NETWORK INSPECTION TESTS (should pass)
#===========================================================================

test_ip_addr_show() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip -j addr show")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ip -j addr show"
        echo "  Error: $response"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ip -j addr show"
        ((PASS++))
    fi
}

test_ip_route_show() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip -j route show")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ip -j route show"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ip -j route show"
        ((PASS++))
    fi
}

test_ip_link_show() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip -j -d link show")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ip -j -d link show"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ip -j -d link show"
        ((PASS++))
    fi
}

test_tc_qdisc_show() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc -j qdisc show")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: tc -j qdisc show"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: tc -j qdisc show"
        ((PASS++))
    fi
}

test_ping_within_limit() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -c 3 127.0.0.1")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ping -c 3 (within limit)"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ping -c 3 127.0.0.1"
        ((PASS++))
    fi
}

test_traceroute_within_limit() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "traceroute -m 5 127.0.0.1" 2>&1 || true)

    # May not be installed
    if [[ "$response" =~ "not found" ]] || [[ "$response" =~ "command not found" ]]; then
        echo -e "${YELLOW}SKIP${NC}: traceroute not installed"
        ((SKIP++))
    elif has_error "$response"; then
        echo -e "${RED}FAIL${NC}: traceroute -m 5"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: traceroute -m 5 127.0.0.1"
        ((PASS++))
    fi
}

test_dig_simple() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "dig +short localhost" 2>&1 || true)

    if [[ "$response" =~ "not found" ]]; then
        echo -e "${YELLOW}SKIP${NC}: dig not installed"
        ((SKIP++))
    elif has_error "$response"; then
        echo -e "${RED}FAIL${NC}: dig +short localhost"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: dig +short localhost"
        ((PASS++))
    fi
}

test_ethtool_stats() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -S lo" 2>&1 || true)

    # lo may not support stats
    if [[ "$response" =~ "no stats" ]] || [[ "$response" =~ "not found" ]]; then
        echo -e "${YELLOW}SKIP${NC}: ethtool -S (not supported on lo)"
        ((SKIP++))
    elif has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ethtool -S lo"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ethtool -S lo"
        ((PASS++))
    fi
}

test_nft_list() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "nft list tables" 2>&1 || true)

    if [[ "$response" =~ "not found" ]]; then
        echo -e "${YELLOW}SKIP${NC}: nft not installed"
        ((SKIP++))
    elif has_error "$response"; then
        echo -e "${RED}FAIL${NC}: nft list tables"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: nft list tables"
        ((PASS++))
    fi
}

test_batch_commands() {
    local response
    response=$(mcp_call_tool "ssh_batch_commands" "{
        \"session_id\": \"$SSH_SESSION_ID\",
        \"commands\": [\"hostname\", \"uname -r\", \"id\"]
    }")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: batch commands"
        ((FAIL++))
    else
        local count
        count=$(echo "$response" | jq -r '.results | length // 0')
        if [ "$count" -eq 3 ]; then
            echo -e "${GREEN}PASS${NC}: batch commands (3 results)"
            ((PASS++))
        else
            echo -e "${RED}FAIL${NC}: batch commands (expected 3, got $count)"
            ((FAIL++))
        fi
    fi
}

#===========================================================================
# MAIN
#===========================================================================

echo ""
echo "=============================================="
echo "Network Commands E2E Tests"
echo "=============================================="
echo ""

setup

echo "--- Inspection Commands (should PASS) ---"
echo ""

test_ip_addr_show
test_ip_route_show
test_ip_link_show
test_tc_qdisc_show
test_ping_within_limit
test_traceroute_within_limit
test_dig_simple
test_ethtool_stats
test_nft_list
test_batch_commands

echo ""
echo "=============================================="
echo "Summary"
echo "=============================================="
echo ""
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo -e "Skipped: ${YELLOW}$SKIP${NC}"
echo ""

if [ $FAIL -gt 0 ]; then
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

echo -e "${GREEN}SUCCESS${NC}"
exit 0
```

### Step 7.4: Add Network Security E2E Tests

**File**: `mcp/tests/real/test_security_e2e.sh`
**Location**: Add after existing security tests
**Lines to Add**: ~100

```bash
#===========================================================================
# NETWORK COMMAND SECURITY TESTS
# Reference: DESIGN_NETWORK_COMMANDS.md
#===========================================================================

run_network_security_tests() {
    echo ""
    echo "=== Network Command Security Tests ==="
    echo ""

    local response

    # ip modifications MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip link set eth0 down")
    expect_blocked "ip link set (interface down)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip link set lo up")
    expect_blocked "ip link set (even on lo)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip addr add 10.0.0.1/24 dev eth0")
    expect_blocked "ip addr add" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip addr del 10.0.0.1/24 dev eth0")
    expect_blocked "ip addr del" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip route add default via 10.0.0.1")
    expect_blocked "ip route add" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip route del 10.0.0.0/24")
    expect_blocked "ip route del" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip route flush table main")
    expect_blocked "ip route flush" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip neigh add 10.0.0.1 lladdr aa:bb:cc:dd:ee:ff dev eth0")
    expect_blocked "ip neigh add" "$response"

    # tc modifications MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc qdisc add dev eth0 root netem delay 100ms")
    expect_blocked "tc qdisc add" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc qdisc del dev eth0 root")
    expect_blocked "tc qdisc del" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc qdisc change dev eth0 root netem delay 50ms")
    expect_blocked "tc qdisc change" "$response"

    # nft modifications MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "nft add table inet test")
    expect_blocked "nft add table" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "nft delete table inet test")
    expect_blocked "nft delete table" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "nft flush ruleset")
    expect_blocked "nft flush ruleset" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "nft add chain inet filter input")
    expect_blocked "nft add chain" "$response"

    # iptables modifications MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "iptables -A INPUT -j DROP")
    expect_blocked "iptables -A (append)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "iptables -D INPUT 1")
    expect_blocked "iptables -D (delete)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "iptables -F")
    expect_blocked "iptables -F (flush)" "$response"

    # ethtool dangerous flags MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -f eth0 firmware.bin")
    expect_blocked "ethtool -f (firmware flash)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -E eth0")
    expect_blocked "ethtool -E (EEPROM write)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -e eth0")
    expect_blocked "ethtool -e (EEPROM read)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -W eth0")
    expect_blocked "ethtool -W (wake-on-lan)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -s eth0 speed 1000")
    expect_blocked "ethtool -s (speed set)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -K eth0 tso on")
    expect_blocked "ethtool -K (offload set)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -A eth0 rx on")
    expect_blocked "ethtool -A (pause set)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -G eth0 rx 4096")
    expect_blocked "ethtool -G (ring set)" "$response"

    # Ping abuse MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -f 8.8.8.8")
    expect_blocked "ping -f (flood)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -c 6 8.8.8.8")
    expect_blocked "ping -c 6 (over limit)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -c 100 8.8.8.8")
    expect_blocked "ping -c 100 (way over limit)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping 8.8.8.8")
    expect_blocked "ping without -c (infinite)" "$response"

    # Traceroute abuse MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "traceroute -m 16 google.com")
    expect_blocked "traceroute -m 16 (over limit)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "traceroute google.com")
    expect_blocked "traceroute without -m (default hops)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "traceroute -g 10.0.0.1 google.com")
    expect_blocked "traceroute -g (source route)" "$response"

    # DNS abuse MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "dig AXFR example.com")
    expect_blocked "dig AXFR (zone transfer)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "dig -x 8.8.8.8")
    expect_blocked "dig -x (reverse lookup)" "$response"

    # Verify inspection commands still work
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip -j addr show")
    expect_success "ip -j addr show (inspection)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc -j qdisc show")
    expect_success "tc -j qdisc show (inspection)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -c 3 127.0.0.1")
    expect_success "ping -c 3 (within limit)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -i lo" 2>&1 || true)
    if [[ ! "$response" =~ "not found" ]]; then
        expect_success "ethtool -i (driver info)" "$response"
    fi
}

# Add to main test runner
# In the main() function, add:
# run_network_security_tests
```

### Step 7.5: Update Test Runner

**File**: `mcp/tests/run_all_tests.sh`
**Location**: In real tests section (around line 105)
**Lines to Add**: ~15

```bash
# Add after test_security_e2e.sh section:

echo ""
echo "Running test_network_e2e.sh..."
if [ -f "$SCRIPT_DIR/real/test_network_e2e.sh" ]; then
    if ./real/test_network_e2e.sh; then
        REAL_PASS=$((REAL_PASS + 1))
        echo -e "${GREEN}Network E2E tests passed${NC}"
    else
        REAL_FAIL=$((REAL_FAIL + 1))
        echo -e "${RED}Network E2E tests failed${NC}"
    fi
fi
```

### Phase 7 Verification Checklist

```bash
# 1. Run TCL E2E tests (requires 3-VM setup)
tclsh mcp/agent/e2e_test.tcl --mcp-host 10.178.0.10 --target-host 10.178.0.20

# 2. Run bash network E2E tests
SSH_HOST=10.178.0.20 PASSWORD=testpass ./mcp/tests/real/test_network_e2e.sh

# 3. Run security E2E tests
SSH_HOST=10.178.0.20 PASSWORD=testpass ./mcp/tests/real/test_security_e2e.sh

# 4. Run full test suite
./mcp/tests/run_all_tests.sh --all
```

| Check | Expected Result | Status |
|-------|-----------------|--------|
| e2e_test.tcl updated | Network tests added | ☐ |
| test_network_e2e.sh created | ~200 lines | ☐ |
| test_security_e2e.sh updated | Network security tests added | ☐ |
| TCL E2E tests pass | All network tests pass | ☐ |
| Bash E2E tests pass | All pass or skip (missing tools) | ☐ |
| Security E2E tests pass | All dangerous commands blocked | ☐ |
| ip link set blocked via MCP | Returns error | ☐ |
| ethtool -f blocked via MCP | Returns error | ☐ |
| ping -c 3 works via MCP | Returns success | ☐ |
| batch commands work via MCP | Returns 3 results | ☐ |

---

## Phase 8: VM Test Infrastructure

### Objective

Update Nix VM configuration to support network command testing with proper network namespaces, traffic control, and firewall rules.

### Duration: ~3 hours

### Step 8.1: Update Target VM with Network Testing Infrastructure

**File**: `nix/ssh-target-vm.nix`
**Location**: Add to the module configuration
**Lines to Add**: ~100

```nix
# Add after line 100 in the module configuration

# ─── Network Command Testing Infrastructure ─────────────────────
# Reference: DESIGN_NETWORK_COMMANDS.md Section "VM Test Infrastructure"

# Install network diagnostic tools
environment.systemPackages = with pkgs; [
  iproute2
  ethtool
  nftables
  iptables
  conntrack-tools
  bridge-utils
  bind.dnsutils    # dig, nslookup, host
  traceroute
  mtr
  iputils          # ping
  tcpdump
];

# Enable nftables
networking.nftables = {
  enable = true;
  ruleset = ''
    table inet test_filter {
      chain input {
        type filter hook input priority 0; policy accept;
        # Test rules for inspection
        counter comment "test input counter"
      }
      chain output {
        type filter hook output priority 0; policy accept;
        counter comment "test output counter"
      }
    }
    table inet test_nat {
      chain prerouting {
        type nat hook prerouting priority 0;
      }
      chain postrouting {
        type nat hook postrouting priority 0;
      }
    }
  '';
};

# Enable connection tracking
boot.kernelModules = [ "nf_conntrack" ];

# Create test network namespace
systemd.services.setup-test-netns = {
  description = "Create test network namespace";
  wantedBy = ["multi-user.target"];
  after = ["network.target"];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
  script = ''
    # Create namespace
    ${pkgs.iproute2}/bin/ip netns add testns || true

    # Create veth pair
    ${pkgs.iproute2}/bin/ip link add veth-host type veth peer name veth-ns || true
    ${pkgs.iproute2}/bin/ip link set veth-ns netns testns || true

    # Configure host side
    ${pkgs.iproute2}/bin/ip addr add 10.200.0.1/24 dev veth-host || true
    ${pkgs.iproute2}/bin/ip link set veth-host up || true

    # Configure namespace side
    ${pkgs.iproute2}/bin/ip netns exec testns ip addr add 10.200.0.2/24 dev veth-ns || true
    ${pkgs.iproute2}/bin/ip netns exec testns ip link set veth-ns up || true
    ${pkgs.iproute2}/bin/ip netns exec testns ip link set lo up || true
  '';
};

# Create dummy interface for flap testing
systemd.services.setup-test-interfaces = {
  description = "Create test interfaces";
  wantedBy = ["multi-user.target"];
  after = ["network.target"];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
  script = ''
    # Dummy interface for testing
    ${pkgs.iproute2}/bin/ip link add dummy0 type dummy || true
    ${pkgs.iproute2}/bin/ip addr add 10.99.0.1/24 dev dummy0 || true
    ${pkgs.iproute2}/bin/ip link set dummy0 up || true

    # Bridge for testing
    ${pkgs.iproute2}/bin/ip link add testbr0 type bridge || true
    ${pkgs.iproute2}/bin/ip link set testbr0 up || true
  '';
};

# Traffic control for testing
systemd.services.setup-tc = {
  description = "Setup traffic control for testing";
  wantedBy = ["multi-user.target"];
  after = ["setup-test-interfaces.service"];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
  script = ''
    # Add test qdisc
    ${pkgs.iproute2}/bin/tc qdisc add dev dummy0 root netem delay 10ms || true
  '';
};
```

### Step 8.2: Create Integration Test Script

**File**: `nix/tests/network-commands-test.nix`
**Lines**: ~150

```nix
# nix/tests/network-commands-test.nix
#
# Integration tests for network commands
{
  pkgs,
  lib,
  ...
}:
{
  name = "network-commands-integration";

  nodes = {
    target = { config, pkgs, ... }: {
      # Use the target VM configuration
      imports = [ ../ssh-target-vm.nix ];
    };

    client = { config, pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        tcl-9_0
        curl
        jq
      ];
    };
  };

  testScript = ''
    start_all()

    # Wait for target to be ready
    target.wait_for_unit("multi-user.target")
    target.wait_for_unit("setup-test-netns.service")
    target.wait_for_unit("setup-tc.service")

    # Test 1: ip commands work
    target.succeed("ip -j addr show")
    target.succeed("ip -j route show")
    target.succeed("ip -j link show")
    target.succeed("ip netns list")

    # Test 2: ethtool works
    target.succeed("ethtool dummy0 || true")
    target.succeed("ethtool -S dummy0 || true")

    # Test 3: tc commands work
    target.succeed("tc -j qdisc show")
    target.succeed("tc qdisc show dev dummy0")

    # Test 4: nft commands work
    target.succeed("nft -j list ruleset")
    target.succeed("nft list tables")

    # Test 5: Network namespace works
    target.succeed("ip netns exec testns ip addr show")

    # Test 6: Bridge commands work
    target.succeed("bridge link show || true")

    # Test 7: Connectivity tools work
    target.succeed("ping -c 1 127.0.0.1")
    target.succeed("dig +short localhost || true")

    # Test 8: conntrack works (may be empty)
    target.succeed("conntrack -L || true")

    print("All network command tests passed!")
  '';
}
```

### Step 8.3: Update flake.nix

**File**: `flake.nix`
**Location**: Add to checks section
**Lines to Add**: ~10

```nix
# In the checks section, add:
network-commands = import ./nix/tests/network-commands-test.nix {
  inherit pkgs lib;
};
```

### Phase 8 Verification Checklist

```bash
# Build and test VM
nix build .#checks.x86_64-linux.network-commands

# Manual VM verification (if TAP networking available)
sudo nix run .#ssh-network-setup
nix build .#ssh-target-vm-tap-debug && ./result/bin/microvm-run &

# Wait for boot, then test
ssh testuser@10.178.0.20 -p 2222 "ip -j addr show"
ssh testuser@10.178.0.20 -p 2222 "tc -j qdisc show"
ssh testuser@10.178.0.20 -p 2222 "nft -j list ruleset"
ssh testuser@10.178.0.20 -p 2222 "ip netns list"
```

| Check | Expected Result | Status |
|-------|-----------------|--------|
| VM builds successfully | nix build completes | ☐ |
| ip commands work in VM | JSON output | ☐ |
| tc commands work | qdisc listed | ☐ |
| nft commands work | ruleset shown | ☐ |
| Network namespace exists | testns accessible | ☐ |
| Dummy interface exists | dummy0 listed | ☐ |
| Bridge interface exists | testbr0 listed | ☐ |
| Integration test passes | All assertions pass | ☐ |

---

## Phase 9: Documentation and Final Verification

### Objective

Update documentation and run complete test suite.

### Duration: ~1 hour

### Step 9.1: Update README.md

**File**: `README.md`
**Location**: In MCP Tools table (around line 155)
**Lines to Add**: ~20

Add to the MCP Tools table:

```markdown
| `ssh_network_interfaces` | List network interfaces with state and stability info |
| `ssh_network_routes` | Show routing tables |
| `ssh_network_firewall` | Show firewall rules (nftables/iptables) |
| `ssh_network_qdisc` | Show traffic control qdiscs |
| `ssh_network_connectivity` | Test connectivity (ping/dns/traceroute) |
| `ssh_network_compare` | Compare network state changes |
| `ssh_batch_commands` | Execute multiple commands (max 5) |
```

### Step 9.2: Update CLAUDE.md

**File**: `CLAUDE.md`
**Location**: Add new section after MCP Security Model
**Lines to Add**: ~30

```markdown
## Network Commands

The MCP server supports network inspection commands for system administration:

### Allowed Commands
- `ip -j link/addr/route/rule/neigh show` - Interface and routing info (JSON)
- `ethtool -S/-i/-k <iface>` - Interface stats (read-only flags only)
- `tc -j qdisc/class/filter show` - Traffic control
- `nft -j list ruleset/tables` - Firewall rules
- `ping -c [1-5]`, `traceroute -m [1-15]` - Connectivity tests
- `dig`, `nslookup`, `host` - DNS queries

### Blocked Commands
- Any modification: `ip link set`, `tc add`, `nft add`, etc.
- Dangerous ethtool flags: `-E`, `-f`, `-W` (hardware modification)
- Unlimited ping/traceroute (max 5 packets, 15 hops)
- DNS zone transfers, reverse lookups

### High-Level Tools
- `ssh_network_interfaces` - Interfaces with flap detection
- `ssh_network_routes` - Routing tables
- `ssh_network_firewall` - Auto-detects nft/iptables
- `ssh_batch_commands` - Up to 5 commands per batch
```

### Step 9.3: Final Test Suite Run

```bash
# Run complete test suite
cd mcp/tests && ./run_all_tests.sh

# Run CLI tests
cd tests && ./run_all_tests.sh

# Run shellcheck
./tests/run_shellcheck.sh

# Run Nix integration tests
nix build .#checks.x86_64-linux.integration
nix build .#checks.x86_64-linux.network-commands

# Format check
nix fmt --check
```

### Phase 9 Verification Checklist

| Check | Expected Result | Status |
|-------|-----------------|--------|
| README updated | New tools documented | ☐ |
| CLAUDE.md updated | Network section added | ☐ |
| MCP tests pass | 535+ tests (355 + 180 new) | ☐ |
| CLI tests pass | 62 tests | ☐ |
| Shellcheck passes | 0 warnings | ☐ |
| Integration tests pass | All checks green | ☐ |
| Nix format check | No changes needed | ☐ |

---

## Summary

### Total New Files

| File | Lines | Purpose |
|------|-------|---------|
| `mcp/tests/mock/test_security_network.test` | ~450 | Security pattern unit tests |
| `mcp/tests/mock/test_tools_network.test` | ~250 | Tool implementation unit tests |
| `mcp/tests/real/test_network_e2e.sh` | ~200 | Network command E2E tests |
| `nix/tests/network-commands-test.nix` | ~150 | VM integration tests |

### Total Modified Files

| File | Changes | Purpose |
|------|---------|---------|
| `mcp/lib/security.tcl` | +115 lines | Allowlist/blocklist patterns, privacy filter |
| `mcp/lib/tools.tcl` | +550 lines | 7 new tools, large output handler |
| `mcp/agent/e2e_test.tcl` | +200 lines | Network tool E2E tests |
| `mcp/tests/real/test_security_e2e.sh` | +100 lines | Network security E2E tests |
| `mcp/tests/run_all_tests.sh` | +15 lines | Network E2E test integration |
| `nix/ssh-target-vm.nix` | +100 lines | Network test infrastructure |
| `README.md` | +20 lines | Documentation |
| `CLAUDE.md` | +30 lines | AI guidance |
| `flake.nix` | +10 lines | New test target |

### Test Count Summary

| Category | Tests |
|----------|-------|
| Existing MCP mock tests | 355 |
| New security network unit tests | ~100 |
| New tool unit tests | ~50 |
| New privacy filter tests | ~15 |
| New batch tests | ~15 |
| **New TCL E2E tests** | ~15 |
| **New Bash E2E tests** | ~10 |
| **New Security E2E tests** | ~25 |
| VM integration tests | ~10 |
| **Total** | **~595** |

### Test Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                         TEST PYRAMID                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│    ┌─────────────────────────────────────────────────────────────┐  │
│    │              VM Integration Tests (~10)                     │  │
│    │         nix build .#checks.x86_64-linux.network-commands    │  │
│    └─────────────────────────────────────────────────────────────┘  │
│                              ▲                                      │
│    ┌─────────────────────────────────────────────────────────────┐  │
│    │                  E2E Tests (~50)                            │  │
│    │   TCL Agent (e2e_test.tcl) + Bash (test_network_e2e.sh)     │  │
│    │   + Security (test_security_e2e.sh)                         │  │
│    └─────────────────────────────────────────────────────────────┘  │
│                              ▲                                      │
│    ┌─────────────────────────────────────────────────────────────┐  │
│    │                 Unit/Mock Tests (~180)                      │  │
│    │   test_security_network.test + test_tools_network.test      │  │
│    └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Definition of Done

- [ ] All 9 phases completed
- [ ] All verification checklists passed
- [ ] Unit tests: 535+ tests passing
- [ ] E2E tests: 50+ tests passing
- [ ] VM integration: All checks green
- [ ] Shellcheck: 0 warnings
- [ ] Nix format: clean
- [ ] Documentation updated
- [ ] No security regressions
- [ ] CRITICAL: All modification commands blocked via MCP
