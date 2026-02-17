# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SSH Automation Framework with two components:
- **CLI Tool** (`bin/ssh-automation`) - Direct TCL/Expect SSH automation
- **MCP Server** (`mcp/server.tcl`) - HTTP/JSON-RPC server exposing SSH tools to LLMs

Core innovation: **Unique Prompt Injection** - sets a predictable prompt (`XPCT<pid>>`) after SSH connection, enabling reliable output capture regardless of remote shell configuration.

## Build & Test Commands

```bash
# Development environment (recommended)
nix develop

# CLI tests (62 tests)
./tests/run_all_tests.sh

# MCP tests (562 tests)
./mcp/tests/run_all_tests.sh

# Shell script linting
./tests/run_shellcheck.sh

# Real SSH tests (requires target)
SSH_HOST=192.168.1.100 PASSWORD=secret ./tests/real/run_real_tests.sh

# Nix integration test (3-VM automated test)
nix build .#checks.x86_64-linux.integration

# Format Nix files
nix fmt
```

## Running the Tools

```bash
# CLI tool
PASSWORD=secret ./bin/ssh-automation --host 192.168.1.100 --filename /etc/os-release

# MCP server
./mcp/server.tcl --port 3000 --bind 127.0.0.1 --debug INFO
```

## Architecture

### Core Libraries (`lib/`)
Shared TCL/Expect modules:
- `common/prompt.tcl` - Prompt injection engine (the core innovation)
- `common/debug.tcl` - Logging (levels 0-7)
- `connection/ssh.tcl` - SSH connection management
- `auth/password.tcl`, `auth/sudo.tcl` - Authentication handling
- `commands/*.tcl` - Command execution (sudo_exec, hostname, cat_file)

### MCP Server (`mcp/`)
- `server.tcl` - Entry point
- `lib/security.tcl` - **Critical**: command allowlist, path validation, rate limiting
- `lib/tools.tcl` - SSH tool definitions (ssh_connect, ssh_run_command, etc.)
- `lib/jsonrpc.tcl` - JSON-RPC 2.0 handler
- `lib/http.tcl` - HTTP/1.1 server
- `lib/session.tcl`, `lib/pool.tcl` - Session/connection management
- `agent/` - Pure TCL MCP client for E2E testing

### Nix Infrastructure (`nix/`)
3-VM test architecture:
- **Agent VM** (10.178.0.5) - TCL test client
- **MCP VM** (10.178.0.10) - MCP server on port 3000
- **Target VM** (10.178.0.20) - Multiple SSHD instances (ports 2222-2228)

Constants in `nix/constants/` define network topology, ports, users, and SSHD configs.

## MCP Security Model

The MCP server is **read-only by design**:
- **Allowlisted commands only**: `ls`, `cat`, `head`, `tail`, `grep`, `ps`, `df`, `hostname`, `uname`, etc.
- **Blocked**: `rm`, `chmod`, `sudo`, `bash`, `python`, `curl`, `wget`, and all write operations
- **Shell metacharacters blocked**: `|`, `;`, `&&`, `||`, `` ` ``, `$()`, `>`, `<`
- **Path validation**: Only `/etc`, `/var/log`, `/home`, `/tmp`, `/opt`, `/usr/share`, `/proc`, `/sys`
- **Rate limiting**: 100 requests/minute per client

## Network Commands

The MCP server supports network inspection commands for system administration:

### Allowed Commands
- `ip -j link/addr/route/rule/neigh show` - Interface and routing info (JSON)
- `ethtool -S/-i/-k <iface>` - Interface stats (read-only flags only)
- `tc -j qdisc/class/filter show` - Traffic control
- `nft -j list ruleset/tables` - Firewall rules
- `ping -c [1-5]`, `traceroute -m [1-15]` - Connectivity tests (limited)
- `dig`, `nslookup`, `host` - DNS queries (A/AAAA only)

### Blocked Commands
- Any modification: `ip link set`, `tc add`, `nft add`, etc.
- Dangerous ethtool flags: `-E`, `-f`, `-W` (hardware modification)
- Unlimited ping/traceroute (max 5 packets, 15 hops)
- DNS zone transfers, reverse lookups

### High-Level Network Tools
- `ssh_network_interfaces` - Interfaces with statistics
- `ssh_network_routes` - Routing tables (IPv4/IPv6)
- `ssh_network_firewall` - Auto-detects nft/iptables
- `ssh_network_qdisc` - Traffic control qdiscs
- `ssh_network_connectivity` - Ping/DNS/traceroute tests
- `ssh_batch_commands` - Up to 5 commands per batch

## Testing Strategy

- **Mock tests**: Use `mock_ssh.tcl` to simulate SSH sessions (no network required)
- **Real tests**: Require SSH target with `SSH_HOST`, `PASSWORD` env vars
- **VM tests**: NixOS MicroVMs with TAP networking for full integration testing

Test files follow the pattern `tests/mock/test_*.sh` (CLI) and `mcp/tests/mock/test_*.tcl` (MCP).

## Code Quality Requirements

**All shell scripts must pass shellcheck with zero warnings or errors.**

- Run `./tests/run_shellcheck.sh` before committing
- Never disable shellcheck warnings - fix the code instead
- Use `# shellcheck source=filename.sh` directive when sourcing files
- Use long-form arguments for clarity (e.g., `--external-sources` not `-x`)

## Dependencies

- **Tcl 9.0** - All components use Tcl 9.0 (`tcl-9_0` in nixpkgs)
- **expect-tcl9** - Expect built against Tcl 9.0 (local build in `nix/expect-tcl9/`, PR #490930 pending)
- **bash** - Test scripts
- **shellcheck** - Linting (required, must pass with zero warnings)
- **nix** - Reproducible builds (recommended)
