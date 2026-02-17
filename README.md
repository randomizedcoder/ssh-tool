# SSH Automation Tool

A modular TCL/Expect framework for SSH automation with robust prompt detection. Includes both a CLI tool and an MCP (Model Context Protocol) server for LLM-driven automation.

**Built with Tcl 9.0** - This project includes a port of Expect to Tcl 9.0, enabling 64-bit data handling and improved performance. See [Requirements](#requirements) for details.

## Overview

This project provides two ways to automate SSH tasks:

1. **CLI Tool** (`bin/ssh-automation`) - Direct command-line SSH automation
2. **MCP Server** (`mcp/server.tcl`) - HTTP server exposing SSH tools via JSON-RPC for LLM integration

Both share the same core libraries and use **unique prompt injection** - after connecting, a predictable prompt (`XPCT<pid>>`) is set that can be reliably detected regardless of the remote system's shell configuration.

## Requirements

- **Tcl 9.0** - TCL interpreter (64-bit support, improved performance)
- **expect-tcl9** - Expect compiled against Tcl 9.0 (see below)
- **bash** - For test scripts
- **shellcheck** - For shell script linting

### Expect with Tcl 9.0

This project uses **Expect compiled against Tcl 9.0**, which required porting Expect to the new Tcl 9 API. Key changes include:

- `Tcl_Size` (64-bit) replaces `int` for size parameters
- Channel driver updated to `TCL_CHANNEL_VERSION_5` with `close2Proc`
- Compatibility layer for removed macros (`_ANSI_ARGS_`, `CONST*`, `TCL_VARARGS*`)
- `Tcl_EvalTokens` wrapper using `Tcl_EvalTokensStandard`

The port is available in `nix/expect-tcl9/` and has been submitted as [nixpkgs PR #490930](https://github.com/NixOS/nixpkgs/pull/490930).

### Using Nix (recommended)

```bash
# Enter development shell with all dependencies (Tcl 9.0 + expect-tcl9)
nix develop

# Verify versions
expect -v        # expect version 5.45.4
tclsh9.0 <<< 'puts [info patchlevel]'  # 9.0.1
```

### Install on Fedora/RHEL (Tcl 8.6 fallback)

```bash
sudo dnf install tcl expect shellcheck
```

### Install on Debian/Ubuntu (Tcl 8.6 fallback)

```bash
sudo apt install tcl expect shellcheck
```

---

# Part 1: CLI Tool

## Quick Start

```bash
# Set passwords via environment variables
export PASSWORD="your-ssh-password"
export SUDO="your-sudo-password"

# Run the tool
./bin/ssh-automation --host 192.168.1.100 --filename /etc/os-release

# With explicit user and port
./bin/ssh-automation --host 192.168.1.100 --port 22 --user admin --filename /etc/os-release

# With debug output
./bin/ssh-automation --host 192.168.1.100 --filename /etc/os-release --debug 4

# For ephemeral VMs (skip host key verification)
./bin/ssh-automation --host 192.168.1.100 --filename /etc/os-release --insecure
```

## CLI Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--host` | Yes | - | Hostname or IP address |
| `--filename` | Yes | - | File to cat on remote host |
| `--user` | No | `$USER` | SSH username |
| `--port` | No | 22 | SSH port |
| `--debug` | No | 0 | Debug level 0-7 |
| `--insecure` | No | off | Skip host key verification |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PASSWORD` | SSH password (prompts interactively if not set) |
| `SUDO` | Sudo password (prompts interactively if not set) |
| `INSECURE` | Set to `1` to skip host key verification |

## Debug Levels

| Level | Name | Description |
|-------|------|-------------|
| 0 | Off | No debug output |
| 1 | Error | Errors only |
| 2 | Warn | Warnings (includes insecure mode warning) |
| 3 | Info | Connection events |
| 4 | Verbose | Command execution |
| 5 | Debug | Expect patterns |
| 6 | Trace | Line-by-line output capture |
| 7 | Max | Internal state |

---

# Part 2: MCP Server

The MCP (Model Context Protocol) server exposes SSH automation capabilities via HTTP/JSON-RPC, enabling LLMs to securely interact with remote systems.

## Features

- **HTTP/1.1 server** with JSON-RPC 2.0 protocol
- **Built-in JSON parser** (no tcllib dependency)
- **Mandatory security controls** - command allowlist, path validation
- **Session management** with connection pooling
- **Prometheus metrics** at `/metrics`
- **Graceful shutdown** with zombie process reaping

## Quick Start

```bash
# Start the server (localhost only by default)
./mcp/server.tcl

# With custom options
./mcp/server.tcl --port 8080 --bind 0.0.0.0 --debug DEBUG
```

## Server Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `--port` | 3000 | Port to listen on |
| `--bind` | 127.0.0.1 | Address to bind to |
| `--debug` | INFO | Log level: ERROR, WARN, INFO, DEBUG |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | POST | JSON-RPC (MCP protocol) |
| `/mcp` | POST | JSON-RPC (MCP protocol) |
| `/health` | GET | Health check (JSON) |
| `/metrics` | GET | Prometheus metrics |

## MCP Tools

| Tool | Description |
|------|-------------|
| `ssh_connect` | Connect to remote host via SSH |
| `ssh_disconnect` | Disconnect SSH session |
| `ssh_run_command` | Run command on remote host |
| `ssh_run` | Alias for ssh_run_command |
| `ssh_cat_file` | Read file from remote host |
| `ssh_hostname` | Get remote hostname |
| `ssh_list_sessions` | List active SSH sessions |
| `ssh_pool_stats` | Get connection pool statistics |
| `ssh_network_interfaces` | List network interfaces with state and statistics |
| `ssh_network_routes` | Show routing tables (IPv4/IPv6) |
| `ssh_network_firewall` | Show firewall rules (auto-detects nft/iptables) |
| `ssh_network_qdisc` | Show traffic control qdiscs |
| `ssh_network_connectivity` | Test connectivity (ping/dns/traceroute) |
| `ssh_network_compare` | Compare network state changes |
| `ssh_batch_commands` | Execute multiple commands (max 5) |

## Example: JSON-RPC Request

```bash
# Initialize session
curl -X POST http://localhost:3000/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# Connect to SSH host
curl -X POST http://localhost:3000/ \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: <session-id>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
    "name":"ssh_connect",
    "arguments":{"host":"192.168.1.100","user":"admin","password":"secret"}
  }}'

# Run command
curl -X POST http://localhost:3000/ \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: <session-id>" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{
    "name":"ssh_run_command",
    "arguments":{"session_id":"<ssh-session-id>","command":"hostname"}
  }}'
```

## Security

The MCP server implements **mandatory security controls** - there is no bypass.

### Command Allowlist

Only safe, read-only commands are permitted:
- `ls`, `cat`, `head`, `tail`, `grep`, `wc`
- `ps`, `df`, `du`, `top -bn1`
- `hostname`, `uname`, `whoami`, `id`, `date`, `uptime`, `pwd`
- `stat`, `file`, `sort`, `uniq`, `cut`

### Blocked Patterns

- **Shell metacharacters**: `|`, `;`, `&&`, `||`, `` ` ``, `$()`, `>`, `<`
- **Dangerous commands**: `rm`, `chmod`, `chown`, `mv`, `cp`, `mkdir`
- **Code execution**: `find -exec`, `awk`, `sed`, `xargs`, `env`
- **Interpreters**: `python`, `perl`, `ruby`, `php`, `sh`, `bash`
- **Network tools**: `curl`, `wget`, `nc`, `ssh`, `telnet`
- **Privilege escalation**: `sudo`, `su`

### Path Validation

- **Allowed directories**: `/etc`, `/var/log`, `/home`, `/tmp`, `/opt`, `/usr/share`, `/proc`, `/sys`
- **Blocked files**: `/etc/shadow`, `/etc/sudoers`, SSH keys, bash history

### Rate Limiting

- 100 requests per minute per client
- Returns HTTP 429 when exceeded

### Network Commands

The MCP server supports network inspection commands for system administration and diagnostics. These commands follow the same security model - read-only operations only.

**Allowed Network Commands:**

| Command | Example | Description |
|---------|---------|-------------|
| `ip -j link/addr/route show` | `ip -j addr show` | Interface and routing info (JSON) |
| `ip netns list` | `ip netns list` | List network namespaces |
| `ethtool -S/-i/-k` | `ethtool -S eth0` | Interface stats (read-only flags only) |
| `tc -j qdisc/class/filter show` | `tc -j qdisc show` | Traffic control inspection |
| `nft -j list ruleset/tables` | `nft -j list ruleset` | Firewall rules (nftables) |
| `iptables -L -n` | `iptables -L -n` | Firewall rules (iptables) |
| `bridge link/fdb/vlan show` | `bridge -j link show` | Bridge inspection |
| `conntrack -L` | `conntrack -L` | Connection tracking |
| `sysctl net.*` | `sysctl net.ipv4.ip_forward` | Network sysctl values |
| `ping -c [1-5]` | `ping -c 3 host` | Connectivity test (max 5 packets) |
| `traceroute -m [1-15]` | `traceroute -m 10 host` | Path tracing (max 15 hops) |
| `dig`, `nslookup`, `host` | `dig example.com` | DNS queries (A/AAAA only) |
| `mtr --report -c [1-5]` | `mtr --report -c 3 host` | Network path analysis |

**Blocked Network Operations:**

- Any modification: `ip link set`, `tc qdisc add`, `nft add`, etc.
- Dangerous ethtool flags: `-E` (EEPROM write), `-f` (flash), `-W` (wake-on-lan), etc.
- Unlimited ping/traceroute (max 5 packets, 15 hops enforced)
- DNS zone transfers (`dig AXFR`), reverse lookups (`dig -x`)
- Flood ping (`ping -f`)

---

# Part 3: Nix Integration

The project includes comprehensive Nix flake support for reproducible development and testing.

## Development Shell

```bash
# Enter development environment with all tools
nix develop

# Available: expect, tcl, tclint, shellcheck, curl, jq, sshpass
```

## MicroVM Testing

Ephemeral NixOS MicroVMs for integration testing without affecting your system. The project provides a 3-VM architecture:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Host                                            │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                     sshbr0 (10.178.0.1/24)                            │ │
│   └───────┬─────────────────────┬─────────────────────┬───────────────────┘ │
│           │                     │                     │                      │
│       sshtap0               sshtap1               sshtap2                    │
└───────────│─────────────────────│─────────────────────│──────────────────────┘
            │                     │                     │
  ┌─────────┴─────────┐ ┌─────────┴─────────┐ ┌─────────┴─────────┐
  │    Agent VM       │ │     MCP VM        │ │    Target VM      │
  │   10.178.0.5      │ │   10.178.0.10     │ │   10.178.0.20     │
  │                   │ │                   │ │                   │
  │  TCL Test Client  │ │  MCP Server :3000 │ │  SSHD :2222-2228  │
  └───────────────────┘ └───────────────────┘ └───────────────────┘
```

- **Agent VM** - TCL 9 test client that simulates an AI agent talking to MCP
- **MCP VM** - Runs the MCP server on port 3000
- **Target VM** - Multiple SSHD instances with various configurations

```bash
# Build test VMs
nix build .#agent-vm-debug         # TCL test agent VM
nix build .#mcp-vm-debug           # MCP server VM
nix build .#ssh-target-vm-debug    # Multi-SSHD target VM

# Run target VM (user-mode networking)
./result/bin/microvm-run

# SSH ports available on target VM:
#   2222 - standard (password auth)
#   2223 - keyonly (pubkey only)
#   2224 - fancyprompt (complex prompts)
#   2225 - slowauth (2s delay)
#   2226 - denyall (all auth rejected)
#   2227 - unstable (restarts every 5s)
#   2228 - rootlogin (root permitted)
#
# Netem ports (network degradation):
#   2322-2328 - latency/loss simulation
```

## TAP Networking (requires sudo)

For full 3-VM testing with direct network access:

```bash
# Setup bridge network with 3 TAP devices
sudo nix run .#ssh-network-setup

# Terminal 1: Start target VM
nix build .#ssh-target-vm-tap-debug && ./result/bin/microvm-run

# Terminal 2: Start MCP VM
nix build .#mcp-vm-tap-debug && ./result/bin/microvm-run

# Terminal 3: Start Agent VM (runs E2E tests automatically in debug mode)
nix build .#agent-vm-tap-debug && ./result/bin/microvm-run

# Or run tests manually via SSH to agent VM
nix run .#ssh-vm-ssh-agent -- /etc/agent/run-tests.sh

# VMs accessible at:
#   Agent VM:  10.178.0.5 (SSH)
#   MCP VM:    10.178.0.10:3000 (MCP), :22 (SSH)
#   Target VM: 10.178.0.20:2222-2228 (SSH)

# Teardown
sudo nix run .#ssh-network-teardown
```

## TCL Agent Client

The project includes a pure TCL 9 MCP client (`mcp/agent/`) for E2E testing:

```tcl
# Example: Using the MCP client library
package require Tcl 9.0
source mcp/agent/mcp_client.tcl

# Initialize
::agent::mcp::init "http://10.178.0.10:3000"
::agent::mcp::initialize "my-agent" "1.0"

# Connect to SSH target
set result [::agent::mcp::ssh_connect "10.178.0.20" "testuser" "testpass" 2222]
set session_id [dict get $result session_id]

# Run commands
set output [::agent::mcp::ssh_run_command $session_id "hostname"]
puts [::agent::mcp::extract_text $output]

# Read files
set content [::agent::mcp::ssh_cat_file $session_id "/etc/os-release"]

# Cleanup
::agent::mcp::ssh_disconnect $session_id
```

The agent includes:
- `http_client.tcl` - Pure TCL HTTP/1.1 client (no dependencies)
- `json.tcl` - JSON parser/encoder
- `mcp_client.tcl` - High-level MCP protocol client
- `e2e_test.tcl` - Complete E2E test suite

## Flake Outputs

| Output | Description |
|--------|-------------|
| `packages.agent-vm` | Agent VM (user networking) |
| `packages.agent-vm-debug` | Agent VM with debug mode |
| `packages.agent-vm-tap` | Agent VM (TAP networking) |
| `packages.mcp-vm` | MCP server VM |
| `packages.mcp-vm-debug` | MCP server VM with debug mode |
| `packages.mcp-vm-tap` | MCP server VM (TAP networking) |
| `packages.ssh-target-vm` | Target VM (user networking) |
| `packages.ssh-target-vm-debug` | Target VM with debug mode |
| `packages.ssh-target-vm-tap` | Target VM (TAP networking) |
| `devShells.default` | Development environment |
| `checks.integration` | NixOS integration tests (3 VMs) |
| `apps.ssh-test-network-inspection` | Network inspection command tests |
| `apps.ssh-test-network-connectivity` | Connectivity tests (ping, DNS, traceroute) |
| `apps.ssh-test-network-all` | All network command tests |
| `apps.ssh-loadtest-quick` | Quick load test (30s) |
| `apps.ssh-loadtest` | Standard load test runner |
| `apps.ssh-loadtest-full` | Full load test suite |

---

# Part 4: Load Testing

The project includes a comprehensive load testing framework for measuring MCP server performance, throughput, and latency characteristics.

## Quick Start

```bash
# Start the 3-VM infrastructure (requires sudo for TAP networking)
sudo nix run .#ssh-network-setup
nix build .#ssh-target-vm-tap-debug && ./result/bin/microvm-run &
nix build .#mcp-vm-tap-debug && ./result/bin/microvm-run &

# Wait for VMs to boot (~30s), then run load tests

# Quick smoke test (30 seconds)
nix run .#ssh-loadtest-quick

# Full test suite (all 5 scenarios, ~15-20 minutes)
nix run .#ssh-loadtest-full

# Specific scenario with custom parameters
nix run .#ssh-loadtest -- command_throughput 120 10  # 120s duration, 10 workers

# Cleanup
sudo nix run .#ssh-network-teardown
```

## Load Test Scenarios

| Scenario | Duration | Description |
|----------|----------|-------------|
| `connection_rate` | 60s | Measure max SSH connections/second |
| `command_throughput` | 120s | Measure max commands/second on warm connections |
| `sustained_load` | 600s | 10-minute stability test for resource leaks |
| `latency_test` | 60s | Measure latency impact via netem ports (2322-2328) |
| `exhaustion_test` | 60s | Verify graceful degradation at pool/rate limits |

## Load Test Commands

| Command | Description |
|---------|-------------|
| `nix run .#ssh-loadtest-quick` | 30-second smoke test |
| `nix run .#ssh-loadtest -- <scenario> [duration] [workers]` | Run specific scenario |
| `nix run .#ssh-loadtest-full` | All 5 scenarios |
| `nix run .#ssh-loadtest-list` | List available scenarios |
| `nix run .#ssh-loadtest-connection-rate` | Connection rate test |
| `nix run .#ssh-loadtest-throughput` | Command throughput test |
| `nix run .#ssh-loadtest-latency` | Latency sensitivity test |
| `nix run .#ssh-loadtest-metrics` | Scrape MCP server metrics |

## Manual Usage

```bash
# List scenarios
tclsh mcp/agent/loadtest/run.tcl --list-scenarios

# Run with custom options
tclsh mcp/agent/loadtest/run.tcl \
  --scenario command_throughput \
  --duration 60 \
  --workers 5 \
  --mcp-host 10.178.0.10 \
  --target-host 10.178.0.20
```

## Load Test Output

Results are saved to `/tmp/loadtest_results/<test_id>/`:
- `*.jsonl` - Raw per-worker results
- `summary.json` - Aggregated results and metrics

Example report:

```
======================================================================
                         LOAD TEST RESULTS
======================================================================

Test ID:    loadtest_20260212_153045
Scenario:   command_throughput
Duration:   120.0s

----------------------------------------------------------------------
COMMAND THROUGHPUT TEST
----------------------------------------------------------------------

THROUGHPUT
  Total Requests:     4,523
  Successful:         4,515 (99.8%)
  Failed:             8
  Requests/Second:    37.7 avg, 52.3 peak

LATENCY (milliseconds)
  Min:    12.3
  p50:    42.1
  p95:    98.5
  p99:    145.2
  Max:    312.8

----------------------------------------------------------------------
POOL STATISTICS
----------------------------------------------------------------------
  Hit Rate:           87%
  Peak Active:        10

----------------------------------------------------------------------
EXTRAPOLATION (to 8 CPU / 16GB RAM)
----------------------------------------------------------------------
  Measured RPS:      37.7 (on 4 cores)
  Estimated RPS:     64.1 (on 8 cores)
  Scaling factor:    1.70x
  Confidence:        MEDIUM (based on linear scaling model)
======================================================================
```

## VM Resources for Load Testing

The load test VMs use increased resources for meaningful performance measurements:

| VM | Memory | vCPUs |
|----|--------|-------|
| Agent | 512 MB | 2 |
| MCP | 1 GB | 4 |
| Target | 1 GB | 4 |

Total: ~2.5 GB RAM, 10 cores

## Metrics Collected

**Client-side metrics:**
- Request latency (min, p50, p95, p99, max)
- Throughput (requests/second)
- Success/error counts

**Server-side metrics (via `/metrics`):**
- `mcp_pool_hits_total` - Connection pool reuse
- `mcp_pool_misses_total` - New connections created
- `mcp_pool_creates_total` - Total connections established
- `mcp_pool_health_fails_total` - Failed health checks
- `mcp_ssh_command_duration_seconds` - Command latency histogram

## Extrapolation Methodology

For CPU-bound scenarios, the framework estimates performance on larger hardware:

```
extrapolated_rps = measured_rps × (target_cpus / test_cpus) × 0.85
```

Confidence levels based on MCP VM CPU utilization:
- **< 50%**: LOW - Not CPU bound, scaling may not help
- **50-80%**: MEDIUM - Likely to scale well
- **> 80%**: HIGH - Clearly CPU bound, scaling should improve

---

# Project Structure

```
ssh-tool/
├── bin/
│   └── ssh-automation              # CLI executable
├── lib/
│   ├── common/
│   │   ├── debug.tcl               # Debug/logging
│   │   ├── prompt.tcl              # Prompt detection
│   │   └── utils.tcl               # Utilities
│   ├── auth/
│   │   ├── password.tcl            # SSH password
│   │   └── sudo.tcl                # Sudo password
│   ├── connection/
│   │   └── ssh.tcl                 # SSH connection
│   └── commands/
│       ├── sudo_exec.tcl           # Sudo elevation
│       ├── hostname.tcl            # Hostname command
│       └── cat_file.tcl            # File reading
├── mcp/
│   ├── server.tcl                  # MCP server entry point
│   ├── lib/                        # 12 library modules
│   ├── agent/                      # TCL MCP client (simulated AI agent)
│   │   ├── http_client.tcl         # Pure TCL HTTP client
│   │   ├── json.tcl                # JSON parser/encoder
│   │   ├── mcp_client.tcl          # MCP protocol client
│   │   ├── e2e_test.tcl            # E2E test suite
│   │   └── loadtest/               # Load testing framework
│   │       ├── run.tcl             # Main entry point
│   │       ├── coordinator.tcl     # Multi-process orchestration
│   │       ├── worker.tcl          # Load generator process
│   │       ├── config.tcl          # Configuration
│   │       ├── scenarios/          # Test scenario definitions
│   │       ├── metrics/            # Metrics collection
│   │       └── output/             # Report generation
│   └── tests/                      # MCP test suites
├── nix/
│   ├── constants/                  # Shared configuration
│   │   ├── network.nix             # Network settings (3 VMs)
│   │   ├── ports.nix               # Port assignments
│   │   ├── users.nix               # Test users
│   │   ├── sshd.nix                # SSHD configurations
│   │   ├── netem.nix               # Network emulation
│   │   └── loadtest.nix            # Load test VM resources
│   ├── tests/
│   │   ├── e2e-test.nix            # E2E test runners
│   │   └── loadtest.nix            # Load test runners
│   ├── shell.nix                   # Development shell
│   ├── agent-vm.nix                # TCL agent MicroVM
│   ├── mcp-vm.nix                  # MCP server MicroVM
│   ├── ssh-target-vm.nix           # Multi-SSHD target MicroVM
│   ├── network-setup.nix           # TAP/bridge scripts
│   └── nixos-test.nix              # NixOS test framework (3 VMs)
├── tests/
│   ├── run_all_tests.sh            # CLI test runner
│   └── mock/                       # 11 CLI test files
├── flake.nix                       # Nix flake
└── README.md                       # This file
```

---

# How It Works

## Unique Prompt Injection

The core reliability feature. After SSH connection:

1. Disable terminal features that interfere (bracket-paste mode, colors)
2. Clear PS0, PS2, and PROMPT_COMMAND to prevent extra output
3. Disable systemd shell integration (OSC 3008 sequences on modern Fedora/RHEL)
4. Set a unique prompt: `XPCT<pid>>` (e.g., `XPCT12345>`)
5. All subsequent command output is captured between command echo and prompt

This works regardless of:
- Custom PS1 prompts (colors, git status, paths)
- Different shells (bash, zsh, sh, csh)
- ANSI escape codes and OSC sequences
- Systemd terminal integration (Fedora 43+)
- Varying prompt styles across Linux/FreeBSD/Darwin

## Command Output Capture

When running a command:

1. Send command + carriage return
2. Skip first line (command echo)
3. Strip ANSI/OSC escape sequences from each line
4. Capture all lines until prompt appears
5. Return captured lines joined with newlines

---

# Running Tests

## CLI Tests

```bash
# Run all CLI mock tests (62 tests)
./tests/run_all_tests.sh

# Run CLI real tests (requires SSH target)
SSH_HOST=192.168.1.100 PASSWORD=secret ./tests/real/run_real_tests.sh

# Shell script linting
./tests/run_shellcheck.sh
```

## MCP Tests

```bash
# Run all MCP mock tests (562 tests)
TCLSH=tclsh ./mcp/tests/run_all_tests.sh

# Run MCP tests including integration (requires SSH target)
SSH_HOST=192.168.1.100 PASSWORD=secret ./mcp/tests/run_all_tests.sh --all
```

## VM Integration Tests

```bash
# Option 1: Automated NixOS test (3 VMs, fully automated)
nix build .#checks.x86_64-linux.integration

# Option 2: Manual testing with TAP networking
sudo nix run .#ssh-network-setup
nix build .#ssh-target-vm-tap-debug && ./result/bin/microvm-run &
nix build .#mcp-vm-tap-debug && ./result/bin/microvm-run &
nix build .#agent-vm-tap-debug && ./result/bin/microvm-run  # Runs E2E tests

# Option 3: Single VM user-mode testing
nix build .#ssh-target-vm-debug
./result/bin/microvm-run &

# Test SSH (after VM boots ~30s)
SSHPASS=testpass sshpass -e ssh -p 2222 testuser@localhost hostname
```

## Test Coverage

All tests pass with Tcl 9.0 and expect-tcl9.

| Category | Tests | Status |
|----------|-------|--------|
| CLI mock tests | 62 | ✅ Pass |
| MCP mock tests | 562 | ✅ Pass |
| Shellcheck (scripts) | 24 | ✅ Pass |
| VM integration | 23 | ✅ Pass |
| **Total** | **671** | **✅ Pass** |

### CLI Test Breakdown

| Component | Tests |
|-----------|-------|
| debug.tcl | 6 |
| prompt.tcl | 6 |
| password.tcl | 6 |
| sudo.tcl | 6 |
| ssh.tcl | 5 |
| sudo_exec.tcl | 3 |
| hostname.tcl | 3 |
| cat_file.tcl | 6 |
| escape_sequences | 10 |
| timeouts | 5 |
| edge_cases | 6 |

### MCP Test Breakdown

| Component | Tests |
|-----------|-------|
| util.tcl | 14 |
| log.tcl | 18 |
| metrics.tcl | 16 |
| security.tcl | 129 |
| security_network.tcl | 176 |
| session.tcl | 32 |
| pool.tcl | 20 |
| jsonrpc.tcl | 40 |
| router.tcl | 13 |
| tools.tcl | 30 |
| tools_network.tcl | 31 |
| http.tcl | 27 |
| lifecycle.tcl | 16 |

### VM Integration Tests

| Test | Count |
|------|-------|
| Base SSH ports (2222-2228) | 7 |
| Netem ports (2322-2328) | 7 |
| Root login scenarios | 2 |
| Multi-user auth | 5 |
| File access | 2 |

### Agent E2E Tests

| Test | Description |
|------|-------------|
| Health check | MCP server /health endpoint |
| Initialize | MCP session initialization |
| Tools list | Verify available tools |
| SSH connect | Connect to target via MCP |
| SSH hostname | Run hostname command |
| SSH run command | Execute whoami, uname |
| SSH cat file | Read /etc/hostname, /etc/os-release |
| SSH disconnect | Clean session teardown |
| Security: blocked cmd | Verify rm, etc. are blocked |
| Security: metacharacters | Verify ; && \| are blocked |

---

# Known Limitations

1. **Password-only authentication** - No SSH key support yet
2. **Read-only operations** - MCP server only allows read commands
3. **No file upload** - Only reading via `cat`
4. **Linux-focused testing** - Real tests on Fedora; FreeBSD/Darwin via mock
5. **No Windows support** - Requires POSIX environment

---

# License

See LICENSE file.

# Contributing

1. Ensure all tests pass: `./tests/run_all_tests.sh` and `./mcp/tests/run_all_tests.sh`
2. Ensure shellcheck passes: `./tests/run_shellcheck.sh`
3. Add tests for new functionality
4. Update design docs for architectural changes
5. Format Nix files: `nix fmt`
