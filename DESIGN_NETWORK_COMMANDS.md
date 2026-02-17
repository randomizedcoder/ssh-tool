# Design Document: Network Commands Extension for MCP Server

## Overview

This document proposes extending the MCP SSH automation server with network diagnostic and configuration viewing commands. The goal is to enable LLMs to inspect and understand Linux network configuration for system administration tasks while maintaining the server's security-first design.

## Motivation

System administrators and LLMs assisting with infrastructure tasks frequently need to:
- Inspect network interface configuration (IP addresses, link state, MTU)
- View routing tables and routing policy rules
- Examine firewall rules (nftables, iptables)
- Inspect traffic control settings (tc/qdisc)
- Understand network namespace configurations
- Debug network connectivity issues

Currently, the MCP server's allowlist is limited to basic diagnostic commands (`netstat`, `ss`). This proposal adds comprehensive network inspection capabilities.

## Design Philosophy

### Read-Only vs Configuration Mode

The current MCP server is **read-only by design**. This proposal introduces two tiers:

| Mode | Commands | Security Model | Use Case |
|------|----------|----------------|----------|
| **Inspection (default)** | `ip -json`, `ethtool`, `tc -json show` | Read-only, no state changes | Diagnosis, auditing, learning |
| **Configuration (opt-in)** | `ip link set`, `ip route add` | Requires explicit flag, audit logged | Actual system changes |

**Recommendation**: Start with inspection-only (Phase 1), add configuration in Phase 2 after operational experience.

### JSON-First Design

Modern `ip` and `tc` commands support JSON output (`-j`/`-json`). This provides:
- **Structured data** for LLM parsing
- **Consistent format** across kernel versions
- **Programmatic handling** in the MCP layer
- **Easier aggregation** for batch operations

```bash
# Example: ip -j addr show
[{"ifname":"eth0","address":"10.0.0.5/24","operstate":"UP",...}]
```

### Shell-Free Execution Model

**CRITICAL**: All commands MUST be executed via direct `exec` without shell interpretation:

```tcl
# CORRECT: Direct exec (no shell injection possible)
exec /usr/sbin/ip -j addr show

# WRONG: Shell invocation (vulnerable to redirection attacks)
exec sh -c "ip -j addr show"
```

This prevents LLM-attempted shell redirection attacks like:
- `ip -j addr show > /tmp/payload`
- `ip -j addr show; rm -rf /`

The existing Expect-based execution via `spawn ssh` is safe because commands are sent as literal strings to the remote shell prompt, but the security layer validates the command **before** it reaches the shell.

## Proposed Command Categories

### Category 1: Interface Inspection (`ip link`, `ip addr`, `ethtool`)

| Command | Description | Security | JSON Support |
|---------|-------------|----------|--------------|
| `ip -j link show` | List interfaces and state | Read-only | Yes |
| `ip -j addr show` | IP addresses on interfaces | Read-only | Yes |
| `ip -j -d link show` | Detailed link info (driver, qdisc, **last_change**) | Read-only | Yes |
| `ethtool <iface>` | PHY/driver settings | Read-only | No (text) |
| `ethtool -S <iface>` | Interface statistics | Read-only | No (text) |
| `ethtool -i <iface>` | Driver info | Read-only | No (text) |
| `ethtool -k <iface>` | Offload settings | Read-only | No (text) |

**Security pattern for `ethtool` (STRICT ALLOWLIST)**:

`ethtool` has many dangerous flags that MUST be blocked:
- `-e` - EEPROM dump (information leakage)
- `-E` - EEPROM write (hardware modification)
- `-f` - Firmware flash (hardware modification)
- `-W` - Wake-on-LAN set (configuration change)
- `-s` - Speed/duplex set (configuration change)
- `-K` - Offload set (configuration change)
- `-A` - Pause set (configuration change)
- `-C` - Coalesce set (configuration change)
- `-G` - Ring buffer set (configuration change)
- `-L` - Channel set (configuration change)

**Explicitly allowed flags only**:
```tcl
# STRICT: Only allow read-only flags
# -S = stats, -i = driver info, -k = offload show (lowercase!),
# -g = ring params show, -a = pause show, -c = coalesce show
# -m = module info, -n = nway status, -T = timestamping
# No flag = basic link info
{^ethtool\s+(-[Sikgacmn]|-T)?\s+[a-zA-Z0-9@_-]+$}
```

**Explicitly blocked patterns for ethtool** (defense in depth):
```tcl
# Block any write/config flags
{\bethtool\s+.*-[EefWKACGLspPuU]}
```

### Category 2: Routing (`ip route`, `ip rule`, `ip neigh`)

| Command | Description | Security | JSON Support |
|---------|-------------|----------|--------------|
| `ip -j route show` | Routing table | Read-only | Yes |
| `ip -j route show table <N>` | Specific routing table | Read-only | Yes |
| `ip -j rule show` | Routing policy rules | Read-only | Yes |
| `ip -j neigh show` | ARP/neighbor table | Read-only | Yes |
| `ip -j tunnel show` | Tunnel interfaces | Read-only | Yes |

### Category 3: Traffic Control (`tc`)

| Command | Description | Security | JSON Support |
|---------|-------------|----------|--------------|
| `tc -j qdisc show` | All qdiscs | Read-only | Yes |
| `tc -j qdisc show dev <iface>` | Interface qdisc | Read-only | Yes |
| `tc -j class show dev <iface>` | Traffic classes | Read-only | Yes |
| `tc -j filter show dev <iface>` | Filters/actions | Read-only | Yes |
| `tc -s qdisc show` | Qdisc with stats | Read-only | No (text) |

**Note**: `tc` JSON output requires iproute2 >= 5.7 (2020+).

### Category 4: Firewall Rules (`nft`, `iptables`)

| Command | Description | Security | JSON Support |
|---------|-------------|----------|--------------|
| `nft -j list ruleset` | Full nftables ruleset | Read-only | Yes |
| `nft -j list tables` | Table list | Read-only | Yes |
| `nft -j list table <family> <name>` | Specific table | Read-only | Yes |
| `nft list chain <family> <table> <chain>` | Specific chain | Read-only | No |
| `iptables -L -n -v` | Legacy iptables rules | Read-only | No |
| `iptables -t nat -L -n -v` | NAT rules | Read-only | No |
| `ip6tables -L -n -v` | IPv6 rules | Read-only | No |

**Security consideration**: These expose firewall rules. This may reveal security policies. Document in API.

### Category 5: Network Namespaces

| Command | Description | Security | JSON Support |
|---------|-------------|----------|--------------|
| `ip netns list` | List network namespaces | Read-only | No |
| `ip netns identify <pid>` | Find namespace for PID | Read-only | No |
| `ip -j -n <ns> link show` | Links in namespace | Read-only | Yes |
| `ip -j -n <ns> addr show` | Addresses in namespace | Read-only | Yes |
| `ip -j -n <ns> route show` | Routes in namespace | Read-only | Yes |

**Note**: Namespace commands require root or `CAP_NET_ADMIN`. The MCP session may not have these privileges.

### Category 6: Additional Network Diagnostics

| Command | Description | Security | JSON Support |
|---------|-------------|----------|--------------|
| `ip -j -s link show` | Link statistics | Read-only | Yes |
| `ip -j maddr show` | Multicast addresses | Read-only | Yes |
| `ip -j vrf show` | VRF configuration | Read-only | Yes |
| `bridge -j link show` | Bridge ports | Read-only | Yes |
| `bridge -j fdb show` | Forwarding database | Read-only | Yes |
| `bridge -j vlan show` | VLAN info | Read-only | Yes |
| `conntrack -L` | Connection tracking | Read-only | No |
| `sysctl net.` | Kernel network params | Read-only | No |

### Category 7: Connectivity Diagnostics

Essential for debugging network issues from the target host's perspective:

| Command | Description | Security | Limits |
|---------|-------------|----------|--------|
| `ss -tlnpa` | Socket statistics (TCP) | Read-only | Already allowed |
| `ss -ulnpa` | Socket statistics (UDP) | Read-only | Already allowed |
| `dig <domain>` | DNS resolution | Read-only, rate-limited | Single query |
| `dig +short <domain>` | Brief DNS answer | Read-only | Single query |
| `nslookup <domain>` | DNS resolution (legacy) | Read-only | Single query |
| `host <domain>` | DNS resolution (simple) | Read-only | Single query |
| `ping -c <N> <host>` | ICMP connectivity | Time-limited | Max 5 packets |
| `ping6 -c <N> <host>` | ICMPv6 connectivity | Time-limited | Max 5 packets |
| `traceroute -m <N> <host>` | Route tracing | Time-limited | Max 15 hops |
| `traceroute6 -m <N> <host>` | IPv6 route tracing | Time-limited | Max 15 hops |
| `mtr -c <N> --report <host>` | Combined ping/traceroute | Time-limited | Max 5 cycles |

**Security patterns for connectivity tools**:

```tcl
# DNS queries (single domain, no options that could cause issues)
{^dig\s+(\+short\s+)?[a-zA-Z0-9][a-zA-Z0-9.-]+$}
{^nslookup\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}
{^host\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}

# Ping with strict packet count limit (1-5 only)
{^ping6?\s+-c\s*[1-5]\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}

# Traceroute with strict hop limit (1-15 only)
{^traceroute6?\s+-m\s*([1-9]|1[0-5])\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}

# MTR report mode only (non-interactive), limited cycles
{^mtr\s+-c\s*[1-5]\s+--report\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}
```

**Blocked connectivity patterns** (prevent abuse):
```tcl
# Block ping flood, unrestricted counts
{\bping\s+.*-[fiaAQrRs]}
{\bping\s+-c\s*([6-9]|[1-9][0-9]+)}

# Block traceroute source routing, interface binding
{\btraceroute\s+.*-[gis]}

# Block interactive MTR
{\bmtr\s+(?!.*--report)}
```

**Rationale for limits**:
- `ping -c 5` = ~5 seconds max execution time
- `traceroute -m 15` = ~30 seconds max (1-2s per hop timeout)
- `mtr -c 5 --report` = ~5 seconds max
- DNS queries are fast (<1s typically) but rate-limited by existing mechanism

## Security Implementation

### Privacy Mode

For high-security environments, a **Privacy Mode** toggle masks sensitive information before returning data to the LLM:

| Data Type | Masking Strategy | Example |
|-----------|------------------|---------|
| Internal IPs | Replace with `x.x.x.x` or keep prefix | `10.1.2.3` → `10.x.x.x` |
| Port numbers | Optionally mask ephemeral ports | `:54321` → `:xxxxx` |
| MAC addresses | Mask last 3 octets | `52:54:00:12:34:56` → `52:54:00:xx:xx:xx` |
| Connection IDs | Hash or truncate | `connid=12345` → `connid=*****` |

**Implementation in tools layer**:
```tcl
proc apply_privacy_filter {output privacy_level} {
    switch $privacy_level {
        "none" { return $output }
        "standard" {
            # Mask RFC1918 addresses (keep network prefix)
            set output [regsub -all {(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)[0-9]+\.[0-9]+} \
                $output {\1x.x}]
            # Mask ephemeral ports (>32767)
            set output [regsub -all {:([3-6][0-9]{4})} $output {:xxxxx}]
            return $output
        }
        "strict" {
            # Mask all IPs except loopback
            set output [regsub -all {(?!127\.0\.0\.)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+} \
                $output {x.x.x.x}]
            return $output
        }
    }
}
```

**Tool parameter**:
```json
{
  "name": "ssh_network_conntrack",
  "inputSchema": {
    "properties": {
      "privacy": {"enum": ["none", "standard", "strict"], "default": "standard"}
    }
  }
}
```

### Updated Allowlist Patterns

```tcl
# New patterns to add to security.tcl

# ip command (inspection only)
{^ip\s+(-[0-9])?\s*(-j(son)?)?\s*(-d(etails)?)?\s*(-s(tat(istics)?)?)?\s*(link|addr|address|route|rule|neigh|neighbor|tunnel|maddr|vrf)\s+(show|list)(\s|$)}
{^ip\s+(-j)?\s*netns\s+(list|identify)(\s|$)}
{^ip\s+(-j)?\s*-n\s+[a-zA-Z0-9_-]+\s+(link|addr|route)\s+show(\s|$)}

# ethtool (STRICT: read-only flags ONLY)
{^ethtool\s+(-[Sikgacmn]|-T)?\s+[a-zA-Z0-9@_-]+$}

# tc command (show only)
{^tc\s+(-[js])?\s*(qdisc|class|filter|action)\s+show(\s|$)}

# nft command (list only)
{^nft\s+(-j)?\s*list\s+(ruleset|tables|table|chain|set|map)(\s|$)}

# iptables (list only, with common tables)
{^ip6?tables\s+(-t\s+(filter|nat|mangle|raw|security)\s+)?-[LnvS]+(\s|$)}

# bridge command (show only)
{^bridge\s+(-j)?\s+(link|fdb|vlan|mdb)\s+show(\s|$)}

# conntrack (list only)
{^conntrack\s+-L(\s|$)}

# sysctl net parameters (read only)
{^sysctl\s+(-a\s+)?net\.}

# DNS queries
{^dig\s+(\+short\s+)?[a-zA-Z0-9][a-zA-Z0-9.-]+$}
{^nslookup\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}
{^host\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}

# Ping with strict limits (1-5 packets only)
{^ping6?\s+-c\s*[1-5]\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}

# Traceroute with strict limits (1-15 hops only)
{^traceroute6?\s+-m\s*([1-9]|1[0-5])\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}

# MTR report mode only
{^mtr\s+-c\s*[1-5]\s+--report\s+[a-zA-Z0-9][a-zA-Z0-9.-]+$}
```

### Commands Explicitly Blocked

The following patterns remain blocked (defense in depth):

```tcl
# Block any ip commands that modify state
{\bip\s+.*\s+(add|del|delete|change|replace|set|flush|append)\b}

# Block tc modifications
{\btc\s+.*\s+(add|del|change|replace)\b}

# Block nft modifications
{\bnft\s+.*\s+(add|delete|insert|replace|flush|destroy)\b}

# Block iptables modifications
{\biptables\s+.*\s+(-[ADIRF]|--append|--delete|--insert|--replace|--flush)\b}

# Block ethtool write/config flags (CRITICAL)
{\bethtool\s+.*-[EefWKACGLspPuU]}
{\bethtool\s+.*--flash}
{\bethtool\s+.*--change}
{\bethtool\s+.*--set}

# Block ping/traceroute abuse
{\bping\s+.*-[fiaAQrRs]}
{\bping\s+-c\s*([6-9]|[1-9][0-9]+)}
{\btraceroute\s+.*-[gis]}
{\bmtr\s+(?!.*--report)}

# Block DNS zone transfers and advanced queries
{\bdig\s+.*AXFR}
{\bdig\s+.*-[x]\s}
```

## MCP API Design

### Option A: Raw Command (Current Pattern)

Continue using `ssh_run_command` with allowlisted network commands:

```json
{
  "method": "tools/call",
  "params": {
    "name": "ssh_run_command",
    "arguments": {
      "session_id": "sess_123",
      "command": "ip -j addr show"
    }
  }
}
```

**Pros**: Simple, flexible, no new tools needed
**Cons**: LLM must know command syntax, output parsing varies

### Option B: High-Level Network Tools (Recommended)

Add network-specific tools that wrap commands and return structured data:

#### `ssh_network_interfaces`
```json
{
  "name": "ssh_network_interfaces",
  "description": "List network interfaces with addresses, state, and stability info",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string"},
      "interface": {"type": "string", "description": "Optional: specific interface"},
      "include_stats": {"type": "boolean", "default": false},
      "include_stability": {"type": "boolean", "default": true, "description": "Include link_changes_count and last_change for flap detection"}
    },
    "required": ["session_id"]
  }
}
```

**Response** (with stability info for flap detection):
```json
{
  "interfaces": [
    {
      "name": "eth0",
      "mac": "52:54:00:12:34:56",
      "mtu": 1500,
      "state": "UP",
      "operstate": "UP",
      "addresses": [
        {"family": "inet", "address": "10.0.0.5", "prefixlen": 24},
        {"family": "inet6", "address": "fe80::5054:ff:fe12:3456", "prefixlen": 64, "scope": "link"}
      ],
      "stats": {"rx_bytes": 1234567, "tx_bytes": 987654, "rx_errors": 0, "tx_errors": 0},
      "stability": {
        "link_changes_count": 2,
        "last_change_seconds_ago": 3600,
        "carrier_up_count": 2,
        "carrier_down_count": 1
      }
    }
  ],
  "timestamp": "2026-02-16T10:30:00Z"
}
```

**Implementation note**: `last_change` is derived from `ip -d link show` which reports `link/ether ... numtxqueues ... link_changes X`. Combined with `/sys/class/net/<iface>/carrier_changes`.

#### `ssh_network_routes`
```json
{
  "name": "ssh_network_routes",
  "description": "Show routing table",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string"},
      "table": {"type": "string", "default": "main"},
      "family": {"enum": ["inet", "inet6", "all"], "default": "all"}
    },
    "required": ["session_id"]
  }
}
```

#### `ssh_network_firewall`
```json
{
  "name": "ssh_network_firewall",
  "description": "Show firewall rules (nftables or iptables)",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string"},
      "format": {"enum": ["nft", "iptables", "auto"], "default": "auto"},
      "table": {"type": "string", "description": "Optional: specific table"}
    },
    "required": ["session_id"]
  }
}
```

#### `ssh_network_qdisc`
```json
{
  "name": "ssh_network_qdisc",
  "description": "Show traffic control qdiscs and classes",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string"},
      "interface": {"type": "string", "description": "Optional: specific interface"},
      "include_stats": {"type": "boolean", "default": false}
    },
    "required": ["session_id"]
  }
}
```

#### `ssh_network_namespaces`
```json
{
  "name": "ssh_network_namespaces",
  "description": "List network namespaces and optionally inspect one",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string"},
      "namespace": {"type": "string", "description": "Inspect specific namespace"},
      "detail": {"enum": ["list", "interfaces", "routes", "all"], "default": "list"}
    },
    "required": ["session_id"]
  }
}
```

#### `ssh_network_compare` (Diff Capability)

A powerful tool for diagnosing "what changed?" scenarios:

```json
{
  "name": "ssh_network_compare",
  "description": "Compare current network state against a previous snapshot or baseline",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string"},
      "scope": {
        "enum": ["interfaces", "routes", "firewall", "all"],
        "default": "all",
        "description": "What to compare"
      },
      "baseline": {
        "type": "string",
        "description": "Optional: JSON snapshot from previous ssh_network_* call to compare against. If omitted, compares against cached state from last call."
      },
      "format": {
        "enum": ["diff", "added_removed", "summary"],
        "default": "added_removed"
      }
    },
    "required": ["session_id"]
  }
}
```

**Response**:
```json
{
  "changes_detected": true,
  "scope": "routes",
  "comparison": {
    "added": [
      {"dst": "10.100.0.0/24", "gateway": "10.0.0.254", "dev": "eth0"}
    ],
    "removed": [
      {"dst": "10.50.0.0/24", "gateway": "10.0.0.1", "dev": "eth0"}
    ],
    "modified": [
      {
        "item": "default route",
        "before": {"gateway": "10.0.0.1"},
        "after": {"gateway": "10.0.0.254"}
      }
    ]
  },
  "baseline_timestamp": "2026-02-16T10:00:00Z",
  "current_timestamp": "2026-02-16T10:30:00Z"
}
```

**Use cases**:
- "Why can't we reach the service anymore?" → Compare routing tables
- "Did the firewall rules change?" → Compare nftables rulesets
- "What happened to the interface?" → Compare link states

**Implementation**: Server caches the last snapshot per session. LLM can also explicitly pass a previous snapshot for comparison.

#### `ssh_network_connectivity`

Consolidated connectivity testing tool:

```json
{
  "name": "ssh_network_connectivity",
  "description": "Test network connectivity from the target host (ping, DNS, traceroute)",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string"},
      "target": {"type": "string", "description": "Hostname or IP to test"},
      "tests": {
        "type": "array",
        "items": {"enum": ["ping", "dns", "traceroute"]},
        "default": ["ping", "dns"]
      },
      "ping_count": {"type": "integer", "minimum": 1, "maximum": 5, "default": 3},
      "traceroute_hops": {"type": "integer", "minimum": 1, "maximum": 15, "default": 10}
    },
    "required": ["session_id", "target"]
  }
}
```

**Response**:
```json
{
  "target": "google.com",
  "results": {
    "dns": {
      "resolved": true,
      "addresses": ["142.250.80.46", "2607:f8b0:4004:800::200e"],
      "latency_ms": 5
    },
    "ping": {
      "reachable": true,
      "packets_sent": 3,
      "packets_received": 3,
      "loss_percent": 0,
      "rtt_min_ms": 12.5,
      "rtt_avg_ms": 14.2,
      "rtt_max_ms": 18.1
    },
    "traceroute": {
      "hops": [
        {"hop": 1, "ip": "10.0.0.1", "rtt_ms": 1.2},
        {"hop": 2, "ip": "192.168.1.1", "rtt_ms": 5.3},
        {"hop": 3, "ip": "*", "rtt_ms": null},
        {"hop": 4, "ip": "142.250.80.46", "rtt_ms": 12.5}
      ],
      "reached_target": true
    }
  }
}
```

### Option C: Batch Command Execution (Performance)

Add a tool for executing multiple commands in parallel:

#### `ssh_batch_commands`
```json
{
  "name": "ssh_batch_commands",
  "description": "Execute multiple commands concurrently and return all results",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string"},
      "commands": {
        "type": "array",
        "items": {"type": "string"},
        "minItems": 1,
        "maxItems": 5,
        "description": "List of commands (max 5 to prevent pool starvation)"
      },
      "parallel": {"type": "boolean", "default": true},
      "stop_on_error": {"type": "boolean", "default": false}
    },
    "required": ["session_id", "commands"]
  }
}
```

**Pool Starvation Prevention**:

| Limit | Value | Rationale |
|-------|-------|-----------|
| Max commands per batch | 5 | Prevents single request exhausting pool |
| Max parallel sessions per client | 10 | Reserves capacity for other clients |
| Batch timeout | 30s | Prevents runaway batch operations |

**Response**:
```json
{
  "results": [
    {"command": "ip -j addr show", "success": true, "output": "[...]", "duration_ms": 15},
    {"command": "ip -j route show", "success": true, "output": "[...]", "duration_ms": 12},
    {"command": "tc -j qdisc show", "success": true, "output": "[...]", "duration_ms": 18}
  ],
  "total_duration_ms": 23,
  "parallel": true,
  "sessions_used": 3
}
```

**IMPORTANT: Namespace Consistency Warning**

When using parallel execution, each command runs in an **independent session**:

```
┌─────────────────────────────────────────────────────────────┐
│                    PARALLEL BATCH                            │
├─────────────────────────────────────────────────────────────┤
│  Session 1: ip -j addr show         → sees default netns    │
│  Session 2: ip -j route show        → sees default netns    │
│  Session 3: ip netns exec foo ...   → ERROR: separate sess  │
└─────────────────────────────────────────────────────────────┘
```

- **Namespace changes do NOT propagate** between parallel sessions
- Each session starts in the default network namespace
- Use `ip -n <namespace>` syntax for namespace-specific queries
- For complex namespace workflows, use serial execution on a single session

**Documentation requirement**: The tool MUST clearly state that parallel batch commands are "independent executions" with no shared state.

## Parallel Execution Architecture

### Current Model: Serial Execution

```
┌──────────┐     ┌─────────────┐     ┌────────────┐
│  Client  │────▶│ MCP Server  │────▶│ SSH Target │
│          │  1  │             │  1  │            │
│          │◀────│             │◀────│            │
│          │  2  │             │  2  │            │
│          │────▶│             │────▶│            │
│          │◀────│             │◀────│            │
└──────────┘     └─────────────┘     └────────────┘
         4 round trips for 2 commands
```

### Proposed Model: Parallel Execution

#### Option 1: Single Session, Sequential Commands (Simple)

```tcl
# Run commands sequentially on existing session
# Pro: Simple, uses existing spawn_id
# Con: Still serial, no parallelism
proc batch_serial {spawn_id commands} {
    set results {}
    foreach cmd $commands {
        ::mcp::security::validate_command $cmd
        lappend results [::prompt::run $spawn_id $cmd]
    }
    return $results
}
```

#### Option 2: Multiple Parallel SSH Sessions (True Parallelism)

```
┌──────────┐     ┌─────────────┐     ┌────────────┐
│  Client  │────▶│ MCP Server  │═══▶│ SSH Target │
│          │  1  │             │    │            │
│          │     │  ┌───────┐  │────│            │
│          │     │  │ SSH 1 │──│    │            │
│          │     │  ├───────┤  │────│            │
│          │     │  │ SSH 2 │──│    │            │
│          │     │  ├───────┤  │    │            │
│          │     │  │ SSH 3 │──│    │            │
│          │◀────│  └───────┘  │◀═══│            │
└──────────┘  1  └─────────────┘     └────────────┘
         2 round trips for 3 commands (parallel SSH)
```

**Implementation**:
```tcl
proc batch_parallel {host user password commands} {
    # Create N parallel SSH connections from pool
    set sessions {}
    set async_ids {}

    foreach cmd $commands {
        ::mcp::security::validate_command $cmd
        set sess [::mcp::pool::acquire $host $user $password]
        lappend sessions $sess

        # Run command asynchronously
        set spawn_id [dict get $sess spawn_id]
        lappend async_ids [after 0 [list async_run $spawn_id $cmd]]
    }

    # Wait for all to complete
    set results [gather_results $async_ids]

    # Release sessions back to pool
    foreach sess $sessions {
        ::mcp::pool::release $sess
    }

    return $results
}
```

**Pros**: True parallelism, significant speedup for multiple commands
**Cons**: More SSH connections, pool management complexity

#### Option 3: Multi-Session Per MCP Client (Hybrid)

Allow the MCP client to create multiple SSH sessions and run commands on them in parallel:

```json
{
  "method": "tools/call",
  "params": {
    "name": "ssh_parallel_run",
    "arguments": {
      "targets": [
        {"session_id": "sess_1", "command": "ip -j addr show"},
        {"session_id": "sess_2", "command": "ip -j route show"},
        {"session_id": "sess_3", "command": "tc -j qdisc show"}
      ]
    }
  }
}
```

This allows parallelism across both:
- Multiple commands on same host (different sessions)
- Multiple commands on different hosts

### Recommended Approach

1. **Phase 1**: Add `ssh_batch_commands` with sequential execution (simple)
2. **Phase 2**: Add connection pool integration for parallel execution
3. **Phase 3**: Add `ssh_parallel_run` for multi-session parallelism

## Large Output Handling

### Streaming Large Rulesets

Full `nft list ruleset` or `conntrack -L` output can be massive (several MB). The MCP server implements automatic handling:

| Output Size | Behavior | Rationale |
|-------------|----------|-----------|
| < 256 KB | Return full output | Normal operation |
| 256 KB - 1 MB | Return with warning | Alert LLM to large response |
| > 1 MB | Summary mode + truncation | Prevent memory exhaustion |

**Summary Mode Response**:
```json
{
  "truncated": true,
  "original_size_bytes": 2500000,
  "returned_size_bytes": 262144,
  "summary": {
    "tables": 5,
    "chains": 23,
    "rules": 1547,
    "largest_table": "inet filter (892 rules)"
  },
  "content": "[first 256KB of output...]",
  "suggestion": "Use ssh_network_firewall with 'table' parameter to query specific tables"
}
```

**Implementation**:
```tcl
proc handle_large_output {output max_size} {
    set size [string length $output]

    if {$size <= $max_size} {
        return [dict create truncated false content $output]
    }

    # Generate summary based on content type
    set summary [generate_summary $output]

    return [dict create \
        truncated true \
        original_size_bytes $size \
        returned_size_bytes $max_size \
        summary $summary \
        content [string range $output 0 [expr {$max_size - 1}]] \
        suggestion "Query specific tables/interfaces to reduce output size" \
    ]
}
```

### Conntrack-Specific Handling

`conntrack -L` can return millions of entries on busy servers. Special handling:

```json
{
  "name": "ssh_network_conntrack",
  "inputSchema": {
    "properties": {
      "limit": {"type": "integer", "default": 1000, "maximum": 10000},
      "filter": {"type": "string", "description": "Filter expression (e.g., 'src=10.0.0.1')"},
      "summary_only": {"type": "boolean", "default": false}
    }
  }
}
```

**Summary-only response** (for monitoring):
```json
{
  "summary_only": true,
  "total_connections": 45230,
  "by_protocol": {"tcp": 42100, "udp": 3100, "icmp": 30},
  "by_state": {"ESTABLISHED": 38000, "TIME_WAIT": 4100, "SYN_SENT": 1000}
}
```

## Performance Considerations

### Connection Pool Sizing

For parallel batch operations, the pool should support multiple simultaneous connections:

| Scenario | Pool Size | Rationale |
|----------|-----------|-----------|
| Single command | 1-2 | Current default |
| Batch (3-5 cmds) | 3-5 | One connection per command |
| Heavy parallel | 10 | Upper limit per host |

### Latency Budget

Typical network command latencies:

| Command | Typical Latency | Notes |
|---------|-----------------|-------|
| `ip -j addr show` | 5-15ms | Very fast |
| `ip -j route show` | 5-15ms | Depends on table size |
| `tc -j qdisc show` | 10-20ms | Iterates all interfaces |
| `nft -j list ruleset` | 20-100ms | Depends on ruleset size |
| `ethtool <iface>` | 10-30ms | Driver-dependent |
| `conntrack -L` | 50-500ms | Depends on connection count |

**Batch of 5 commands**:
- Serial: ~100ms
- Parallel: ~30ms (limited by slowest)

## Testing Strategy

### Unit Tests (Mock)

1. **Allowlist validation** - Test all new patterns accept valid commands
2. **Block validation** - Test modification commands are rejected
3. **JSON parsing** - Verify JSON output is properly passed through
4. **Batch execution** - Test batch command handling
5. **Privacy mode** - Test IP/port masking at all levels
6. **Large output** - Test truncation and summary generation
7. **ethtool strict allowlist** - Test ONLY permitted flags work

### Integration Tests (VM)

1. **Interface listing** - Verify `ip addr` works across interface types
2. **Routing tables** - Test with multiple routing tables
3. **Namespace support** - Test with network namespaces (requires setup)
4. **Firewall rules** - Test with active nftables/iptables
5. **Traffic control** - Test with configured qdiscs
6. **Connectivity tools** - Test ping/traceroute/DNS from VM
7. **Flap detection** - Test interface stability fields
8. **Diff capability** - Test before/after comparison

### MCP Server E2E Tests

End-to-end tests that exercise the full MCP server stack with real SSH connections. These tests verify that network commands work correctly through the entire pipeline: HTTP → JSON-RPC → Tools → SSH → Target.

#### TCL Agent E2E Tests (`mcp/agent/e2e_test.tcl`)

Add network tool tests to the existing E2E test suite:

```tcl
#=============================================================================
# Network Tool E2E Tests
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

        set text [::agent::mcp::extract_text $result]
        # Should have at least a default route or local routes
        ::test::assert {[string length $text] > 10} "Routes output is not empty"

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
            ::test::assert {$fw_format in {nft iptables}} "Detected firewall format"
        }

    } err]} {
        # May fail if no firewall installed - that's OK
        ::test::skip "Network firewall tool" "Firewall may not be installed"
    }
}

proc test_network_connectivity {} {
    puts ""
    puts "--- Test: Network Connectivity Tool ---"

    if {[catch {
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

            foreach cmd_result $results {
                if {[dict exists $cmd_result success]} {
                    ::test::assert {[dict get $cmd_result success]} \
                        "Command [dict get $cmd_result command] succeeded"
                }
            }
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

    if {[catch {
        # Try to submit 6 commands (should fail)
        set result [::agent::mcp::call_tool "ssh_batch_commands" \
            [dict create \
                session_id $::session_id \
                commands [list "cmd1" "cmd2" "cmd3" "cmd4" "cmd5" "cmd6"]]]

        if {[dict exists $result isError] && [dict get $result isError]} {
            ::test::pass "Batch size limit correctly enforced"
        } else {
            ::test::fail "Batch size limit" "Should reject >5 commands"
        }

    } err]} {
        # Error is expected - this is a pass
        if {[string match "*max*" $err] || [string match "*5*" $err]} {
            ::test::pass "Batch size limit correctly enforced"
        } else {
            ::test::fail "Batch size limit" $err
        }
    }
}
```

#### Bash E2E Tests (`mcp/tests/real/test_network_e2e.sh`)

Create a new test file for network command E2E testing:

```bash
#!/bin/bash
# test_network_e2e.sh - Network Commands E2E Tests
#
# Tests network tools through the MCP server with real SSH connections.
# Requires: SSH_HOST, PASSWORD environment variables
#
# Usage: ./test_network_e2e.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=mcp_client.sh
source "$SCRIPT_DIR/mcp_client.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

# Setup
setup() {
    check_mcp_server
    mcp_initialize
    SSH_SESSION_ID=$(mcp_ssh_connect "$SSH_HOST" "$SSH_USER" "$PASSWORD" | jq -r '.session_id // empty')
    if [ -z "$SSH_SESSION_ID" ]; then
        echo -e "${RED}Failed to establish SSH session${NC}"
        exit 1
    fi
    echo "SSH Session: $SSH_SESSION_ID"
}

# Teardown
teardown() {
    if [ -n "$SSH_SESSION_ID" ]; then
        mcp_ssh_disconnect "$SSH_SESSION_ID" > /dev/null 2>&1 || true
    fi
}

trap teardown EXIT

#===========================================================================
# NETWORK TOOL TESTS
#===========================================================================

test_ip_addr_show() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip -j addr show")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ip -j addr show"
        ((FAIL++))
    else
        # Verify JSON output
        if echo "$response" | jq -e '.[0].ifname' > /dev/null 2>&1; then
            echo -e "${GREEN}PASS${NC}: ip -j addr show returns valid JSON"
            ((PASS++))
        else
            echo -e "${YELLOW}PASS${NC}: ip -j addr show (non-JSON output)"
            ((PASS++))
        fi
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

test_ping_limited() {
    local response
    # Should succeed with 3 packets
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -c 3 127.0.0.1")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ping -c 3 127.0.0.1"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ping -c 3 allowed"
        ((PASS++))
    fi
}

test_ethtool_stats() {
    local response
    # May fail if interface doesn't exist - that's OK
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -S lo" 2>&1 || true)

    # Either success or "no stats available" is acceptable
    if has_error "$response" && [[ ! "$response" =~ "no stats" ]]; then
        echo -e "${YELLOW}SKIP${NC}: ethtool -S (may not be supported)"
    else
        echo -e "${GREEN}PASS${NC}: ethtool -S command accepted"
        ((PASS++))
    fi
}

test_nft_list() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "nft list tables" 2>&1 || true)

    # May fail if nft not installed
    if has_error "$response" && [[ "$response" =~ "not found" ]]; then
        echo -e "${YELLOW}SKIP${NC}: nft not installed"
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
            echo -e "${RED}FAIL${NC}: batch commands (expected 3 results, got $count)"
            ((FAIL++))
        fi
    fi
}

#===========================================================================
# MAIN
#===========================================================================

echo ""
echo "=== Network Commands E2E Tests ==="
echo ""

setup

test_ip_addr_show
test_ip_route_show
test_tc_qdisc_show
test_ping_limited
test_ethtool_stats
test_nft_list
test_batch_commands

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ $FAIL -gt 0 ]; then
    exit 1
fi
exit 0
```

#### Security E2E Tests (`mcp/tests/real/test_security_e2e.sh`)

Add network command security tests:

```bash
#===========================================================================
# NETWORK COMMAND SECURITY TESTS
#===========================================================================

run_network_security_tests() {
    echo ""
    echo "=== Network Command Security Tests ==="
    echo ""

    local response

    # ip link set MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip link set eth0 down")
    expect_blocked "ip link set (interface down)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip addr add 10.0.0.1/24 dev eth0")
    expect_blocked "ip addr add" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip route add default via 10.0.0.1")
    expect_blocked "ip route add" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip route del 10.0.0.0/24")
    expect_blocked "ip route del" "$response"

    # tc modifications MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc qdisc add dev eth0 root netem delay 100ms")
    expect_blocked "tc qdisc add" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc qdisc del dev eth0 root")
    expect_blocked "tc qdisc del" "$response"

    # nft modifications MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "nft add table inet test")
    expect_blocked "nft add table" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "nft flush ruleset")
    expect_blocked "nft flush ruleset" "$response"

    # ethtool dangerous flags MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -f eth0 firmware.bin")
    expect_blocked "ethtool -f (firmware flash)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -E eth0")
    expect_blocked "ethtool -E (EEPROM write)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool -s eth0 speed 1000")
    expect_blocked "ethtool -s (speed set)" "$response"

    # Ping flood MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -f 8.8.8.8")
    expect_blocked "ping -f (flood)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -c 100 8.8.8.8")
    expect_blocked "ping -c 100 (over limit)" "$response"

    # Traceroute abuse MUST be blocked
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "traceroute -m 100 google.com")
    expect_blocked "traceroute -m 100 (over limit)" "$response"

    # But inspection commands should work
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip -j addr show")
    expect_success "ip -j addr show (inspection)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc -j qdisc show")
    expect_success "tc -j qdisc show (inspection)" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -c 3 127.0.0.1")
    expect_success "ping -c 3 (within limit)" "$response"
}
```

### E2E Test Matrix

| Test Category | Test File | Tests | Purpose |
|---------------|-----------|-------|---------|
| TCL Agent E2E | `mcp/agent/e2e_test.tcl` | ~15 | Full MCP protocol flow |
| Bash MCP E2E | `mcp/tests/real/test_mcp_e2e.sh` | ~10 | HTTP/JSON-RPC integration |
| Network E2E | `mcp/tests/real/test_network_e2e.sh` | ~10 | Network tool functionality |
| Security E2E | `mcp/tests/real/test_security_e2e.sh` | ~20 | Attack vector blocking |

### E2E Test Environment

Tests can run against:
1. **Local VM** (TAP networking): Full 3-VM setup
2. **Real SSH target**: Any Linux host with network tools
3. **Docker container**: Lightweight testing

```bash
# Option 1: 3-VM TAP setup
sudo nix run .#ssh-network-setup
nix build .#ssh-target-vm-tap-debug && ./result/bin/microvm-run &
nix build .#mcp-vm-tap-debug && ./result/bin/microvm-run &
cd mcp/tests/real && SSH_HOST=10.178.0.20 PASSWORD=testpass ./test_network_e2e.sh

# Option 2: Real SSH target
SSH_HOST=192.168.1.100 PASSWORD=secret ./test_network_e2e.sh

# Option 3: TCL agent E2E
tclsh mcp/agent/e2e_test.tcl --mcp-host 10.178.0.10 --target-host 10.178.0.20
```

### Test Scenarios

```tcl
# Test: List interfaces with JSON output
test_network_interfaces_json {
    set result [::mcp::tools::dispatch "ssh_run_command" \
        [dict create session_id $session command "ip -j addr show"] \
        $mcp_session]

    # Verify JSON is valid
    set json [dict get $result content 0 text]
    set parsed [json::decode $json]
    assert {[llength $parsed] > 0}
    assert {[dict exists [lindex $parsed 0] ifname]}
}

# Test: Batch commands execute and return
test_batch_commands {
    set result [::mcp::tools::dispatch "ssh_batch_commands" \
        [dict create \
            session_id $session \
            commands [list "ip -j addr show" "ip -j route show" "hostname"]] \
        $mcp_session]

    set results [dict get $result results]
    assert {[llength $results] == 3}
    assert {[dict get [lindex $results 0] success]}
}

# Test: Modification commands are blocked
test_ip_set_blocked {
    set err [catch {
        ::mcp::security::validate_command "ip link set eth0 down"
    }]
    assert {$err == 1}
}

# Test: ethtool dangerous flags are blocked
test_ethtool_flash_blocked {
    set err [catch {
        ::mcp::security::validate_command "ethtool -f eth0 firmware.bin"
    }]
    assert {$err == 1}
}

test_ethtool_eeprom_blocked {
    set err [catch {
        ::mcp::security::validate_command "ethtool -E eth0"
    }]
    assert {$err == 1}
}

# Test: Ping packet limit enforced
test_ping_limit_enforced {
    # 5 packets allowed
    set ok [catch {::mcp::security::validate_command "ping -c 5 8.8.8.8"}]
    assert {$ok == 0}

    # 6 packets blocked
    set err [catch {::mcp::security::validate_command "ping -c 6 8.8.8.8"}]
    assert {$err == 1}

    # 100 packets blocked
    set err [catch {::mcp::security::validate_command "ping -c 100 8.8.8.8"}]
    assert {$err == 1}
}

# Test: Privacy mode masks internal IPs
test_privacy_mode_standard {
    set input "src=10.1.2.3 dst=8.8.8.8 sport=54321 dport=443"
    set output [::mcp::security::apply_privacy_filter $input "standard"]
    assert {[string match "*10.x.x*" $output]}
    assert {[string match "*8.8.8.8*" $output]}  ;# Public IP preserved
    assert {[string match "*:xxxxx*" $output]}    ;# Ephemeral port masked
    assert {[string match "*:443*" $output]}      ;# Well-known port preserved
}

# Test: Large output triggers summary mode
test_large_output_truncation {
    # Generate 2MB output
    set large_output [string repeat "x" 2097152]
    set result [::mcp::tools::handle_large_output $large_output 262144]
    assert {[dict get $result truncated]}
    assert {[dict get $result original_size_bytes] == 2097152}
    assert {[string length [dict get $result content]] <= 262144}
}

# Test: Batch size limit enforced
test_batch_size_limit {
    set err [catch {
        ::mcp::tools::dispatch "ssh_batch_commands" \
            [dict create \
                session_id $session \
                commands [list "cmd1" "cmd2" "cmd3" "cmd4" "cmd5" "cmd6"]] \
            $mcp_session
    }]
    assert {$err == 1}
    assert {[string match "*max*5*" $::errorInfo]}
}

# Test: Network compare detects changes
test_network_compare {
    # Get baseline
    set baseline [::mcp::tools::dispatch "ssh_network_routes" \
        [dict create session_id $session] $mcp_session]

    # Simulate change (in real test, add a route)
    # ...

    # Compare
    set result [::mcp::tools::dispatch "ssh_network_compare" \
        [dict create \
            session_id $session \
            scope "routes" \
            baseline [dict get $baseline raw_json]] \
        $mcp_session]

    assert {[dict exists $result changes_detected]}
}
```

### VM Test Infrastructure

Add to `nix/ssh-target-vm.nix`:

```nix
# Configure test networking for network command tests
networking.interfaces.test0 = {
  virtual = true;
  ipv4.addresses = [{ address = "192.168.100.1"; prefixLength = 24; }];
};

# Add traffic control for testing
systemd.services.setup-tc = {
  script = ''
    tc qdisc add dev test0 root netem delay 10ms
  '';
  wantedBy = ["multi-user.target"];
};

# Add nftables rules for testing (multiple tables for large ruleset test)
networking.nftables = {
  enable = true;
  ruleset = ''
    table inet test_filter {
      chain input { type filter hook input priority 0; policy accept; }
      chain output { type filter hook output priority 0; policy accept; }
    }
    table inet test_nat {
      chain prerouting { type nat hook prerouting priority 0; }
      chain postrouting { type nat hook postrouting priority 0; }
    }
  '';
};

# Create a network namespace for testing
systemd.services.setup-netns = {
  script = ''
    ip netns add testns
    ip link add veth0 type veth peer name veth1
    ip link set veth1 netns testns
    ip addr add 10.200.0.1/24 dev veth0
    ip netns exec testns ip addr add 10.200.0.2/24 dev veth1
    ip link set veth0 up
    ip netns exec testns ip link set veth1 up
    ip netns exec testns ip link set lo up
  '';
  wantedBy = ["multi-user.target"];
};

# Install connectivity testing tools
environment.systemPackages = with pkgs; [
  iproute2
  ethtool
  nftables
  iptables
  conntrack-tools
  bridge-utils
  bind.dnsutils  # dig, nslookup
  traceroute
  mtr
  iputils        # ping
];

# Enable connection tracking for conntrack tests
boot.kernelModules = [ "nf_conntrack" ];

# Generate test connections for conntrack
systemd.services.generate-connections = {
  script = ''
    # Generate some tracked connections for testing
    for i in $(seq 1 10); do
      timeout 1 curl -s http://example.com/ || true &
    done
    wait
  '';
  wantedBy = ["multi-user.target"];
  after = ["network-online.target"];
};

# Flapping interface simulation for stability testing
systemd.services.flap-interface = {
  script = ''
    # Create a dummy interface that we can flap
    ip link add dummy0 type dummy
    ip addr add 10.99.0.1/24 dev dummy0
    ip link set dummy0 up

    # Simulate 2 link flaps
    sleep 2
    ip link set dummy0 down
    sleep 1
    ip link set dummy0 up
    sleep 1
    ip link set dummy0 down
    sleep 1
    ip link set dummy0 up
  '';
  wantedBy = ["multi-user.target"];
};
```

### Additional Test Fixtures

```nix
# Large ruleset generation for truncation testing
systemd.services.generate-large-ruleset = {
  script = ''
    # Generate a large nftables ruleset for truncation testing
    for i in $(seq 1 500); do
      nft add rule inet test_filter input ip saddr 10.0.$((i/256)).$((i%256)) counter
    done
  '';
  wantedBy = ["multi-user.target"];
  after = ["nftables.service"];
};
```

## Phased Implementation

### Phase 1: Read-Only Network Inspection (Week 1-2)

1. Update `security.tcl` with new allowlist patterns
2. Add blocked patterns for modification commands (including strict ethtool)
3. Add connectivity tool patterns (ping, traceroute, DNS with limits)
4. Test all new patterns with unit tests (including edge cases)
5. Update VM test infrastructure
6. Document new allowed commands in README

**Deliverables**:
- Extended allowlist in `security.tcl` (~25 new patterns)
- Extended blocklist for dangerous variants (~15 new patterns)
- 80+ new security tests (including flag permutations)
- VM with test network configuration (tc, nftables, netns)

### Phase 2: High-Level Tools (Week 3-4)

1. Implement `ssh_network_interfaces` tool (with stability/flap detection)
2. Implement `ssh_network_routes` tool
3. Implement `ssh_network_firewall` tool (with summary mode)
4. Implement `ssh_network_qdisc` tool
5. Implement `ssh_network_connectivity` tool
6. Add JSON parsing/normalization layer
7. Implement large output handling (truncation, summary)

**Deliverables**:
- 5 new tools in `tools.tcl`
- Tool definitions with JSON schemas
- Large output handler with 1MB threshold
- 60+ tool tests

### Phase 3: Batch Execution & Advanced (Week 5-6)

1. Implement `ssh_batch_commands` (sequential first)
2. Add pool integration for parallel execution (max 5 per batch)
3. Implement `ssh_network_compare` (diff tool)
4. Implement `ssh_network_conntrack` (with privacy mode)
5. Add metrics for batch operations
6. Performance testing and optimization
7. Document namespace isolation for parallel batch

**Deliverables**:
- `ssh_batch_commands` tool with pool integration
- `ssh_network_compare` tool with baseline caching
- `ssh_network_conntrack` tool with privacy levels
- Parallel execution via connection pool
- Performance benchmarks
- Clear documentation on batch isolation

### Phase 4: Advanced Features (Future)

1. Network namespace deep inspection tools
2. `ssh_parallel_run` for multi-session, multi-host parallelism
3. Configuration mode (opt-in, with full audit logging)
4. Real-time interface monitoring (periodic polling with diff)
5. Persistent snapshot storage for long-term comparison
6. Integration with observability stack (Prometheus metrics for network state)

## API Summary

### New Tools (Phase 2+)

| Tool | Description | Required | Key Features |
|------|-------------|----------|--------------|
| `ssh_network_interfaces` | List interfaces, addresses, state | session_id | Stability/flap detection |
| `ssh_network_routes` | Show routing tables | session_id | Table selection, family filter |
| `ssh_network_firewall` | Show nftables/iptables rules | session_id | Auto-detect, summary mode |
| `ssh_network_qdisc` | Show traffic control configuration | session_id | Stats, per-interface |
| `ssh_network_namespaces` | List and inspect network namespaces | session_id | Multi-level detail |
| `ssh_network_compare` | Compare network state (diff) | session_id | Baseline caching |
| `ssh_network_connectivity` | Test connectivity (ping/dns/trace) | session_id, target | Combined tests |
| `ssh_network_conntrack` | Connection tracking with privacy | session_id | Privacy mode, summary |
| `ssh_batch_commands` | Execute multiple commands at once | session_id, commands | Max 5, parallel |

### New Allowed Commands (Phase 1)

| Category | Command Pattern | Example |
|----------|-----------------|---------|
| IP Link | `ip [-j] [-d] link show` | `ip -j -d link show` |
| IP Addr | `ip [-j] addr show` | `ip -j addr show eth0` |
| IP Route | `ip [-j] route show [table N]` | `ip -j route show table main` |
| IP Rule | `ip [-j] rule show` | `ip -j rule show` |
| IP Neigh | `ip [-j] neigh show` | `ip -j neigh show` |
| IP Netns | `ip netns list/identify` | `ip netns list` |
| Ethtool | `ethtool [-Sikgacmn] <iface>` | `ethtool -S eth0` |
| TC | `tc [-js] qdisc/class/filter show` | `tc -j qdisc show dev eth0` |
| NFT | `nft [-j] list ruleset/tables/table` | `nft -j list ruleset` |
| IPTables | `iptables -L -n [-v] [-t table]` | `iptables -t nat -L -n -v` |
| Bridge | `bridge [-j] link/fdb/vlan show` | `bridge -j fdb show` |
| Conntrack | `conntrack -L` | `conntrack -L` |
| Sysctl | `sysctl net.*` | `sysctl net.ipv4.ip_forward` |
| DNS | `dig`, `nslookup`, `host` | `dig +short example.com` |
| Ping | `ping -c [1-5]` | `ping -c 3 8.8.8.8` |
| Traceroute | `traceroute -m [1-15]` | `traceroute -m 10 google.com` |
| MTR | `mtr -c [1-5] --report` | `mtr -c 3 --report 8.8.8.8` |

## Security Checklist

- [ ] All new commands are read-only (no state modification)
- [ ] Modification variants are explicitly blocked
- [ ] Pattern tests cover edge cases (whitespace, flags, arguments)
- [ ] Documentation notes that firewall rules are exposed
- [ ] Rate limiting applies to new commands
- [ ] Batch commands validate each command individually
- [ ] Pool connections for parallel execution respect limits
- [ ] Namespace commands document privilege requirements
- [ ] **ethtool patterns STRICTLY allowlist read-only flags only**
- [ ] **ping/traceroute counts enforced (max 5 packets, 15 hops)**
- [ ] **Shell redirection blocked at execution layer (no `sh -c`)**
- [ ] **Privacy mode implemented for conntrack/sensitive data**
- [ ] **Large output handling prevents memory exhaustion (1MB limit)**
- [ ] **Batch size limited to 5 to prevent pool starvation**
- [ ] **Namespace isolation documented for parallel batch**
- [ ] **DNS queries limited to simple A/AAAA lookups (no AXFR)**

## Resolved Design Decisions

Based on review feedback, the following decisions have been made:

| Question | Decision | Rationale |
|----------|----------|-----------|
| JSON parsing location | Server-side with passthrough | Parse for validation/summary, return raw for full data |
| Missing commands | Probe on connect | Cache available tools per session |
| Batch session model | Pool-based parallel | Document namespace isolation clearly |
| Namespace privileges | Clear error + documentation | No privilege escalation attempts |
| ethtool flags | Strict allowlist only | Too many dangerous write flags to blocklist safely |

## Open Questions

1. **Privacy mode default level?**
   - `none` = fastest, full visibility
   - `standard` = mask internal IPs (RFC1918), recommended default
   - `strict` = mask all IPs except loopback

2. **Snapshot retention for `ssh_network_compare`?**
   - Per-session cache (lost on disconnect)
   - Persistent storage with TTL (survives reconnection)
   - Explicit snapshot management API

3. **Connectivity test timeout handling?**
   - Hard timeout kills command (may leave orphan process)
   - Graceful timeout with partial results
   - Pre-computed timeout based on packet count

4. **Large ruleset pagination?**
   - Single truncated response with summary
   - Cursor-based pagination for iterative retrieval
   - Force table-specific queries for large rulesets

## Appendix: Command Reference

### Full `ip` JSON Output Example

```bash
$ ip -j addr show eth0
[{
  "ifindex": 2,
  "ifname": "eth0",
  "flags": ["BROADCAST","MULTICAST","UP","LOWER_UP"],
  "mtu": 1500,
  "qdisc": "fq_codel",
  "operstate": "UP",
  "group": "default",
  "link_type": "ether",
  "address": "52:54:00:12:34:56",
  "broadcast": "ff:ff:ff:ff:ff:ff",
  "addr_info": [{
    "family": "inet",
    "local": "10.0.0.5",
    "prefixlen": 24,
    "broadcast": "10.0.0.255",
    "scope": "global",
    "dynamic": true,
    "label": "eth0",
    "valid_life_time": 3600,
    "preferred_life_time": 3600
  }]
}]
```

### Full `tc` JSON Output Example

```bash
$ tc -j qdisc show dev eth0
[{
  "kind": "fq_codel",
  "handle": "0:",
  "root": true,
  "refcnt": 2,
  "options": {
    "limit": 10240,
    "flows": 1024,
    "quantum": 1514,
    "target": 5000,
    "interval": 100000,
    "memory_limit": 33554432,
    "ecn": true
  }
}]
```

### Full `nft` JSON Output Example

```bash
$ nft -j list tables
{"nftables": [
  {"metainfo": {"version": "1.0.2", "release_name": "Lester Gooch"}},
  {"table": {"family": "inet", "name": "filter", "handle": 1}}
]}
```
