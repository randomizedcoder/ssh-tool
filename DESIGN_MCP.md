# Design Document: MCP Server for SSH Automation

## Overview

This document describes the design for a Model Context Protocol (MCP) server that exposes the SSH automation framework to Large Language Models (LLMs). The server provides an HTTP-based API that allows LLMs to connect to remote hosts, execute commands, read files, and perform administrative tasks via SSH.

## Security Architecture: Telnet-Like SSH Proxy Model

### Why Not Full SSH?

The SSH protocol supports many advanced features:

| SSH Feature | Description | Security Risk if Exposed to LLM |
|-------------|-------------|--------------------------------|
| **Port Forwarding** | `-L`, `-R`, `-D` tunnels | LLM could create backdoors, pivot to internal networks |
| **X11 Forwarding** | GUI application tunneling | Attack surface, potential code execution |
| **Agent Forwarding** | Pass-through authentication | Credential theft, lateral movement |
| **SFTP/SCP** | File transfer subsystem | Arbitrary file upload, malware deployment |
| **Multiple Channels** | Concurrent sessions in one connection | Bypass monitoring, side-channel attacks |
| **Escape Sequences** | `~.`, `~C` shell escapes | Break out of controlled session |
| **Pseudo-TTY Allocation** | Full interactive terminal | Interactive exploits, escape sequences |
| **ProxyJump** | Multi-hop SSH | Pivot through jump hosts |

**Exposing these features to an LLM would be extremely dangerous.**

### Our Approach: Telnet-Like Simplicity

Instead of exposing SSH's full capabilities, we treat the connection as a **simple text-based command/response channel** - conceptually similar to Telnet, but using SSH for transport security:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SECURITY BOUNDARY                               │
│                                                                         │
│  ┌─────────────┐       ┌─────────────────────────┐       ┌───────────┐  │
│  │             │       │     MCP Server          │       │           │  │
│  │  LLM/Client │──────▶│  ┌─────────────────┐    │──────▶│   Remote  │  │
│  │             │ HTTP  │  │ Security Filter │    │  SSH  │   Host    │  │
│  │             │◀──────│  │ - Command Check │    │◀──────│           │  │
│  │             │ JSON  │  │ - Path Check    │    │ Text  │           │  │
│  └─────────────┘       │  │ - Rate Limit    │    │       └───────────┘  │
│                        │  └─────────────────┘    │                      │
│                        │                         │                      │
│                        │  ALL traffic proxied    │                      │
│                        │  ALL commands filtered  │                      │
│                        └─────────────────────────┘                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### What We DO Support

| Feature | Implementation | Security Control |
|---------|---------------|------------------|
| Command execution | `send "cmd\r"` via Expect | Command allowlist filter |
| File reading | `cat` command | Path allowlist + realpath check |
| Output capture | Line-by-line via Expect | Logged, size-limited |
| Session management | spawn_id tracking | Session limits, timeouts |

### What We DO NOT Support (By Design)

| Feature | Status | Reason |
|---------|--------|--------|
| Port forwarding | **BLOCKED** | No `-L`, `-R`, `-D` flags passed to SSH |
| X11 forwarding | **BLOCKED** | No `-X` flag, `DISPLAY` not set |
| Agent forwarding | **BLOCKED** | No `-A` flag, `SSH_AUTH_SOCK` not passed |
| SFTP/SCP | **BLOCKED** | No subsystem access, only shell |
| ProxyJump | **BLOCKED** | No `-J` flag, direct connections only |
| Escape sequences | **BLOCKED** | Not a real PTY, Expect filters escapes |
| Arbitrary SSH options | **BLOCKED** | SSH invoked with hardcoded safe options |
| Multiple channels | **BLOCKED** | One shell channel per spawn_id |
| Raw file transfer | **BLOCKED** | Only `cat` for reading, no writing |

### SSH Invocation

We invoke SSH with minimal, security-hardened options:

```tcl
proc connect {host user password {insecure 0}} {
    # Security: Explicit options, no config file, no agent
    set ssh_opts [list \
        -o "BatchMode=no" \
        -o "ForwardAgent=no" \
        -o "ForwardX11=no" \
        -o "PermitLocalCommand=no" \
        -o "Tunnel=no" \
        -o "ClearAllForwardings=yes" \
        -o "UpdateHostKeys=no" \
        -F "/dev/null" \
    ]

    if {$insecure} {
        lappend ssh_opts \
            -o "StrictHostKeyChecking=no" \
            -o "UserKnownHostsFile=/dev/null"
    }

    spawn ssh {*}$ssh_opts $user@$host

    # No PTY allocation (-T could be added for extra safety)
    # Shell session only - no subsystems
}
```

### Why This Matters

1. **Complete Visibility**: Every command the LLM executes goes through our filter
2. **No Hidden Channels**: No port forwarding = no covert communication
3. **No File Upload**: Read-only access prevents malware deployment
4. **No Credential Theft**: No agent forwarding = no key extraction
5. **Auditable**: All I/O logged and rate-limited
6. **Containable**: Single session, single channel, no pivoting

### Trade-offs

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| No file upload | Can't deploy configs | Use external tools, or add explicit upload tool with strict validation |
| No interactive commands | Can't run `vim`, `top -i` | Use non-interactive equivalents (`top -bn1`) |
| No tunneling | Can't access internal services | By design - forces explicit access |
| Command overhead | Each command is a round-trip | Connection pooling reduces impact |

## MCP Session Model

MCP defines a [lifecycle](https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle) with three phases: **Initialization** → **Operation** → **Shutdown**. Our design involves two distinct session layers:

```
┌─────────────────────────────────────────────────────────────────┐
│                    LLM Client (Claude, etc.)                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ MCP Session (Mcp-Session-Id header)
                              │ - One per LLM conversation
                              │ - Stateful: tracks which SSH sessions belong to this client
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       MCP Server (This)                         │
│                                                                 │
│  MCP Session State:                                             │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ mcp_session_abc123:                                     │    │
│  │   ssh_sessions: [sess_001, sess_002]                    │    │
│  │   created: 2024-01-15T10:00:00Z                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ SSH Sessions (session_id in tool params)
                              │ - Multiple per MCP session
                              │ - Stateful: maintains SSH connection + prompt state
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Remote SSH Hosts                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │ sess_001     │  │ sess_002     │  │ sess_003     │           │
│  │ admin@host1  │  │ root@host1   │  │ admin@host2  │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

### Layer 1: MCP Session (Client ↔ MCP Server)

The protocol-level session between the LLM client and our MCP server:

| Aspect | Description |
|--------|-------------|
| **Identifier** | `Mcp-Session-Id` HTTP header (generated on `initialize`) |
| **Lifecycle** | Created at `initialize`, destroyed at connection close |
| **State** | List of SSH sessions owned by this client |
| **Purpose** | Track which SSH sessions belong to which LLM conversation |

This follows the [Streamable HTTP transport](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports) pattern where sessions are identified by a header.

### Layer 2: SSH Session (MCP Server ↔ Remote Host)

The application-level sessions representing active SSH connections:

| Aspect | Description |
|--------|-------------|
| **Identifier** | `session_id` in tool parameters (e.g., `sess_a1b2c3d4`) |
| **Lifecycle** | Created by `ssh_connect`, destroyed by `ssh_disconnect` or timeout |
| **State** | spawn_id, prompt marker, is_root, connection info |
| **Purpose** | Maintain persistent SSH connection for multiple commands |

This pattern matches the existing [SSH-MCP server](https://lib.rs/crates/ssh-mcp) implementation.

### Stateless vs Stateful Tools

MCP supports both patterns. Our design uses:

| Tool | Pattern | Rationale |
|------|---------|-----------|
| `ssh_connect` | Stateful | Creates persistent SSH session |
| `ssh_run_command` | Stateful | Requires existing session_id |
| `ssh_disconnect` | Stateful | Closes existing session |
| `ssh_run` | Stateless | Acquires from pool, runs, releases (one-shot) |
| `ssh_pool_stats` | Stateless | Read-only, no session needed |

**Stateless tools** (like `ssh_run`) follow the [recommended MCP pattern](https://docs.langchain.com/oss/python/langchain/mcp) where each call is independent. They use connection pooling internally but don't expose session state to the LLM.

**Stateful tools** (like `ssh_run_command`) are needed for multi-step workflows:
- Elevate to root, then run privileged commands
- Change directory, then run commands in that directory
- Maintain environment variables across commands

### MCP Session Cleanup

When an MCP session ends (client disconnects or times out), we clean up associated SSH sessions:

```tcl
proc mcp_session::cleanup {mcp_session_id} {
    variable sessions

    if {![dict exists $sessions $mcp_session_id]} {
        return
    }

    set data [dict get $sessions $mcp_session_id]
    set ssh_sessions [dict get $data ssh_sessions]

    # Close all SSH sessions owned by this MCP session
    foreach ssh_sid $ssh_sessions {
        catch {session::disconnect $ssh_sid}
    }

    dict unset sessions $mcp_session_id
    debug::log 3 "MCP session $mcp_session_id cleaned up ([llength $ssh_sessions] SSH sessions closed)"
}
```

### Mcp-Session-Id Header

For HTTP transport, we support the `Mcp-Session-Id` header:

```tcl
proc handle_request {sock headers body} {
    # Check for existing MCP session
    set mcp_sid ""
    if {[dict exists $headers mcp-session-id]} {
        set mcp_sid [dict get $headers mcp-session-id]
        if {![mcp_session::exists $mcp_sid]} {
            # Invalid session ID
            return [send_http_error $sock 400 "Invalid Mcp-Session-Id"]
        }
    }

    # Parse JSON-RPC
    set req [json::json2dict $body]
    set method [dict get $req method]

    # Initialize creates new MCP session
    if {$method eq "initialize"} {
        set mcp_sid [mcp_session::create]
        set response [handle_initialize $req]
        return [send_http_200 $sock $response [dict create Mcp-Session-Id $mcp_sid]]
    }

    # Other methods require valid session
    if {$mcp_sid eq ""} {
        return [send_http_error $sock 400 "Missing Mcp-Session-Id header"]
    }

    # ... dispatch to method handler
}
```

## Goals

1. **Enable LLM Access** - Allow LLMs to use SSH automation capabilities via MCP protocol
2. **Session Management** - Support multiple concurrent SSH sessions with proper lifecycle
3. **Structured Responses** - Encapsulate SSH output in well-defined JSON responses
4. **Testability** - Full test coverage with both mock and real servers
5. **Use Standard Libraries** - Leverage Tcllib for HTTP and JSON handling

## Dependencies

| Package | Tcllib Module | Purpose |
|---------|---------------|---------|
| `json` | tcllib/json | Parse JSON requests |
| `json::write` | tcllib/json | Generate JSON responses |
| `httpd` | tcllib/httpd | HTTP server (TclOO-based) |

**Requirements:**
- Tcl 8.6+ (required by tcllib httpd)
- Tcllib 1.18+ (for json and httpd modules)
- Expect (for SSH automation)

**Install on Fedora:**
```bash
sudo dnf install tcl tcllib expect
```

**Install on Debian/Ubuntu:**
```bash
sudo apt install tcl tcllib expect
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         LLM / Client                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP (JSON-RPC 2.0)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       MCP Server (TCL)                          │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   HTTP Handler                           │    │
│  │  - Parse JSON-RPC requests                               │    │
│  │  - Route to tool handlers                                │    │
│  │  - Format JSON-RPC responses                             │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                 Session Manager                          │    │
│  │  - Track active SSH sessions                             │    │
│  │  - Map session_id → spawn_id                             │    │
│  │  - Session timeouts and cleanup                          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │               Tool Handlers (MCP Tools)                  │    │
│  │  - ssh_connect       - ssh_run_command                   │    │
│  │  - ssh_cat_file      - ssh_hostname                      │    │
│  │  - ssh_sudo_elevate  - ssh_disconnect                    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
└──────────────────────────────│───────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Existing SSH Automation Lib                   │
│  lib/connection/ssh.tcl   lib/commands/*.tcl                    │
│  lib/common/prompt.tcl    lib/auth/*.tcl                        │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ SSH
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Remote SSH Hosts                           │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
ssh-tool/
├── mcp/
│   ├── server.tcl              # Main MCP server executable
│   ├── lib/
│   │   ├── jsonrpc.tcl         # JSON-RPC 2.0 handler (uses tcllib json)
│   │   ├── session.tcl         # SSH session manager
│   │   ├── pool.tcl            # Connection pooling
│   │   ├── tools.tcl           # MCP tool definitions and handlers
│   │   ├── log.tcl             # Structured JSON logging
│   │   ├── metrics.tcl         # Prometheus metrics (/metrics endpoint)
│   │   ├── security.tcl        # Path/command validation, allowlists
│   │   └── lifecycle.tcl       # Signal handling, graceful shutdown
│   ├── config/
│   │   └── allowlist.conf      # Command allowlist (optional)
│   └── tests/
│       ├── run_mcp_tests.sh    # MCP test runner
│       ├── mock/
│       │   ├── test_jsonrpc.sh     # JSON-RPC tests
│       │   ├── test_session.sh     # Session manager tests
│       │   ├── test_pool.sh        # Connection pool tests
│       │   ├── test_security.sh    # Security validation tests
│       │   ├── test_tools.sh       # Tool handler tests
│       │   └── helpers/
│       │       └── mock_mcp_server.tcl  # Mock MCP server for client tests
│       ├── real/
│       │   ├── test_mcp_connect.sh     # Real SSH via MCP
│       │   ├── test_mcp_commands.sh    # Commands via MCP
│       │   ├── test_mcp_session.sh     # Session lifecycle
│       │   └── test_mcp_pool.sh        # Pool behavior tests
│       └── client/
│           ├── mcp_client.sh           # Test client (curl-based)
│           └── mcp_client.tcl          # Test client (TCL)
```

## MCP Protocol

### Transport

The MCP server uses HTTP as the transport layer:

- **Protocol**: HTTP/1.1
- **Port**: Configurable (default: 3000)
- **Content-Type**: application/json
- **Method**: POST for JSON-RPC, GET for health

### JSON-RPC 2.0 Format

All MCP communication uses JSON-RPC 2.0:

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "ssh_connect",
    "arguments": {
      "host": "192.168.1.100",
      "user": "admin",
      "password": "secret"
    }
  }
}
```

**Response (Success):**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Connected to 192.168.1.100"
      }
    ],
    "session_id": "sess_abc123"
  }
}
```

**Response (Error):**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32000,
    "message": "SSH connection failed: Permission denied"
  }
}
```

## MCP Methods

### Core Methods

| Method | Description |
|--------|-------------|
| `initialize` | Initialize MCP session, exchange capabilities |
| `tools/list` | List available tools and their schemas |
| `tools/call` | Execute a tool with arguments |

### Initialize

Called once when client connects:

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "clientInfo": {
      "name": "claude-code",
      "version": "1.0.0"
    }
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "serverInfo": {
      "name": "ssh-automation-mcp",
      "version": "1.0.0"
    },
    "capabilities": {
      "tools": {}
    }
  }
}
```

### Tools List

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list"
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "ssh_connect",
        "description": "Connect to a remote host via SSH",
        "inputSchema": {
          "type": "object",
          "properties": {
            "host": {"type": "string", "description": "Hostname or IP address"},
            "user": {"type": "string", "description": "SSH username"},
            "password": {"type": "string", "description": "SSH password"},
            "insecure": {"type": "boolean", "description": "Skip host key verification"}
          },
          "required": ["host", "password"]
        }
      },
      {
        "name": "ssh_run_command",
        "description": "Execute a command on a connected SSH session",
        "inputSchema": {
          "type": "object",
          "properties": {
            "session_id": {"type": "string", "description": "SSH session ID"},
            "command": {"type": "string", "description": "Command to execute"}
          },
          "required": ["session_id", "command"]
        }
      },
      {
        "name": "ssh_cat_file",
        "description": "Read a file from the remote host",
        "inputSchema": {
          "type": "object",
          "properties": {
            "session_id": {"type": "string", "description": "SSH session ID"},
            "path": {"type": "string", "description": "File path to read"}
          },
          "required": ["session_id", "path"]
        }
      },
      {
        "name": "ssh_hostname",
        "description": "Get the hostname of the connected host",
        "inputSchema": {
          "type": "object",
          "properties": {
            "session_id": {"type": "string", "description": "SSH session ID"},
            "fqdn": {"type": "boolean", "description": "Return fully qualified domain name"}
          },
          "required": ["session_id"]
        }
      },
      {
        "name": "ssh_sudo_elevate",
        "description": "Elevate to root privileges via sudo",
        "inputSchema": {
          "type": "object",
          "properties": {
            "session_id": {"type": "string", "description": "SSH session ID"},
            "password": {"type": "string", "description": "Sudo password"}
          },
          "required": ["session_id", "password"]
        }
      },
      {
        "name": "ssh_disconnect",
        "description": "Close an SSH session",
        "inputSchema": {
          "type": "object",
          "properties": {
            "session_id": {"type": "string", "description": "SSH session ID"}
          },
          "required": ["session_id"]
        }
      },
      {
        "name": "ssh_list_sessions",
        "description": "List all active SSH sessions",
        "inputSchema": {
          "type": "object",
          "properties": {}
        }
      },
      {
        "name": "ssh_run",
        "description": "Run command using pooled connection (implicit session)",
        "inputSchema": {
          "type": "object",
          "properties": {
            "host": {"type": "string", "description": "Hostname or IP"},
            "user": {"type": "string", "description": "SSH username"},
            "password": {"type": "string", "description": "SSH password"},
            "command": {"type": "string", "description": "Command to execute"},
            "insecure": {"type": "boolean", "description": "Skip host key verification"}
          },
          "required": ["host", "password", "command"]
        }
      },
      {
        "name": "ssh_pool_stats",
        "description": "Get connection pool statistics",
        "inputSchema": {
          "type": "object",
          "properties": {
            "host": {"type": "string", "description": "Filter by host (optional)"}
          }
        }
      },
      {
        "name": "ssh_pool_warmup",
        "description": "Pre-create connections to a host",
        "inputSchema": {
          "type": "object",
          "properties": {
            "host": {"type": "string", "description": "Hostname or IP"},
            "user": {"type": "string", "description": "SSH username"},
            "password": {"type": "string", "description": "SSH password"},
            "count": {"type": "integer", "description": "Number of connections to create"}
          },
          "required": ["host", "password", "count"]
        }
      },
      {
        "name": "ssh_pool_drain",
        "description": "Close all idle connections to a host",
        "inputSchema": {
          "type": "object",
          "properties": {
            "host": {"type": "string", "description": "Hostname or IP (all hosts if omitted)"}
          }
        }
      }
    ]
  }
}
```

## Tool Definitions

### ssh_connect

Establish an SSH connection to a remote host.

**Input:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `host` | string | Yes | - | Hostname or IP address |
| `user` | string | No | `$USER` | SSH username |
| `password` | string | Yes | - | SSH password |
| `insecure` | boolean | No | false | Skip host key verification |

**Output:**
```json
{
  "content": [
    {
      "type": "text",
      "text": "Connected to 192.168.1.100 as user 'admin'"
    }
  ],
  "session_id": "sess_a1b2c3d4"
}
```

**Errors:**
| Code | Message |
|------|---------|
| -32001 | Connection refused |
| -32002 | Authentication failed |
| -32003 | Connection timeout |
| -32004 | Host key verification failed |

### ssh_run_command

Execute a command on an active SSH session.

**Input:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | Yes | Session ID from ssh_connect |
| `command` | string | Yes | Command to execute |

**Output:**
```json
{
  "content": [
    {
      "type": "text",
      "text": "Linux\n"
    }
  ],
  "exit_code": 0
}
```

**Errors:**
| Code | Message |
|------|---------|
| -32010 | Session not found |
| -32011 | Session disconnected |
| -32012 | Command timeout |

### ssh_cat_file

Read a file from the remote host.

**Input:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | Yes | Session ID from ssh_connect |
| `path` | string | Yes | Absolute or relative file path |

**Output:**
```json
{
  "content": [
    {
      "type": "text",
      "text": "NAME=\"Fedora Linux\"\nVERSION=\"43 (Server Edition)\"\n..."
    }
  ],
  "bytes": 245
}
```

**Errors:**
| Code | Message |
|------|---------|
| -32010 | Session not found |
| -32020 | File not found |
| -32021 | Permission denied |
| -32022 | Invalid filename |

### ssh_hostname

Get the hostname of the connected host.

**Input:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `session_id` | string | Yes | - | Session ID from ssh_connect |
| `fqdn` | boolean | No | false | Return fully qualified domain name |

**Output:**
```json
{
  "content": [
    {
      "type": "text",
      "text": "webserver01"
    }
  ],
  "hostname": "webserver01"
}
```

### ssh_sudo_elevate

Elevate to root privileges via sudo.

**Input:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | Yes | Session ID from ssh_connect |
| `password` | string | Yes | Sudo password |

**Output:**
```json
{
  "content": [
    {
      "type": "text",
      "text": "Elevated to root"
    }
  ],
  "is_root": true
}
```

**Errors:**
| Code | Message |
|------|---------|
| -32010 | Session not found |
| -32030 | Sudo authentication failed |
| -32031 | User not in sudoers |

### ssh_disconnect

Close an SSH session.

**Input:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | Yes | Session ID to close |

**Output:**
```json
{
  "content": [
    {
      "type": "text",
      "text": "Session sess_a1b2c3d4 disconnected"
    }
  ]
}
```

### ssh_list_sessions

List all active SSH sessions.

**Input:** None

**Output:**
```json
{
  "content": [
    {
      "type": "text",
      "text": "2 active sessions"
    }
  ],
  "sessions": [
    {
      "session_id": "sess_a1b2c3d4",
      "host": "192.168.1.100",
      "user": "admin",
      "is_root": false,
      "connected_at": "2024-01-15T10:30:00Z"
    },
    {
      "session_id": "sess_e5f6g7h8",
      "host": "192.168.1.101",
      "user": "root",
      "is_root": true,
      "connected_at": "2024-01-15T10:35:00Z"
    }
  ]
}
```

## Session Management

### Session Lifecycle

```
┌──────────┐    ssh_connect    ┌──────────┐
│  None    │ ─────────────────▶│  Active  │
└──────────┘                   └──────────┘
                                    │
                 ┌──────────────────┼──────────────────┐
                 │                  │                  │
                 ▼                  ▼                  ▼
          ssh_disconnect      timeout            connection
                 │              drop                lost
                 │                  │                  │
                 ▼                  ▼                  ▼
            ┌──────────┐      ┌──────────┐      ┌──────────┐
            │  Closed  │      │  Expired │      │  Error   │
            └──────────┘      └──────────┘      └──────────┘
```

### Session Data Structure

```tcl
namespace eval session {
    # Map: session_id -> session data dict
    variable sessions

    # Session data dict structure:
    # {
    #   spawn_id    <expect spawn_id>
    #   host        "192.168.1.100"
    #   user        "admin"
    #   is_root     0|1
    #   created     <epoch timestamp>
    #   last_used   <epoch timestamp>
    #   in_use      0|1              # Currently handling a request
    #   pool_key    "user@host"      # For connection pooling
    # }
}
```

### Session ID Generation

Session IDs are generated using a combination of:
- Prefix: `sess_`
- Random hex: 8 characters from /dev/urandom or clock

```tcl
proc generate_session_id {} {
    set hex ""
    if {[file readable /dev/urandom]} {
        set f [open /dev/urandom r]
        fconfigure $f -translation binary
        set bytes [read $f 4]
        close $f
        binary scan $bytes H8 hex
    } else {
        set hex [format %08x [expr {int(rand() * 0xFFFFFFFF)}]]
    }
    return "sess_$hex"
}
```

### Session Timeout

Sessions have a configurable idle timeout (default: 30 minutes):

```tcl
variable session_timeout 1800  ;# 30 minutes in seconds

proc cleanup_expired_sessions {} {
    variable sessions
    variable session_timeout

    set now [clock seconds]
    set expired {}

    dict for {sid data} $sessions {
        set last_used [dict get $data last_used]
        if {($now - $last_used) > $session_timeout} {
            lappend expired $sid
        }
    }

    foreach sid $expired {
        disconnect $sid
    }
}
```

## Connection Pooling

SSH connection setup is expensive (TCP handshake, key exchange, authentication). For LLMs making parallel requests, we implement connection pooling similar to database connection pools.

### Pool Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Connection Pool                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Pool: admin@192.168.1.100                  │    │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │    │
│  │  │ sess_01 │ │ sess_02 │ │ sess_03 │ │ sess_04 │        │    │
│  │  │  idle   │ │ in_use  │ │  idle   │ │ in_use  │        │    │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Pool: root@192.168.1.101                   │    │
│  │  ┌─────────┐ ┌─────────┐                                │    │
│  │  │ sess_05 │ │ sess_06 │                                │    │
│  │  │  idle   │ │  idle   │                                │    │
│  │  └─────────┘ └─────────┘                                │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Pool Configuration

```tcl
namespace eval pool {
    # Per-host pool configuration
    variable config [dict create \
        min_connections     1    \
        max_connections     10   \
        spare_connections   2    \
        idle_timeout        1800 \
        connection_timeout  30   \
    ]

    # Map: pool_key -> list of session_ids
    variable pools

    # Map: pool_key -> pool stats
    # { total <n> idle <n> in_use <n> waiting <n> }
    variable stats
}
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `min_connections` | 1 | Minimum connections to maintain per host |
| `max_connections` | 10 | Maximum connections per host |
| `spare_connections` | 2 | Idle connections to keep ready |
| `idle_timeout` | 1800s | Close idle connections after this time |
| `connection_timeout` | 30s | Timeout for new connection attempts |

### Pool Operations

```tcl
# Acquire a connection from pool (or create new)
proc pool::acquire {host user password {insecure 0}} {
    variable pools
    variable config

    set pool_key "$user@$host"

    # Try to get an idle connection from existing pool
    if {[dict exists $pools $pool_key]} {
        set session_id [find_idle_session $pool_key]
        if {$session_id ne ""} {
            mark_in_use $session_id
            return $session_id
        }
    }

    # Check if we can create a new connection
    set current [pool_size $pool_key]
    set max [dict get $config max_connections]

    if {$current >= $max} {
        # Pool exhausted - wait or error
        error "Connection pool exhausted for $pool_key (max: $max)"
    }

    # Create new connection
    set session_id [create_connection $host $user $password $insecure]
    add_to_pool $pool_key $session_id

    return $session_id
}

# Release connection back to pool
proc pool::release {session_id} {
    variable config

    set session [session::get $session_id]
    if {$session eq ""} return

    # Mark as idle, update last_used
    session::update $session_id [dict create \
        in_use 0 \
        last_used [clock seconds] \
    ]

    # Trigger spare connection cleanup if over limit
    after idle [list pool::maintain [dict get $session pool_key]]
}

# Maintain pool size (scale up/down)
proc pool::maintain {pool_key} {
    variable config
    variable pools

    set min [dict get $config min_connections]
    set spare [dict get $config spare_connections]

    set stats [get_pool_stats $pool_key]
    set idle [dict get $stats idle]
    set total [dict get $stats total]

    # Scale down: too many idle connections
    if {$idle > $spare && $total > $min} {
        set excess [expr {$idle - $spare}]
        close_idle_connections $pool_key $excess
    }

    # Scale up: ensure minimum connections
    if {$total < $min} {
        # Would need stored credentials - see note below
    }
}
```

### Connection Pool Modes

Two modes of operation:

#### Mode 1: Explicit Sessions (Current Design)
LLM manages session lifecycle explicitly:
```json
{"method": "tools/call", "params": {"name": "ssh_connect", ...}}
// Returns session_id, LLM reuses it for subsequent calls
{"method": "tools/call", "params": {"name": "ssh_run_command", "arguments": {"session_id": "sess_abc"}}}
```

#### Mode 2: Implicit Pooling (Simplified)
Server manages pool transparently - LLM doesn't see session_ids:
```json
{"method": "tools/call", "params": {"name": "ssh_run", "arguments": {
    "host": "192.168.1.100",
    "user": "admin",
    "password": "secret",
    "command": "hostname"
}}}
```
Server acquires connection from pool, runs command, releases back.

**Recommendation**: Support both modes:
- Explicit for complex multi-command workflows (sudo elevation, stateful operations)
- Implicit for simple one-off commands (file reads, quick checks)

### New Tools for Pool Management

| Tool | Description |
|------|-------------|
| `ssh_pool_stats` | Get pool statistics per host |
| `ssh_pool_warmup` | Pre-create connections to a host |
| `ssh_pool_drain` | Close all idle connections to a host |

```json
{
  "name": "ssh_pool_stats",
  "description": "Get connection pool statistics",
  "inputSchema": {
    "type": "object",
    "properties": {
      "host": {"type": "string", "description": "Filter by host (optional)"}
    }
  }
}
```

**Response:**
```json
{
  "content": [{"type": "text", "text": "2 pools, 6 total connections"}],
  "pools": {
    "admin@192.168.1.100": {"total": 4, "idle": 2, "in_use": 2},
    "root@192.168.1.101": {"total": 2, "idle": 2, "in_use": 0}
  }
}
```

## Binary Payload Handling

For reading binary files (images, compiled binaries, archives), we need to handle non-text content.

### Encoding Strategy

| Content Type | Encoding | Use Case |
|--------------|----------|----------|
| Text | Plain UTF-8 | Small text files, command output |
| Binary | Base64 | Images, binaries, archives |
| Auto | Detect | Server decides based on content |

### Detection Heuristics

```tcl
proc is_binary_content {data} {
    # Check for null bytes (strong binary indicator)
    if {[string first "\x00" $data] >= 0} {
        return 1
    }

    # Check ratio of non-printable characters
    set len [string length $data]
    if {$len == 0} { return 0 }

    set non_printable 0
    foreach char [split $data ""] {
        scan $char %c code
        # Count bytes outside printable ASCII + common whitespace
        if {$code < 9 || ($code > 13 && $code < 32) || $code > 126} {
            incr non_printable
        }
    }

    # If more than 10% non-printable, treat as binary
    return [expr {double($non_printable) / $len > 0.10}]
}
```

### Updated Tool Schemas

#### ssh_cat_file (Enhanced)

```json
{
  "name": "ssh_cat_file",
  "description": "Read a file from the remote host",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string", "description": "SSH session ID"},
      "path": {"type": "string", "description": "File path to read"},
      "encoding": {
        "type": "string",
        "enum": ["text", "base64", "auto"],
        "default": "auto",
        "description": "Output encoding: text (UTF-8), base64, or auto-detect"
      },
      "max_size": {
        "type": "integer",
        "default": 1048576,
        "description": "Maximum file size in bytes (default 1MB)"
      }
    },
    "required": ["session_id", "path"]
  }
}
```

**Response (text):**
```json
{
  "content": [
    {
      "type": "text",
      "text": "NAME=\"Fedora Linux\"\nVERSION=\"43\"\n"
    }
  ],
  "encoding": "text",
  "bytes": 45,
  "mime_type": "text/plain"
}
```

**Response (binary/base64):**
```json
{
  "content": [
    {
      "type": "text",
      "text": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ..."
    }
  ],
  "encoding": "base64",
  "bytes": 2048,
  "mime_type": "image/png"
}
```

### MIME Type Detection

```tcl
proc detect_mime_type {filename data} {
    # Check by extension first
    set ext [string tolower [file extension $filename]]
    set mime_by_ext [dict create \
        .txt  "text/plain" \
        .json "application/json" \
        .xml  "application/xml" \
        .html "text/html" \
        .css  "text/css" \
        .js   "application/javascript" \
        .png  "image/png" \
        .jpg  "image/jpeg" \
        .jpeg "image/jpeg" \
        .gif  "image/gif" \
        .pdf  "application/pdf" \
        .gz   "application/gzip" \
        .tar  "application/x-tar" \
        .zip  "application/zip" \
    ]

    if {[dict exists $mime_by_ext $ext]} {
        return [dict get $mime_by_ext $ext]
    }

    # Check magic bytes
    if {[string range $data 0 3] eq "\x89PNG"} { return "image/png" }
    if {[string range $data 0 1] eq "\xFF\xD8"} { return "image/jpeg" }
    if {[string range $data 0 3] eq "GIF8"} { return "image/gif" }
    if {[string range $data 0 3] eq "%PDF"} { return "application/pdf" }
    if {[string range $data 0 1] eq "\x1F\x8B"} { return "application/gzip" }
    if {[string range $data 0 3] eq "PK\x03\x04"} { return "application/zip" }

    # Default
    if {[is_binary_content $data]} {
        return "application/octet-stream"
    }
    return "text/plain"
}
```

### Binary File Reading via SSH

SSH/Expect works with text streams. For binary files:

```tcl
proc read_binary_file {spawn_id path} {
    # Use base64 encoding on the remote side
    set output [prompt::run $spawn_id "base64 '$path'"]

    # Decode locally
    return [binary decode base64 $output]
}

proc read_file_smart {spawn_id path {encoding "auto"}} {
    if {$encoding eq "base64"} {
        return [list [read_binary_file $spawn_id $path] "base64"]
    }

    # Try text first
    set output [prompt::run $spawn_id "cat '$path'"]

    if {$encoding eq "auto" && [is_binary_content $output]} {
        # Re-read as binary
        return [list [read_binary_file $spawn_id $path] "base64"]
    }

    return [list $output "text"]
}
```

### Size Limits and Chunking

For very large files, consider chunked transfer:

```tcl
# For files > max_size, return metadata only
proc check_file_size {spawn_id path max_size} {
    set output [prompt::run $spawn_id "stat -c %s '$path' 2>/dev/null || stat -f %z '$path'"]
    set size [string trim $output]

    if {![string is integer $size]} {
        error "Cannot determine file size"
    }

    if {$size > $max_size} {
        error "File too large: $size bytes (max: $max_size)"
    }

    return $size
}
```

**Large file response:**
```json
{
  "error": {
    "code": -32023,
    "message": "File too large: 52428800 bytes (max: 1048576)",
    "data": {
      "size": 52428800,
      "max_size": 1048576,
      "path": "/var/log/large.log"
    }
  }
}
```

### New Error Codes

| Code | Name | Description |
|------|------|-------------|
| -32023 | File too large | File exceeds max_size limit |
| -32024 | Encoding error | Failed to encode/decode content |
| -32040 | Pool exhausted | No connections available in pool |
| -32041 | Pool timeout | Timeout waiting for connection |

## HTTP Server Implementation

Using Tcllib's `httpd` module (TclOO-based HTTP server):

### Server Class Definition

```tcl
package require httpd
package require json
package require json::write

# MCP HTTP Server - extends tcllib httpd::server
oo::class create McpServer {
    superclass httpd::server

    # Override to add our routes
    method dispatch {data} {
        set request [my request get]
        set uri [dict get $request uri]
        set method [dict get $request method]

        switch -glob -- "$method $uri" {
            "GET /health" {
                my reply set Status {200 OK}
                my reply set Content-Type application/json
                my puts {{"status":"ok"}}
            }
            "POST /" {
                my DispatchMcp
            }
            default {
                my reply set Status {404 Not Found}
                my reply set Content-Type application/json
                my puts {{"error":"Not found"}}
            }
        }
    }

    method DispatchMcp {} {
        set body [my request get body]
        set response [jsonrpc::handle $body]

        my reply set Status {200 OK}
        my reply set Content-Type application/json
        my puts $response
    }
}
```

### Server Startup

```tcl
proc start_server {port {bind_addr "127.0.0.1"}} {
    McpServer create MCP_SERVER port $port myaddr $bind_addr
    debug::log 2 "MCP server listening on $bind_addr:$port"
}
```

## JSON Handling

Using Tcllib's `json` and `json::write` modules:

### Parsing (Request)

```tcl
package require json

# Parse JSON request to Tcl dict
proc parse_request {json_str} {
    return [::json::json2dict $json_str]
}
```

### Formatting (Response)

```tcl
package require json::write

# Format Tcl data to JSON response
# json::write produces properly escaped JSON
proc format_response {data} {
    return [dict_to_json $data]
}

# Recursive dict to JSON conversion using json::write
proc dict_to_json {value} {
    if {[string is list $value] && [llength $value] > 1} {
        # Check if it's a dict (even number of elements with string keys)
        if {[llength $value] % 2 == 0 && ![string is double [lindex $value 0]]} {
            # Format as object
            set pairs {}
            dict for {k v} $value {
                lappend pairs $k [dict_to_json $v]
            }
            return [json::write object {*}$pairs]
        } else {
            # Format as array
            set items {}
            foreach item $value {
                lappend items [dict_to_json $item]
            }
            return [json::write array {*}$items]
        }
    }

    # Scalar values
    if {$value eq "true" || $value eq "false" || $value eq "null"} {
        return $value
    }
    if {[string is integer -strict $value] || [string is double -strict $value]} {
        return $value
    }
    # String
    return [json::write string $value]
}
```

### JSON-RPC Handler

```tcl
namespace eval jsonrpc {
    proc handle {request_body} {
        # Parse request
        if {[catch {set req [json::parse $request_body]} err]} {
            return [error_response null -32700 "Parse error: $err"]
        }

        # Validate JSON-RPC structure
        if {![dict exists $req jsonrpc] || [dict get $req jsonrpc] ne "2.0"} {
            return [error_response null -32600 "Invalid Request"]
        }

        set id [expr {[dict exists $req id] ? [dict get $req id] : null}]
        set method [dict get $req method]
        set params [expr {[dict exists $req params] ? [dict get $req params] : {}}]

        # Route method
        switch $method {
            "initialize" {
                return [success_response $id [tools::handle_initialize $params]]
            }
            "tools/list" {
                return [success_response $id [tools::handle_list]]
            }
            "tools/call" {
                set tool_name [dict get $params name]
                set tool_args [expr {[dict exists $params arguments] ? [dict get $params arguments] : {}}]
                if {[catch {set result [tools::call $tool_name $tool_args]} err]} {
                    return [error_response $id -32000 $err]
                }
                return [success_response $id $result]
            }
            default {
                return [error_response $id -32601 "Method not found: $method"]
            }
        }
    }

    proc success_response {id result} {
        return [dict_to_json [dict create \
            jsonrpc "2.0" \
            id $id \
            result $result]]
    }

    proc error_response {id code message} {
        return [dict_to_json [dict create \
            jsonrpc "2.0" \
            id $id \
            error [dict create code $code message $message]]]
    }
}
```

## Server Startup

### Command Line Interface

```tcl
#!/usr/bin/env tclsh
# mcp/server.tcl - MCP Server for SSH Automation

# Parse arguments
set port 3000
set debug_level 0

for {set i 0} {$i < $argc} {incr i} {
    set arg [lindex $argv $i]
    switch -glob -- $arg {
        "--port" - "-p" {
            incr i
            set port [lindex $argv $i]
        }
        "--debug" - "-d" {
            incr i
            set debug_level [lindex $argv $i]
        }
        "--help" - "-h" {
            puts "Usage: server.tcl \[options\]"
            puts "Options:"
            puts "  --port, -p <port>    Port to listen on (default: 3000)"
            puts "  --debug, -d <level>  Debug level 0-7 (default: 0)"
            puts "  --help, -h           Show this help"
            exit 0
        }
    }
}

# Load Tcllib packages
package require httpd
package require json
package require json::write

# Load local modules
set script_dir [file dirname [info script]]
set project_root [file dirname $script_dir]

source [file join $script_dir lib jsonrpc.tcl]
source [file join $script_dir lib session.tcl]
source [file join $script_dir lib tools.tcl]

source [file join $project_root lib common debug.tcl]
source [file join $project_root lib common prompt.tcl]
source [file join $project_root lib connection ssh.tcl]
source [file join $project_root lib commands cat_file.tcl]
source [file join $project_root lib commands hostname.tcl]
source [file join $project_root lib commands sudo_exec.tcl]

# Initialize
debug::init $debug_level

# Start server
http::start $port
puts "MCP SSH Automation Server"
puts "Listening on http://localhost:$port"
puts "Press Ctrl+C to stop"

# Enter event loop
vwait forever
```

### Systemd Service (Optional)

```ini
# /etc/systemd/system/ssh-mcp.service
[Unit]
Description=SSH Automation MCP Server
After=network.target

[Service]
Type=simple
ExecStart=/path/to/ssh-tool/mcp/server.tcl --port 3000
Restart=on-failure
User=mcp
Group=mcp

[Install]
WantedBy=multi-user.target
```

## Testing Strategy

### Test Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    Integration Tests (Real)                     │
│  - Real MCP server + Real SSH connections                       │
│  - End-to-end validation                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                   Integration Tests (Mock SSH)                  │
│  - Real MCP server + Mock SSH sessions                          │
│  - Tests MCP layer without network                              │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                       Unit Tests (Mock)                         │
│  - JSON parsing/formatting                                      │
│  - JSON-RPC protocol handling                                   │
│  - Session management                                           │
│  - Tool handlers (mocked SSH)                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Test Client

A bash-based test client using curl:

```bash
#!/bin/bash
# mcp/tests/client/mcp_client.sh - Test client for MCP server

MCP_HOST="${MCP_HOST:-localhost}"
MCP_PORT="${MCP_PORT:-3000}"
REQUEST_ID=0

mcp_request() {
    local method="$1"
    local params="$2"

    REQUEST_ID=$((REQUEST_ID + 1))

    local body
    if [[ -n "$params" ]]; then
        body=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": $REQUEST_ID,
  "method": "$method",
  "params": $params
}
EOF
)
    else
        body=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": $REQUEST_ID,
  "method": "$method"
}
EOF
)
    fi

    curl -s -X POST "http://${MCP_HOST}:${MCP_PORT}/" \
        -H "Content-Type: application/json" \
        -d "$body"
}

# Initialize
mcp_initialize() {
    mcp_request "initialize" '{
        "protocolVersion": "2024-11-05",
        "clientInfo": {"name": "test-client", "version": "1.0.0"}
    }'
}

# List tools
mcp_list_tools() {
    mcp_request "tools/list"
}

# Call a tool
mcp_call_tool() {
    local name="$1"
    local args="$2"

    mcp_request "tools/call" "{\"name\": \"$name\", \"arguments\": $args}"
}

# SSH operations
mcp_ssh_connect() {
    local host="$1"
    local user="$2"
    local password="$3"
    local insecure="${4:-false}"

    mcp_call_tool "ssh_connect" "{
        \"host\": \"$host\",
        \"user\": \"$user\",
        \"password\": \"$password\",
        \"insecure\": $insecure
    }"
}

mcp_ssh_run() {
    local session_id="$1"
    local command="$2"

    mcp_call_tool "ssh_run_command" "{
        \"session_id\": \"$session_id\",
        \"command\": \"$command\"
    }"
}

mcp_ssh_cat_file() {
    local session_id="$1"
    local path="$2"

    mcp_call_tool "ssh_cat_file" "{
        \"session_id\": \"$session_id\",
        \"path\": \"$path\"
    }"
}

mcp_ssh_disconnect() {
    local session_id="$1"

    mcp_call_tool "ssh_disconnect" "{
        \"session_id\": \"$session_id\"
    }"
}
```

### Mock MCP Server

For testing clients without a real server:

```tcl
# mcp/tests/mock/helpers/mock_mcp_server.tcl
# Simulates MCP server responses for client testing

namespace eval mock_mcp {
    variable responses

    # Pre-configured responses
    dict set responses "initialize" {
        result {
            protocolVersion "2024-11-05"
            serverInfo {name "mock-mcp" version "1.0.0"}
            capabilities {tools {}}
        }
    }

    dict set responses "tools/list" {
        result {
            tools {
                {name "ssh_connect" description "Connect via SSH" inputSchema {}}
                {name "ssh_run_command" description "Run command" inputSchema {}}
            }
        }
    }

    dict set responses "ssh_connect" {
        result {
            content {{type "text" text "Connected to mock-host"}}
            session_id "sess_mock123"
        }
    }

    proc handle {request_json} {
        variable responses

        set req [json::parse $request_json]
        set method [dict get $req method]
        set id [dict get $req id]

        if {$method eq "tools/call"} {
            set tool_name [dict get $req params name]
            if {[dict exists $responses $tool_name]} {
                set resp [dict get $responses $tool_name]
            } else {
                set resp {error {code -32601 message "Unknown tool"}}
            }
        } elseif {[dict exists $responses $method]} {
            set resp [dict get $responses $method]
        } else {
            set resp {error {code -32601 message "Method not found"}}
        }

        dict set resp jsonrpc "2.0"
        dict set resp id $id
        return [json::format $resp]
    }
}
```

### Test Framework: tcltest

MCP tests use Tcl's standard `tcltest` package (bundled with Tcl):

```tcl
#!/usr/bin/env tclsh
# mcp/tests/mock/test_tools.test - Test tool handlers using tcltest

package require tcltest
namespace import ::tcltest::*

# Configure test constraints
testConstraint hasSSHTarget [info exists ::env(SSH_HOST)]

# Load modules under test
set script_dir [file dirname [info script]]
set project_root [file dirname [file dirname [file dirname $script_dir]]]

source [file join $project_root "mcp/lib/tools.tcl"]
source [file join $project_root "mcp/lib/session.tcl"]
source [file join $project_root "mcp/lib/pool.tcl"]

# Test 1: ssh_connect tool validation
test ssh_connect-1.0 {ssh_connect requires host parameter} -body {
    tools::call "ssh_connect" {user "admin" password "secret"}
} -returnCodes error -match glob -result "*host*required*"

# Test 2: session validation
test ssh_run_command-1.0 {ssh_run_command rejects invalid session} -body {
    tools::call "ssh_run_command" {session_id "invalid_session" command "hostname"}
} -returnCodes error -match glob -result "*Session not found*"

# Test 3: pool configuration
test pool-1.0 {pool has valid default config} -body {
    dict get $pool::config max_connections
} -result 10

# Test 4: session ID generation
test session-1.0 {session ID has correct format} -body {
    set sid [session::generate_session_id]
    regexp {^sess_[0-9a-f]{8}$} $sid
} -result 1

# Test 5: binary detection
test binary-1.0 {detects binary content with null bytes} -body {
    is_binary_content "hello\x00world"
} -result 1

test binary-1.1 {detects text content} -body {
    is_binary_content "hello world\n"
} -result 0

# Test with real SSH (only runs if SSH_HOST is set)
test real_ssh-1.0 {connect to real host via pool} -constraints {hasSSHTarget} -setup {
    set host $::env(SSH_HOST)
    set user [expr {[info exists ::env(SSH_USER)] ? $::env(SSH_USER) : "das"}]
    set pass $::env(PASSWORD)
} -body {
    set result [tools::call "ssh_connect" [dict create \
        host $host user $user password $pass insecure true]]
    dict exists $result session_id
} -cleanup {
    catch {tools::call "ssh_disconnect" [dict create session_id [dict get $result session_id]]}
} -result 1

# Summary and cleanup
cleanupTests
```

### Test File Naming Convention

| Pattern | Purpose |
|---------|---------|
| `*.test` | tcltest test files (run by tclsh) |
| `*.sh` | Bash wrapper scripts |

### Running Tests

```bash
# Run all MCP tests
./mcp/tests/run_mcp_tests.sh

# Run specific test file
tclsh mcp/tests/mock/test_tools.test

# Run with verbose output
tclsh mcp/tests/mock/test_tools.test -verbose bps

# Run only tests matching pattern
tclsh mcp/tests/mock/test_tools.test -match "pool-*"

# Skip real SSH tests
tclsh mcp/tests/mock/test_tools.test -constraints "!hasSSHTarget"
```

### Real Integration Test

```bash
#!/bin/bash
# mcp/tests/real/test_mcp_connect.sh - Test real SSH via MCP

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

source "$SCRIPT_DIR/../client/mcp_client.sh"

: "${SSH_HOST:=192.168.122.163}"
: "${SSH_USER:=das}"
: "${MCP_PORT:=3000}"

echo "========================================"
echo "Testing MCP SSH Connection (Real)"
echo "========================================"

# Start MCP server in background
"$PROJECT_ROOT/mcp/server.tcl" --port "$MCP_PORT" &
MCP_PID=$!
sleep 2

cleanup() {
    kill $MCP_PID 2>/dev/null
}
trap cleanup EXIT

# Test initialize
echo "Test 1: Initialize..."
result=$(mcp_initialize)
if echo "$result" | grep -q '"protocolVersion"'; then
    echo "PASS: Initialize returned protocol version"
else
    echo "FAIL: Initialize failed"
    exit 1
fi

# Test SSH connect
echo "Test 2: SSH Connect..."
result=$(mcp_ssh_connect "$SSH_HOST" "$SSH_USER" "$PASSWORD" true)
if echo "$result" | grep -q '"session_id"'; then
    SESSION_ID=$(echo "$result" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    echo "PASS: Connected, session_id=$SESSION_ID"
else
    echo "FAIL: SSH connect failed: $result"
    exit 1
fi

# Test run command
echo "Test 3: Run command..."
result=$(mcp_ssh_run "$SESSION_ID" "hostname")
if echo "$result" | grep -q '"content"'; then
    echo "PASS: Command executed"
else
    echo "FAIL: Command failed: $result"
    exit 1
fi

# Test disconnect
echo "Test 4: Disconnect..."
result=$(mcp_ssh_disconnect "$SESSION_ID")
if echo "$result" | grep -q '"content"'; then
    echo "PASS: Disconnected"
else
    echo "FAIL: Disconnect failed: $result"
    exit 1
fi

echo ""
echo "All tests passed!"
```

## Error Handling

MCP uses a three-layer error model following [JSON-RPC 2.0 best practices](https://www.jsonrpc.org/historical/json-rpc-over-http.html):

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: HTTP Transport                                        │
│  - HTTP status codes for transport-level issues                 │
│  - 200 OK for valid JSON-RPC (even if application error)        │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│  Layer 2: JSON-RPC Protocol                                     │
│  - Error codes in response body                                 │
│  - Parse errors, invalid requests, method not found             │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3: Tool Execution                                        │
│  - isError flag in tool response content                        │
│  - SSH failures, file not found, permission denied              │
└─────────────────────────────────────────────────────────────────┘
```

### HTTP Status Codes (Transport Layer)

| Code | Name | When Used |
|------|------|-----------|
| 200 | OK | Valid JSON-RPC request processed (success or error in body) |
| 400 | Bad Request | Malformed JSON, invalid JSON-RPC structure |
| 405 | Method Not Allowed | HTTP method other than POST used |
| 413 | Payload Too Large | Request body exceeds size limit |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Unexpected server crash |
| 503 | Service Unavailable | Server overloaded, max sessions reached |
| 504 | Gateway Timeout | Upstream timeout (rare) |

### Resource Limits

```tcl
namespace eval limits {
    variable max_sessions         50      ;# Total concurrent SSH sessions
    variable max_sessions_per_host 10     ;# Per-host session limit
    variable max_request_size     1048576 ;# 1MB request body limit
    variable requests_per_minute  100     ;# Rate limit per client
}
```

### HTTP Error Responses

For transport-layer errors, return HTTP status with JSON body:

**503 Service Unavailable (Max Sessions):**
```http
HTTP/1.1 503 Service Unavailable
Content-Type: application/json
Retry-After: 30

{
  "error": "Service temporarily unavailable",
  "reason": "max_sessions_exceeded",
  "limit": 50,
  "current": 50,
  "retry_after": 30
}
```

**429 Too Many Requests (Rate Limit):**
```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 60

{
  "error": "Rate limit exceeded",
  "limit": 100,
  "window": "1 minute",
  "retry_after": 60
}
```

**413 Payload Too Large:**
```http
HTTP/1.1 413 Payload Too Large
Content-Type: application/json

{
  "error": "Request body too large",
  "limit": 1048576,
  "received": 5242880
}
```

**400 Bad Request (Invalid JSON):**
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "Invalid JSON",
  "details": "Unexpected token at position 42"
}
```

### JSON-RPC Error Codes (Protocol Layer)

For valid JSON-RPC requests with protocol errors, return HTTP 200 with error in body:

| Code | Name | Description |
|------|------|-------------|
| -32700 | Parse error | Invalid JSON was received |
| -32600 | Invalid Request | Not a valid JSON-RPC request |
| -32601 | Method not found | Method does not exist |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Internal JSON-RPC error |

**Example:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32601,
    "message": "Method not found: tools/invalid"
  }
}
```

### Application Error Codes (Tool Layer)

For tool execution failures, return HTTP 200 with successful JSON-RPC response containing error info:

| Code | Name | Description |
|------|------|-------------|
| -32000 | Server error | Generic SSH/MCP error |
| -32001 | Connection refused | SSH connection refused |
| -32002 | Auth failed | SSH authentication failed |
| -32003 | Connection timeout | SSH connection timeout |
| -32004 | Host key failed | Host key verification failed |
| -32010 | Session not found | Invalid session_id |
| -32011 | Session disconnected | Session no longer active |
| -32012 | Command timeout | Command execution timeout |
| -32020 | File not found | Remote file not found |
| -32021 | Permission denied | No access to file |
| -32022 | Invalid filename | Unsafe filename characters |
| -32023 | File too large | File exceeds max_size limit |
| -32024 | Encoding error | Failed to encode/decode content |
| -32030 | Sudo auth failed | Sudo password incorrect |
| -32031 | Not in sudoers | User cannot sudo |
| -32040 | Pool exhausted | No connections available in pool |
| -32041 | Pool timeout | Timeout waiting for connection |

**Example (Tool Error):**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Error: Connection refused to 192.168.1.100:22"
      }
    ],
    "isError": true,
    "error_code": -32001
  }
}
```

### Error Response Helper

```tcl
proc format_http_error {status reason details} {
    set body [dict_to_json [dict create \
        error $reason \
        {*}$details \
    ]]
    return [list $status $body]
}

proc format_jsonrpc_error {id code message {data {}}} {
    set error [dict create code $code message $message]
    if {$data ne {}} {
        dict set error data $data
    }
    return [dict_to_json [dict create \
        jsonrpc "2.0" \
        id $id \
        error $error \
    ]]
}

proc format_tool_error {id code message} {
    return [dict_to_json [dict create \
        jsonrpc "2.0" \
        id $id \
        result [dict create \
            content [list [dict create type "text" text "Error: $message"]] \
            isError true \
            error_code $code \
        ] \
    ]]
}
```

### Request Processing Flow

```tcl
proc handle_request {sock request_body} {
    # Layer 1: Transport validation
    if {[string length $request_body] > $limits::max_request_size} {
        return [send_http_error $sock 413 "Payload Too Large" \
            [dict create limit $limits::max_request_size received [string length $request_body]]]
    }

    if {[over_rate_limit $sock]} {
        return [send_http_error $sock 429 "Too Many Requests" \
            [dict create limit $limits::requests_per_minute window "1 minute" retry_after 60]]
    }

    if {[at_session_limit]} {
        return [send_http_error $sock 503 "Service Unavailable" \
            [dict create reason "max_sessions_exceeded" limit $limits::max_sessions retry_after 30]]
    }

    # Layer 2: JSON-RPC parsing
    if {[catch {set req [json::json2dict $request_body]} err]} {
        return [send_http_200 $sock [format_jsonrpc_error null -32700 "Parse error: $err"]]
    }

    if {![valid_jsonrpc $req]} {
        return [send_http_200 $sock [format_jsonrpc_error null -32600 "Invalid Request"]]
    }

    set id [dict get $req id]
    set method [dict get $req method]

    # Layer 3: Method dispatch and tool execution
    if {[catch {set result [dispatch $method $req]} err]} {
        return [send_http_200 $sock [format_tool_error $id -32000 $err]]
    }

    return [send_http_200 $sock [format_jsonrpc_success $id $result]]
}
```

## Production Readiness

### Priority Matrix

| Feature | Impact | Complexity | Priority |
|---------|--------|------------|----------|
| JSON Structured Logging | High (Troubleshooting) | Low | P0 |
| Signal Trapping | Medium (Stability) | Low | P0 |
| Path Sanitization | Critical (Security) | Medium | P0 |
| Keep-Alives | High (Reliability) | Medium | P1 |
| Prometheus Metrics | High (Scaling) | Medium | P1 |
| Command Allowlist | High (Security) | Medium | P1 |
| Sudo Timeout Tracking | Medium (Security) | Low | P2 |

### 1. Observability: Structured Logging & Metrics

#### Structured JSON Logging

Replace plain text debug output with JSON logs for integration with ELK, Datadog, Grafana Loki:

```tcl
namespace eval log {
    variable level 3
    variable output stdout

    proc emit {severity message {data {}}} {
        variable output

        set entry [dict create \
            timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1] \
            level $severity \
            message $message \
        ]

        # Add optional structured data
        if {$data ne {}} {
            dict set entry data $data
        }

        # Add context if available
        if {[info exists ::current_mcp_session]} {
            dict set entry mcp_session_id $::current_mcp_session
        }
        if {[info exists ::current_ssh_session]} {
            dict set entry ssh_session_id $::current_ssh_session
        }

        puts $output [dict_to_json $entry]
    }

    proc debug {msg {data {}}} { emit "DEBUG" $msg $data }
    proc info {msg {data {}}}  { emit "INFO" $msg $data }
    proc warn {msg {data {}}}  { emit "WARN" $msg $data }
    proc error {msg {data {}}} { emit "ERROR" $msg $data }
}

# Example output:
# {"timestamp":"2024-01-15T10:30:00Z","level":"INFO","message":"SSH connection established","data":{"host":"192.168.1.100","user":"admin","session_id":"sess_abc123"}}
```

#### Prometheus Metrics Endpoint

Add `/metrics` route exposing key metrics:

```tcl
namespace eval metrics {
    variable counters [dict create]
    variable gauges [dict create]
    variable histograms [dict create]

    # Gauge: current value
    proc gauge_set {name value {labels {}}} {
        variable gauges
        set key [make_key $name $labels]
        dict set gauges $key $value
    }

    # Counter: monotonically increasing
    proc counter_inc {name {value 1} {labels {}}} {
        variable counters
        set key [make_key $name $labels]
        if {![dict exists $counters $key]} {
            dict set counters $key 0
        }
        dict incr counters $key $value
    }

    # Histogram: track distribution
    proc histogram_observe {name value {labels {}}} {
        variable histograms
        set key [make_key $name $labels]
        if {![dict exists $histograms $key]} {
            dict set histograms $key [dict create sum 0 count 0 buckets {}]
        }
        set h [dict get $histograms $key]
        dict incr h count
        dict set h sum [expr {[dict get $h sum] + $value}]
        dict set histograms $key $h
    }

    proc format_prometheus {} {
        variable counters
        variable gauges
        variable histograms

        set out ""

        # Gauges
        append out "# HELP mcp_ssh_active_sessions Current open SSH connections\n"
        append out "# TYPE mcp_ssh_active_sessions gauge\n"
        dict for {key val} $gauges {
            append out "$key $val\n"
        }

        # Counters
        append out "# HELP mcp_ssh_errors_total Total SSH errors by code\n"
        append out "# TYPE mcp_ssh_errors_total counter\n"
        dict for {key val} $counters {
            append out "$key $val\n"
        }

        # Histograms
        append out "# HELP mcp_ssh_command_duration_seconds Command execution time\n"
        append out "# TYPE mcp_ssh_command_duration_seconds histogram\n"
        dict for {key data} $histograms {
            append out "${key}_count [dict get $data count]\n"
            append out "${key}_sum [dict get $data sum]\n"
        }

        return $out
    }
}

# Metrics to track:
# - mcp_ssh_active_sessions (gauge)
# - mcp_ssh_pool_idle_connections{host="..."} (gauge)
# - mcp_ssh_pool_total_connections{host="..."} (gauge)
# - mcp_ssh_command_duration_seconds{host="..."} (histogram)
# - mcp_ssh_errors_total{code="-32001"} (counter)
# - mcp_http_requests_total{method="tools/call",tool="ssh_connect"} (counter)
```

### 2. Process & Signal Management

#### Graceful Shutdown

Handle SIGTERM and SIGINT for clean shutdown:

```tcl
namespace eval lifecycle {
    variable shutting_down 0
    variable grace_period 5000  ;# 5 seconds in ms

    proc init {} {
        # Trap signals
        signal trap SIGTERM [namespace code {shutdown "SIGTERM"}]
        signal trap SIGINT  [namespace code {shutdown "SIGINT"}]
    }

    proc shutdown {reason} {
        variable shutting_down
        variable grace_period

        if {$shutting_down} {
            log::warn "Forced shutdown" [dict create reason "duplicate signal"]
            exit 1
        }
        set shutting_down 1

        log::info "Shutdown initiated" [dict create reason $reason]

        # 1. Stop accepting new HTTP connections
        http::stop_accepting

        # 2. Close all SSH sessions gracefully
        set sessions [session::list_all]
        log::info "Closing SSH sessions" [dict create count [llength $sessions]]

        foreach sid $sessions {
            if {[catch {
                # Send exit command to clean up remote shell
                set spawn_id [session::get_spawn_id $sid]
                send -i $spawn_id "exit\r"
            } err]} {
                log::warn "Error closing session" [dict create session_id $sid error $err]
            }
        }

        # 3. Wait grace period for sessions to close
        after $grace_period [namespace code force_shutdown]

        # 4. Check periodically if all sessions closed
        check_sessions_closed
    }

    proc check_sessions_closed {} {
        variable shutting_down

        set remaining [llength [session::list_all]]
        if {$remaining == 0} {
            log::info "All sessions closed, exiting"
            exit 0
        }

        # Check again in 500ms
        after 500 [namespace code check_sessions_closed]
    }

    proc force_shutdown {} {
        log::warn "Grace period expired, forcing shutdown"

        # Force close any remaining sessions
        foreach sid [session::list_all] {
            catch {session::force_disconnect $sid}
        }

        exit 0
    }
}
```

#### Zombie Process Reaper

Prevent defunct SSH processes from accumulating:

```tcl
namespace eval reaper {
    variable interval 10000  ;# Check every 10 seconds

    proc start {} {
        variable interval
        schedule
    }

    proc schedule {} {
        variable interval
        after $interval [namespace code reap]
    }

    proc reap {} {
        # Reap any zombie child processes
        while {1} {
            if {[catch {wait -i -1 -nowait} result]} {
                # No more children to wait for
                break
            }
            if {$result eq ""} {
                break
            }
            lassign $result pid spawn_id status
            log::debug "Reaped zombie process" [dict create pid $pid status $status]
        }

        schedule
    }
}
```

### 3. Security Hardening

#### Path Sanitization (Filesystem Jail)

Prevent path traversal attacks on `ssh_cat_file`:

```tcl
namespace eval security {
    # =======================================================================
    # PATH SECURITY THREAT MODEL:
    # - Attacker controls path string sent via MCP tool
    # - Goal: Read sensitive files outside allowed directories
    # - Attack vectors: path traversal (..), symlinks, encoding tricks,
    #   null bytes, case manipulation
    #
    # LIMITATION: We validate the path STRING locally, but cannot detect
    # symlinks on the REMOTE system. Mitigation: Use realpath on remote
    # before reading, or restrict to specific known-safe files.
    # =======================================================================

    # Allowed base directories (restrictive by default)
    variable allowed_paths [list \
        "/etc/hostname"       \
        "/etc/os-release"     \
        "/etc/redhat-release" \
        "/etc/debian_version" \
        "/etc/hosts"          \
        "/var/log/messages"   \
        "/var/log/syslog"     \
        "/var/log/auth.log"   \
        "/var/log/secure"     \
        "/tmp"                \
    ]

    # Absolutely forbidden - even if under allowed path
    variable forbidden_patterns [list \
        {shadow}              \
        {passwd-}             \
        {sudoers}             \
        {\.ssh/}              \
        {id_rsa}              \
        {id_dsa}              \
        {id_ecdsa}            \
        {id_ed25519}          \
        {authorized_keys}     \
        {known_hosts}         \
        {\.gnupg/}            \
        {\.bash_history}      \
        {\.mysql_history}     \
        {\.psql_history}      \
        {\.python_history}    \
        {private}             \
        {secret}              \
        {credential}          \
        {password}            \
        {token}               \
        {\.env$}              \
        {\.pem$}              \
        {\.key$}              \
        {\.crt$}              \
    ]

    proc validate_path {path} {
        variable allowed_paths
        variable forbidden_patterns

        # STEP 1: Check for null bytes (injection attempt)
        if {[string first "\x00" $path] >= 0} {
            ::mcp::log::error "Null byte in path" [dict create path $path]
            error "SECURITY: Path contains null byte"
        }

        # STEP 2: Check for control characters
        if {![regexp {^[\x20-\x7e]+$} $path]} {
            ::mcp::log::error "Invalid characters in path" [dict create path $path]
            error "SECURITY: Path contains invalid characters"
        }

        # STEP 3: Check path length
        if {[string length $path] > 512} {
            ::mcp::log::error "Path too long" [dict create length [string length $path]]
            error "SECURITY: Path exceeds maximum length"
        }

        # STEP 4: Normalize path (resolve .. locally)
        # NOTE: This does NOT resolve symlinks on remote system
        set normalized [file normalize $path]

        # STEP 5: Check for path traversal attempts that survived normalization
        if {[string match "*/..*" $normalized] || [string match "*..*" $path]} {
            ::mcp::log::error "Path traversal detected" [dict create path $path]
            error "SECURITY: Path traversal not permitted"
        }

        # STEP 6: Check against forbidden patterns (case insensitive)
        set path_lower [string tolower $normalized]
        foreach pattern $forbidden_patterns {
            if {[regexp -nocase -- $pattern $path_lower]} {
                ::mcp::log::error "Forbidden path pattern" \
                    [dict create path $normalized pattern $pattern]
                error "SECURITY: Path matches forbidden pattern"
            }
        }

        # STEP 7: Check if path matches an allowed path/directory
        set allowed 0
        foreach allowed_path $allowed_paths {
            if {$normalized eq $allowed_path} {
                # Exact match
                set allowed 1
                break
            }
            if {[string match "${allowed_path}/*" $normalized]} {
                # Under allowed directory (but not /tmp/../etc)
                set allowed 1
                break
            }
        }

        if {!$allowed} {
            ::mcp::log::warn "Path not in allowlist" [dict create path $normalized]
            error "SECURITY: Path not in allowed list"
        }

        ::mcp::log::debug "Path permitted" [dict create path $normalized]
        return $normalized
    }

    # For cat_file: Additional check on remote using realpath
    # This catches symlinks on the remote system
    proc build_safe_cat_command {path} {
        set escaped_path [string map {' '\\''} $path]

        # Use realpath to resolve symlinks, then verify the resolved path
        # starts with an allowed prefix
        return "p=\$(realpath -e '$escaped_path' 2>/dev/null) && \
case \"\$p\" in \
  /etc/hostname|/etc/os-release|/etc/hosts|/var/log/*|/tmp/*) cat \"\$p\" ;; \
  *) echo 'SECURITY: Path resolves outside allowed directories' >&2; exit 1 ;; \
esac"
    }
}
```

**IMPORTANT - Symlink Mitigation**: The `build_safe_cat_command` function generates a shell command that:
1. Resolves the path using `realpath` on the REMOTE system
2. Verifies the resolved path is in the allowed set
3. Only then reads the file

This prevents attacks where `/tmp/harmless.txt` is a symlink to `/etc/shadow`.

#### Command Filtering (MANDATORY)

**SECURITY REQUIREMENT**: All commands MUST pass through the security filter. There is no "unrestricted" mode. This is a hard requirement - the server provides Remote Code Execution to an LLM, and we must enforce strict boundaries.

```tcl
namespace eval security {
    # NOTE: There is NO unrestricted mode. All commands are filtered.

    # =======================================================================
    # THREAT MODEL:
    # - Attacker controls command string sent via MCP tool
    # - Goal: Execute arbitrary code, read sensitive files, escalate privs
    # - Attack vectors: shell metacharacters, path traversal, symlinks,
    #   command substitution, find -exec, awk system(), encoding tricks
    # =======================================================================

    # REMOVED DANGEROUS COMMANDS:
    # - find: can use -exec to run arbitrary commands
    # - awk/gawk: system() function executes shell commands
    # - sed: GNU sed -e flag can execute commands
    # - xargs: can execute arbitrary commands
    # - env: can manipulate PATH and environment

    # Allowlist of permitted commands (regex patterns)
    # Commands not matching ANY pattern are REJECTED
    # NOTE: These are SIMPLE, SAFE commands with NO execution capabilities
    variable allowed_commands [list \
        {^ls(\s+-[alhtSr]+)*\s+}       \
        {^cat\s+}                       \
        {^head(\s+-n\s*\d+)?\s+}        \
        {^tail(\s+-n\s*\d+)?\s+}        \
        {^grep(\s+-[ivnHrE]+)*\s+}      \
        {^df(\s+-[hT]+)*\s*$}           \
        {^du(\s+-[sh]+)*\s+}            \
        {^ps(\s+aux)?\s*$}              \
        {^top\s+-bn1\s*$}               \
        {^hostname\s*$}                 \
        {^hostname\s+-f\s*$}            \
        {^uname(\s+-[asnrvmpio]+)*\s*$} \
        {^whoami\s*$}                   \
        {^id\s*$}                       \
        {^date\s*$}                     \
        {^uptime\s*$}                   \
        {^pwd\s*$}                      \
        {^wc(\s+-[lwc]+)*\s+}           \
        {^stat\s+}                      \
        {^file\s+}                      \
        {^free(\s+-[hm]+)*\s*$}         \
        {^lsblk\s*$}                    \
        {^lscpu\s*$}                    \
        {^mount\s*$}                    \
    ]

    # Dangerous patterns - ALWAYS blocked (defense in depth)
    # These catch attacks even if allowlist has a gap
    variable blocked_patterns [list \
        {[/\\]}                         \
        {rm\s}                          \
        {chmod\s}                       \
        {chown\s}                       \
        {mkfs}                          \
        {dd\s}                          \
        {\|}                            \
        {;}                             \
        {&&}                            \
        {\|\|}                          \
        {`}                             \
        {\$\(}                          \
        {\$\{}                          \
        {>\s*[/\w]}                     \
        {<\s*[/\w]}                     \
        {>>}                            \
        {\bsh\b}                        \
        {\bbash\b}                      \
        {\bzsh\b}                       \
        {\bpython}                      \
        {\bperl\b}                      \
        {\bruby\b}                      \
        {\bphp\b}                       \
        {\bnc\b}                        \
        {\bnetcat\b}                    \
        {\bcurl\b}                      \
        {\bwget\b}                      \
        {\bsudo\b}                      \
        {\bsu\b}                        \
        {\bfind\b}                      \
        {\bxargs\b}                     \
        {\bawk\b}                       \
        {\bgawk\b}                      \
        {\bsed\b}                       \
        {\benv\b}                       \
        {\bexec\b}                      \
        {\beval\b}                      \
        {\bsource\b}                    \
        {\.\.}                          \
        {\x00}                          \
        {[\x00-\x08\x0b\x0c\x0e-\x1f]}  \
    ]

    # Characters that MUST NOT appear in commands (prevent encoding tricks)
    variable forbidden_chars [list \
        "\x00" "\x01" "\x02" "\x03" "\x04" "\x05" "\x06" "\x07" \
        "\x08" "\x0b" "\x0c" "\x0e" "\x0f" "\x10" "\x11" "\x12" \
        "\x13" "\x14" "\x15" "\x16" "\x17" "\x18" "\x19" "\x1a" \
        "\x1b" "\x1c" "\x1d" "\x1e" "\x1f" \
    ]

    proc validate_command {cmd} {
        variable allowed_commands
        variable blocked_patterns
        variable forbidden_chars

        # STEP 0: Normalize and sanitize input
        # Reject empty/whitespace-only commands
        set cmd [string trim $cmd]
        if {$cmd eq ""} {
            ::mcp::log::warn "Empty command rejected"
            error "SECURITY: Empty command"
        }

        # STEP 1: Check for forbidden control characters
        # Prevents encoding tricks, null bytes, escape sequences
        foreach char $forbidden_chars {
            if {[string first $char $cmd] >= 0} {
                ::mcp::log::error "Forbidden character in command" \
                    [dict create command [_sanitize_for_log $cmd]]
                error "SECURITY: Command contains forbidden characters"
            }
        }

        # STEP 2: Check for non-ASCII characters (prevent unicode tricks)
        # Only allow printable ASCII (0x20-0x7E) plus tab and newline
        if {![regexp {^[\x20-\x7e\t]*$} $cmd]} {
            ::mcp::log::error "Non-ASCII character in command" \
                [dict create command [_sanitize_for_log $cmd]]
            error "SECURITY: Command contains non-ASCII characters"
        }

        # STEP 3: Check command length (prevent buffer issues)
        if {[string length $cmd] > 1024} {
            ::mcp::log::error "Command too long" [dict create length [string length $cmd]]
            error "SECURITY: Command exceeds maximum length (1024)"
        }

        # STEP 4: Check blocked patterns (defense in depth)
        # Even if allowlist has a gap, these catch common attacks
        foreach pattern $blocked_patterns {
            if {[regexp -nocase -- $pattern $cmd]} {
                ::mcp::log::error "Blocked pattern matched" \
                    [dict create command [_sanitize_for_log $cmd] pattern $pattern]
                error "SECURITY: Command matches blocked pattern"
            }
        }

        # STEP 5: Command MUST match an allowed pattern exactly
        set allowed 0
        set matched_pattern ""
        foreach pattern $allowed_commands {
            if {[regexp -- $pattern $cmd]} {
                set allowed 1
                set matched_pattern $pattern
                break
            }
        }

        if {!$allowed} {
            ::mcp::log::warn "Command not in allowlist" \
                [dict create command [_sanitize_for_log $cmd]]
            error "SECURITY: Command not in allowlist"
        }

        ::mcp::log::info "Command permitted" \
            [dict create command [_sanitize_for_log $cmd] pattern $matched_pattern]
        return 1
    }

    # Sanitize command for safe logging (truncate, escape)
    proc _sanitize_for_log {cmd} {
        set cmd [string range $cmd 0 99]
        set cmd [string map {"\n" "\\n" "\r" "\\r" "\t" "\\t"} $cmd]
        return $cmd
    }
}
```

#### Sudo Timeout Tracking

Track sudo elevation timestamp to detect expiry:

```tcl
namespace eval session {
    # Session data now includes:
    # {
    #   ...
    #   sudo_elevated_at  <epoch timestamp or 0>
    #   sudo_timeout      300  ;# typical sudo timestamp_timeout
    # }

    proc is_sudo_valid {session_id} {
        set data [get $session_id]
        if {![dict exists $data sudo_elevated_at]} {
            return 0
        }

        set elevated_at [dict get $data sudo_elevated_at]
        if {$elevated_at == 0} {
            return 0
        }

        set timeout [dict get $data sudo_timeout]
        set now [clock seconds]
        set elapsed [expr {$now - $elevated_at}]

        if {$elapsed > $timeout} {
            log::info "Sudo session likely expired" [dict create \
                session_id $session_id \
                elapsed $elapsed \
                timeout $timeout]
            return 0
        }

        return 1
    }

    proc mark_sudo_elevated {session_id} {
        update $session_id [dict create \
            sudo_elevated_at [clock seconds] \
            sudo_timeout 300]
    }
}

# Tool can warn LLM about sudo expiry
proc tools::ssh_sudo_elevate {args} {
    # ... elevation logic ...

    # Check if already elevated but may have expired
    if {[session::is_sudo_valid $session_id]} {
        return [dict create \
            content [list [dict create type "text" text "Already elevated to root (session still valid)"]] \
            is_root true \
            sudo_valid true]
    }

    # Re-elevate if expired or not elevated
    # ... sudo logic ...

    session::mark_sudo_elevated $session_id
}
```

### 4. Enhanced Connection Pooling

#### Health Check Keep-Alives

Prevent firewalls from dropping idle connections:

```tcl
namespace eval pool {
    variable health_check_interval 60000  ;# 60 seconds

    proc start_health_checks {} {
        variable health_check_interval
        after $health_check_interval [namespace code health_check_all]
    }

    proc health_check_all {} {
        variable health_check_interval
        variable pools

        dict for {pool_key sessions} $pools {
            foreach sid $sessions {
                if {[session::is_idle $sid]} {
                    health_check_session $sid
                }
            }
        }

        # Reschedule
        after $health_check_interval [namespace code health_check_all]
    }

    proc health_check_session {session_id} {
        set spawn_id [session::get_spawn_id $session_id]

        # Send no-op command
        if {[catch {
            set output [prompt::run $spawn_id "true"]
            session::update $session_id [dict create last_health_check [clock seconds]]
        } err]} {
            log::warn "Health check failed, removing from pool" [dict create \
                session_id $session_id \
                error $err]
            remove_from_pool $session_id
            session::force_disconnect $session_id
        }
    }
}
```

#### Jittered Timeout Cleanup

Prevent thundering herd when cleaning expired sessions:

```tcl
namespace eval pool {
    proc cleanup_expired_sessions {} {
        variable config
        variable pools

        set base_timeout [dict get $config idle_timeout]
        set now [clock seconds]

        dict for {pool_key sessions} $pools {
            foreach sid $sessions {
                # Add jitter: +/- 10% of timeout
                set jitter [expr {int(rand() * $base_timeout * 0.2) - ($base_timeout * 0.1)}]
                set effective_timeout [expr {$base_timeout + $jitter}]

                set last_used [session::get_last_used $sid]
                set idle_time [expr {$now - $last_used}]

                if {$idle_time > $effective_timeout} {
                    log::debug "Expiring idle session" [dict create \
                        session_id $sid \
                        idle_time $idle_time \
                        timeout $effective_timeout]
                    remove_from_pool $sid
                    session::disconnect $sid
                }
            }
        }
    }
}
```

## Security Considerations

### Authentication

The MCP server itself does not authenticate clients. It is designed to run:

1. **Locally only** - Bind to localhost (127.0.0.1) by default
2. **Behind a reverse proxy** - Let nginx/caddy handle auth
3. **In a trusted network** - Internal network only

```tcl
# Default: localhost only
proc start {{bind_addr "127.0.0.1"} {port_num 3000}} {
    variable server_socket
    set server_socket [socket -server [namespace code accept] -myaddr $bind_addr $port_num]
}
```

### Password Handling

- Passwords are received in JSON, not logged at any debug level
- Passwords are passed directly to SSH/sudo, not stored in session data
- Session data does not contain passwords

### Input Validation

- Filenames validated via `security::validate_path` (see above)
- Commands validated via `security::validate_command` (see above)
- Session IDs validated against active sessions
- All paths normalized to prevent traversal attacks

### Rate Limiting

```tcl
namespace eval ratelimit {
    variable requests  ;# dict: client_addr -> {count timestamp}
    variable limit 100 ;# requests per minute

    proc check {addr} {
        variable requests
        variable limit

        set now [clock seconds]
        set minute_ago [expr {$now - 60}]

        if {[dict exists $requests $addr]} {
            set data [dict get $requests $addr]
            if {[dict get $data timestamp] > $minute_ago} {
                if {[dict get $data count] >= $limit} {
                    return 0  ;# Rate limited
                }
                dict incr data count
            } else {
                set data [dict create count 1 timestamp $now]
            }
        } else {
            set data [dict create count 1 timestamp $now]
        }

        dict set requests $addr $data
        return 1  ;# OK
    }
}
```

## Files to Create

| File | Purpose |
|------|---------|
| `mcp/server.tcl` | Main MCP server executable |
| `mcp/lib/jsonrpc.tcl` | JSON-RPC 2.0 handling (uses tcllib json) |
| `mcp/lib/session.tcl` | SSH session manager |
| `mcp/lib/pool.tcl` | Connection pooling |
| `mcp/lib/tools.tcl` | MCP tool definitions and handlers |
| `mcp/lib/log.tcl` | Structured JSON logging |
| `mcp/lib/metrics.tcl` | Prometheus metrics |
| `mcp/lib/security.tcl` | Path/command validation, allowlists |
| `mcp/lib/lifecycle.tcl` | Signal handling, graceful shutdown |
| `mcp/tests/run_mcp_tests.sh` | MCP test runner |
| `mcp/tests/mock/test_jsonrpc.sh` | JSON-RPC tests |
| `mcp/tests/mock/test_session.sh` | Session manager tests |
| `mcp/tests/mock/test_pool.sh` | Connection pool tests |
| `mcp/tests/mock/test_security.sh` | Security validation tests |
| `mcp/tests/mock/test_tools.sh` | Tool handler tests |
| `mcp/tests/mock/helpers/mock_mcp_server.tcl` | Mock server for client tests |
| `mcp/tests/real/test_mcp_connect.sh` | Real SSH via MCP |
| `mcp/tests/real/test_mcp_commands.sh` | Command execution via MCP |
| `mcp/tests/real/test_mcp_session.sh` | Session lifecycle tests |
| `mcp/tests/real/test_mcp_pool.sh` | Real pool behavior tests |
| `mcp/tests/client/mcp_client.sh` | Bash test client |
| `mcp/tests/client/mcp_client.tcl` | TCL test client |
| `mcp/config/allowlist.conf` | Command allowlist configuration |

## Verification

1. **Unit tests pass**: `./mcp/tests/run_mcp_tests.sh`
2. **Integration tests pass** (mock): Tests with mock SSH
3. **Integration tests pass** (real): Tests with real SSH target
4. **All shellcheck passes**: `./tests/run_shellcheck.sh`
5. **Manual verification**:
   ```bash
   # Terminal 1: Start server
   ./mcp/server.tcl --port 3000 --debug 4

   # Terminal 2: Test with curl
   curl -X POST http://localhost:3000/ \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
   ```

## Future Extensions

1. **Streaming responses** - Use Server-Sent Events for long-running commands
2. **WebSocket transport** - Alternative to HTTP for persistent connections
3. **Resource support** - MCP resources for file browsing
4. **Prompt support** - MCP prompts for common workflows
5. **Connection pooling** - Reuse SSH connections across requests
6. **Clustering** - Multiple MCP servers with shared session state
