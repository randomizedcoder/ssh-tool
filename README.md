# SSH Automation Tool

A modular TCL/Expect framework for SSH automation with robust prompt detection. Includes both a CLI tool and an MCP (Model Context Protocol) server for LLM-driven automation.

## Overview

This project provides two ways to automate SSH tasks:

1. **CLI Tool** (`bin/ssh-automation`) - Direct command-line SSH automation
2. **MCP Server** (`mcp/server.tcl`) - HTTP server exposing SSH tools via JSON-RPC for LLM integration

Both share the same core libraries and use **unique prompt injection** - after connecting, a predictable prompt (`XPCT<pid>>`) is set that can be reliably detected regardless of the remote system's shell configuration.

## Requirements

- **expect** - TCL/Expect interpreter (Tcl 8.6+)
- **bash** - For test scripts
- **shellcheck** - For shell script linting (optional)

Install on Fedora:
```bash
sudo dnf install expect shellcheck
```

Install on Debian/Ubuntu:
```bash
sudo apt install expect shellcheck
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

# With explicit user
./bin/ssh-automation --host 192.168.1.100 --user admin --filename /etc/os-release

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
│   ├── lib/
│   │   ├── util.tcl                # Utilities
│   │   ├── log.tcl                 # Structured JSON logging
│   │   ├── metrics.tcl             # Prometheus metrics
│   │   ├── security.tcl            # Command/path validation
│   │   ├── session.tcl             # SSH session tracking
│   │   ├── mcp_session.tcl         # MCP session management
│   │   ├── pool.tcl                # Connection pooling
│   │   ├── jsonrpc.tcl             # JSON-RPC 2.0 + JSON parser
│   │   ├── router.tcl              # Method routing
│   │   ├── tools.tcl               # MCP tool implementations
│   │   ├── http.tcl                # HTTP/1.1 server
│   │   └── lifecycle.tcl           # Graceful shutdown
│   ├── tests/
│   │   ├── run_all_tests.sh        # MCP test runner
│   │   ├── mock/                   # 11 unit test files
│   │   └── real/                   # Integration tests
│   └── LOG.md                      # Implementation log
├── tests/
│   ├── run_all_tests.sh            # CLI test runner
│   ├── mock/                       # CLI mock tests
│   └── real/                       # CLI real tests
├── DESIGN.md                       # CLI design document
├── DESIGN_MCP.md                   # MCP design document
├── IMPLEMENTATION_PLAN.md          # MCP implementation plan
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
# Run all CLI mock tests
./tests/run_all_tests.sh

# Run CLI real tests (requires SSH target)
SSH_HOST=192.168.1.100 PASSWORD=secret ./tests/real/run_real_tests.sh

# Shell script linting
./tests/run_shellcheck.sh
```

## MCP Tests

```bash
# Run all MCP mock tests
TCLSH=tclsh ./mcp/tests/run_all_tests.sh

# Run MCP tests including integration (requires SSH target)
SSH_HOST=192.168.1.100 PASSWORD=secret ./mcp/tests/run_all_tests.sh --all

# Run MCP security tests directly
SSH_HOST=192.168.1.100 PASSWORD=secret ./mcp/tests/real/test_security_e2e.sh
```

## Test Coverage

### CLI Tests

| Component | Tests | Status |
|-----------|-------|--------|
| debug.tcl | 6 | Pass |
| prompt.tcl | 6 | Pass |
| password.tcl | 6 | Pass |
| sudo.tcl | 6 | Pass |
| ssh.tcl | 5 | Pass |
| sudo_exec.tcl | 3 | Pass |
| hostname.tcl | 3 | Pass |
| cat_file.tcl | 6 | Pass |
| escape_sequences | 10 | Pass |
| timeouts | 5 | Pass |
| edge_cases | 6 | Pass |
| **Real tests** | 21 | Pass |

### MCP Tests

| Component | Tests | Status |
|-----------|-------|--------|
| util.tcl | 14 | Pass |
| log.tcl | 18 | Pass |
| metrics.tcl | 16 | Pass |
| security.tcl | 129 | Pass |
| session.tcl | 32 | Pass |
| pool.tcl | 20 | Pass |
| jsonrpc.tcl | 40 | Pass |
| router.tcl | 13 | Pass |
| tools.tcl | 30 | Pass |
| http.tcl | 27 | Pass |
| lifecycle.tcl | 16 | Pass |

**Total: 355 MCP tests + 83 CLI tests = 438 tests passing**

---

# Known Limitations

1. **Password-only authentication** - No SSH key support
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
