# MCP Server Load Testing Guide

Step-by-step guide for running performance tests against the MCP SSH Automation Server.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Host Machine                               │
│   ┌───────────────────────────────────────────────────────────────────┐ │
│   │                     sshbr0 (10.178.0.1/24)                        │ │
│   │                         Network Bridge                            │ │
│   └───────┬─────────────────────┬─────────────────────┬───────────────┘ │
│           │                     │                     │                  │
│       sshtap0               sshtap1               sshtap2                │
│           │                     │                     │                  │
│  ┌────────┴────────┐ ┌──────────┴──────────┐ ┌────────┴────────┐        │
│  │    Agent VM     │ │      MCP VM         │ │    Target VM    │        │
│  │   10.178.0.5    │ │    10.178.0.10      │ │   10.178.0.20   │        │
│  │                 │ │                     │ │                 │        │
│  │  Load Generator │ │  MCP Server :3000   │ │  SSHD instances │        │
│  │  (TCL workers)  │ │  Session Pool       │ │  :2222-2228     │        │
│  │                 │ │  Prometheus metrics │ │  :2322-2328     │        │
│  └─────────────────┘ └─────────────────────┘ └─────────────────┘        │
└─────────────────────────────────────────────────────────────────────────┘
```

### VMs

| VM | IP Address | Purpose |
|----|------------|---------|
| **Agent** | 10.178.0.5 | TCL load generator - spawns workers that send HTTP/JSON-RPC requests |
| **MCP** | 10.178.0.10:3000 | MCP server - manages SSH session pool, processes JSON-RPC requests |
| **Target** | 10.178.0.20 | SSH target - multiple SSHD instances for testing various conditions |

### Target VM Ports

| Port Range | Description |
|------------|-------------|
| 2222-2228 | Standard SSHD instances (password auth, key-only, slow auth, etc.) |
| 2322-2328 | Netem ports - network degradation simulation (latency, packet loss) |

## Prerequisites

- Linux with KVM support (`/dev/kvm` accessible)
- Nix package manager
- ~3 GB RAM available for VMs
- sudo access (for TAP networking)

## Quick Start

### Step 1: Setup Network Bridge

```bash
# Creates bridge sshbr0 + 3 TAP devices (requires sudo)
sudo nix run .#ssh-network-setup
```

### Step 2: Start VMs (3 terminals)

**Terminal 1 - Target VM:**
```bash
nix build .#ssh-target-vm-tap-debug && ./result/bin/microvm-run
```

**Terminal 2 - MCP VM:**
```bash
nix build .#mcp-vm-tap-debug && ./result/bin/microvm-run
```

**Terminal 3 - Wait for boot (~30 seconds), then verify:**
```bash
# Check MCP server is responding
curl -sf http://10.178.0.10:3000/health

# Expected output: {"status":"healthy",...}
```

### Step 3: Run Load Tests

```bash
# Quick smoke test (30 seconds)
nix run .#ssh-loadtest-quick

# Standard test - specific scenario
nix run .#ssh-loadtest -- command_throughput 60 5

# Full suite - all 5 scenarios (~15-20 minutes)
nix run .#ssh-loadtest-full
```

### Step 4: Cleanup

```bash
# Stop VMs (Ctrl+C in each terminal, or)
pkill -f "microvm.*ssh"

# Remove network bridge
sudo nix run .#ssh-network-teardown
```

## Load Test Scenarios

### 1. Connection Rate Test (`connection_rate`)

Measures maximum SSH connection establishment rate.

- **Duration:** 60 seconds
- **Workers:** Tests with 1, 2, 5, 10 workers sequentially
- **Workload:** Pure connect/disconnect cycles (no commands)
- **Purpose:** Find connection pool saturation point

```bash
nix run .#ssh-loadtest-connection-rate
# or
nix run .#ssh-loadtest -- connection_rate 60
```

### 2. Command Throughput Test (`command_throughput`)

Measures maximum commands per second on warm (pre-established) connections.

- **Duration:** 120 seconds
- **Workers:** 10
- **Pre-warm:** 5 sessions established before test
- **Commands:** `hostname`, `whoami`, `cat /etc/hostname`
- **Purpose:** Measure peak command processing rate

```bash
nix run .#ssh-loadtest-throughput
# or
nix run .#ssh-loadtest -- command_throughput 120 10
```

### 3. Sustained Load Test (`sustained_load`)

Identifies resource leaks and performance degradation over time.

- **Duration:** 600 seconds (10 minutes)
- **Workers:** 5
- **Workload Mix:**
  - 70% run commands
  - 20% establish new connections
  - 10% disconnect sessions
- **Rate:** ~50 ops/sec (20ms delay between ops)
- **Purpose:** Detect memory leaks, connection pool issues

```bash
nix run .#ssh-loadtest -- sustained_load 600 5
```

### 4. Latency Sensitivity Test (`latency_test`)

Measures impact of degraded network conditions on throughput.

- **Duration:** 60 seconds per port
- **Workers:** 3
- **Target Rate:** 10 commands/sec
- **Ports Tested:**

| Port | Description | Delay | Jitter | Loss |
|------|-------------|-------|--------|------|
| 2222 | baseline | - | - | - |
| 2322 | 100ms latency | 100ms | 10ms | - |
| 2323 | 50ms + loss | 50ms | 5ms | 5% |
| 2324 | severe | 200ms | 20ms | 10% |
| 2325 | very slow | 500ms | 50ms | - |

```bash
nix run .#ssh-loadtest-latency
```

### 5. Pool Exhaustion Test (`exhaustion_test`)

Verifies graceful degradation when limits are exceeded.

- **Duration:** 60 seconds
- **Workers:** 15
- **Target Connections:** 15 (exceeds pool limit of 10)
- **Expected:**
  - Connection pool: max 10 (load test config: 20)
  - Rate limit: 500 req/min (load test config, 5x normal)
- **Purpose:** Verify proper error handling at limits

```bash
nix run .#ssh-loadtest -- exhaustion_test 60 15
```

## Available Commands

| Command | Description |
|---------|-------------|
| `nix run .#ssh-loadtest-quick` | 30-second smoke test |
| `nix run .#ssh-loadtest -- <scenario> [duration] [workers]` | Run specific scenario |
| `nix run .#ssh-loadtest-full` | All 5 scenarios |
| `nix run .#ssh-loadtest-list` | List available scenarios |
| `nix run .#ssh-loadtest-connection-rate [duration]` | Connection rate test |
| `nix run .#ssh-loadtest-throughput [duration] [workers]` | Command throughput test |
| `nix run .#ssh-loadtest-latency` | Latency sensitivity test |
| `nix run .#ssh-loadtest-metrics` | Scrape MCP Prometheus metrics |

## Manual TCL Execution

Run directly with TCL (no Nix wrapper):

```bash
# List scenarios
tclsh mcp/agent/loadtest/run.tcl --list-scenarios

# Run with full options
tclsh mcp/agent/loadtest/run.tcl \
  --scenario command_throughput \
  --duration 120 \
  --workers 10 \
  --mcp-host 10.178.0.10 \
  --target-host 10.178.0.20 \
  --target-port 2222 \
  --user testuser \
  --password testpass \
  --verbose
```

## VM Resource Allocation

Load test VMs use increased resources (vs. standard testing):

| VM | Memory | vCPUs | Purpose |
|----|--------|-------|---------|
| Agent | 512 MB | 2 | Run multiple TCL worker processes |
| MCP | 1 GB | 4 | Handle concurrent sessions + Expect processes |
| Target | 1 GB | 4 | Handle multiple SSHD connections |

**Total:** ~2.5 GB RAM, 10 vCPUs

## Output and Results

### Results Location

```
/tmp/loadtest_results/<test_id>/
├── w0.jsonl          # Worker 0 raw results
├── w1.jsonl          # Worker 1 raw results
├── ...
└── summary.json      # Aggregated results
```

### JSONL Format (per operation)

```json
{"ts":1234567890,"worker":"w0","op":"ssh_connect","latency_ms":45.2,"status":"success"}
{"ts":1234567891,"worker":"w0","op":"ssh_run_command","latency_ms":23.1,"status":"success"}
```

### Sample Report Output

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

## Metrics Collection

### Client-Side (load generator)

- Request latency (min, p50, p95, p99, max)
- Throughput (requests/second, avg and peak)
- Success/error counts per operation type

### Server-Side (MCP `/metrics` endpoint)

| Metric | Description |
|--------|-------------|
| `mcp_pool_hits_total` | Connection pool cache hits |
| `mcp_pool_misses_total` | Cache misses (new connections) |
| `mcp_pool_creates_total` | Total connections established |
| `mcp_pool_health_fails_total` | Failed health checks |
| `mcp_ssh_command_duration_seconds` | Command latency histogram |

Scrape metrics manually:
```bash
curl http://10.178.0.10:3000/metrics
```

## Extrapolation Methodology

For estimating performance on larger hardware:

```
extrapolated_rps = measured_rps × (target_cpus / test_cpus) × 0.85
```

**Confidence levels** (based on MCP VM CPU utilization):

| Utilization | Confidence | Interpretation |
|-------------|------------|----------------|
| < 50% | LOW | Not CPU-bound, may not scale linearly |
| 50-80% | MEDIUM | Likely to scale well with more CPUs |
| > 80% | HIGH | Clearly CPU-bound, scaling should help |

## Sample Results

From a quick 60-second test with 5 workers:

```
Test ID:    loadtest_20260226_073527
Scenario:   command_throughput
Duration:   69.6s

THROUGHPUT
  Total Requests:     474
  Successful:         470 (99.2%)
  Failed:             4
  Requests/Second:    6.9 avg, 9.0 peak

LATENCY (milliseconds)
  Min:    64.0
  p50:    134.0
  p95:    147.0
  p99:    154.2
  Max:    9405.0
```

## Troubleshooting

### MCP server not reachable

```bash
# Check if VMs are running
pgrep -af "microvm.*ssh"

# Check network bridge
ip link show sshbr0

# Check MCP VM directly
curl -sf http://10.178.0.10:3000/health
```

### Connection timeouts

- Ensure all VMs have booted (~30 seconds after start)
- Check target VM SSHD is running: `ssh -p 2222 testuser@10.178.0.20`

### Rate limit errors

Load test config uses 5x normal limits:
- Connections: 20 (vs. 10 normal)
- Requests: 500/min (vs. 100/min normal)

If still hitting limits, wait 60 seconds or restart MCP VM.

### Out of memory

Reduce worker count or run fewer scenarios:
```bash
nix run .#ssh-loadtest -- command_throughput 60 3
```

### Multiple workers failing to connect

If you see "Initial connect failed" for multiple workers, this is usually due to:

1. **Connection pool saturation** - Workers are competing for limited connections
   - Reduce worker count (try 3 instead of 5)
   - Increase pool limits in MCP server config

2. **MCP session limits** - Too many simultaneous MCP sessions
   - The MCP server may reject rapid connection attempts
   - Add a warmup delay between worker spawns

3. **SSH target overload** - Too many concurrent SSH connections
   - The target VM may have connection limits
   - Check `sshd_config` MaxSessions setting

**Workaround:** Start with fewer workers and gradually increase:
```bash
# Start with 2 workers
nix run .#ssh-loadtest -- command_throughput 60 2

# If successful, try 3
nix run .#ssh-loadtest -- command_throughput 60 3
```

### Commands being blocked

If you see "ssh_commands_blocked" in metrics, this indicates the security module
is rejecting commands. Check:
- Command is on the allowlist (see `mcp/lib/security.tcl`)
- No shell metacharacters (|, ;, &&, ||, etc.)
- Valid path if accessing files

## Files Reference

| File | Purpose |
|------|---------|
| `mcp/agent/loadtest/run.tcl` | Main entry point |
| `mcp/agent/loadtest/config.tcl` | Default configuration |
| `mcp/agent/loadtest/coordinator.tcl` | Multi-worker orchestration |
| `mcp/agent/loadtest/worker.tcl` | Load generation process |
| `mcp/agent/loadtest/scenarios/*.tcl` | 5 scenario definitions |
| `mcp/agent/loadtest/metrics/` | Metrics collection |
| `mcp/agent/loadtest/output/report.tcl` | Report generation |
| `nix/tests/loadtest.nix` | Nix app definitions |
| `nix/constants/loadtest.nix` | VM resource config |
