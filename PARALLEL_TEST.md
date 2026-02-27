# Parallel SSH Command Test

Test parallel SSH command execution throughput via the MCP server.

## Overview

This test measures how fast the MCP server can execute multiple SSH commands in parallel. It:

1. Connects to the MCP server
2. Establishes a single SSH session
3. Fires N commands simultaneously in parallel
4. Measures total time and calculates throughput (commands/second)

## Apps

| App | Description |
|-----|-------------|
| `ssh-test-parallel` | Run 20 parallel commands (configurable) |
| `ssh-test-parallel-stress` | Run 100 parallel commands |

## Usage

### With VM Infrastructure

```bash
# Terminal 1: Start MCP server VM
nix run .#mcp-vm-tap

# Terminal 2: Start SSH target VM
nix run .#ssh-target-vm-tap

# Terminal 3: Run parallel test
nix run .#ssh-test-parallel
```

### With External Targets

```bash
# Start MCP server locally
./mcp/server.tcl --port 3000

# Run test against external SSH host
MCP_HOST=localhost \
MCP_PORT=3000 \
SSH_HOST=192.168.1.100 \
SSH_USER=myuser \
PASSWORD=mypass \
SSH_PORT=22 \
nix run .#ssh-test-parallel
```

## Configuration

All settings have defaults for the VM infrastructure:

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_HOST` | 10.178.0.10 | MCP server IP |
| `MCP_PORT` | 3000 | MCP server port |
| `SSH_HOST` | 10.178.0.20 | SSH target IP |
| `SSH_USER` | testuser | SSH username |
| `PASSWORD` | testpass | SSH password |
| `SSH_PORT` | 2222 | SSH port |
| `NUM_COMMANDS` | 20 | Number of parallel commands |
| `COMMAND` | hostname | Command to execute |

### Examples

```bash
# Run 50 parallel commands
NUM_COMMANDS=50 nix run .#ssh-test-parallel

# Run with different command
COMMAND="uname -a" nix run .#ssh-test-parallel

# Stress test with 200 commands
NUM_COMMANDS=200 nix run .#ssh-test-parallel-stress
```

## Example Output

```
==============================================
Parallel SSH Commands Test
==============================================
MCP Server: http://10.178.0.10:3000
SSH Target: testuser@10.178.0.20:2222
Commands: 20 x 'hostname'

Checking MCP server health...
MCP server is ready
Initializing MCP session...
MCP Session: abc123
Connecting to SSH...
SSH Session: ssh_1

Running 20 commands in parallel...

Disconnecting SSH session...

==============================================
Results
==============================================
Total commands: 20
Successful: 20
Failed: 0
Total time: 2.45s
Throughput: 8.16 commands/second

Test PASSED
```

## Implementation

Located in `nix/tests/parallel-test.nix`, uses `writeShellApplication` pattern.

The test:
- Uses curl for HTTP/JSON-RPC communication with MCP server
- Launches all commands as background bash jobs (`&`)
- Waits for all to complete with `wait`
- Collects results from temp files
- Calculates timing with `bc`

## Related

- `nix run .#ssh-loadtest` - Full load testing suite with multiple scenarios
- `nix run .#ssh-test-e2e` - End-to-end functional tests
- `mcp/agent/loadtest/` - TCL-based load test framework
