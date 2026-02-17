# Load Testing Framework

Performance and load testing framework for the MCP SSH Automation Server.

## Quick Start

```bash
# Enter nix development shell
nix develop

# Start the 3-VM infrastructure (requires sudo for TAP networking)
sudo nix run .#ssh-network-setup
nix build .#ssh-target-vm-tap-debug && ./result/bin/microvm-run &
nix build .#mcp-vm-tap-debug && ./result/bin/microvm-run &

# Wait for VMs to boot (~30s)

# Run quick smoke test (30 seconds)
nix run .#ssh-loadtest-quick

# Run full test suite (all 5 scenarios, ~15 minutes)
nix run .#ssh-loadtest-full

# Cleanup
sudo nix run .#ssh-network-teardown
```

## Available Commands

| Command | Description |
|---------|-------------|
| `nix run .#ssh-loadtest-quick` | 30-second smoke test |
| `nix run .#ssh-loadtest -- <scenario> [duration] [workers]` | Run specific scenario |
| `nix run .#ssh-loadtest-full` | All 5 scenarios |
| `nix run .#ssh-loadtest-list` | List available scenarios |
| `nix run .#ssh-loadtest-connection-rate` | Connection rate test |
| `nix run .#ssh-loadtest-throughput` | Command throughput test |
| `nix run .#ssh-loadtest-latency` | Latency sensitivity test |
| `nix run .#ssh-loadtest-metrics` | Scrape MCP metrics |

## Scenarios

### 1. Connection Rate Test
Measures maximum SSH connection establishment rate.
- Duration: 60s
- Tests with 1, 2, 5, 10 workers
- Operation: connect/disconnect cycles

### 2. Command Throughput Test
Measures maximum commands per second on established connections.
- Duration: 120s
- Workers: 10
- Commands: hostname, whoami, cat /etc/hostname

### 3. Sustained Load Test
Identifies resource leaks and degradation over time.
- Duration: 600s (10 minutes)
- Workload: 70% commands, 20% connect, 10% disconnect

### 4. Latency Sensitivity Test
Measures impact of network latency on throughput using netem ports.
- Tests ports: 2222 (baseline), 2322-2328 (degraded)
- Network conditions: 50ms-500ms latency, 2-10% packet loss

### 5. Pool Exhaustion Test
Verifies graceful degradation when limits are exceeded.
- Exceeds: pool limit (10), rate limit (100 req/min)
- Verifies proper error handling

## Manual Usage

```bash
# From the agent VM or development shell
tclsh mcp/agent/loadtest/run.tcl --help

# Run specific scenario with overrides
tclsh mcp/agent/loadtest/run.tcl \
  --scenario command_throughput \
  --duration 60 \
  --workers 5 \
  --mcp-host 10.178.0.10 \
  --target-host 10.178.0.20
```

## Output

Results are saved to `/tmp/loadtest_results/<test_id>/`:
- `*.jsonl` - Raw per-worker results
- `summary.json` - Aggregated results and metrics

Example report output:
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
EXTRAPOLATION (to 8 CPU / 16GB RAM)
----------------------------------------------------------------------

  Measured RPS:      37.7 (on 4 cores)
  Estimated RPS:     64.1 (on 8 cores)
  Scaling factor:    1.70x

  Confidence:        MEDIUM (based on linear scaling model)
======================================================================
```

## Architecture

```
mcp/agent/loadtest/
├── run.tcl              # Main entry point
├── config.tcl           # Configuration parameters
├── coordinator.tcl      # Multi-process orchestration
├── worker.tcl           # Individual load generator
├── scenarios/           # Test scenario definitions
│   ├── connection_rate.tcl
│   ├── command_throughput.tcl
│   ├── sustained_load.tcl
│   ├── latency_test.tcl
│   └── exhaustion_test.tcl
├── metrics/             # Metrics collection
│   ├── collector.tcl    # Scrapes /metrics endpoint
│   ├── aggregator.tcl   # Combines worker results
│   └── percentiles.tcl  # Statistical calculations
└── output/              # Output generation
    ├── jsonl_writer.tcl # Raw data output
    └── report.tcl       # Summary reports
```

## VM Resources

Default load test VM configuration (from `nix/constants/loadtest.nix`):

| VM | Memory | vCPUs |
|----|--------|-------|
| Agent | 512 MB | 2 |
| MCP | 1 GB | 4 |
| Target | 1 GB | 4 |

Total: ~2.5 GB RAM, 10 cores

## Metrics

The framework collects:
- Client-side: request latency, success/error counts, throughput
- Server-side: Prometheus metrics from `/metrics` endpoint

Pool metrics tracked:
- `mcp_pool_hits_total` - Connection pool reuse
- `mcp_pool_misses_total` - New connections created
- `mcp_pool_creates_total` - Total connections established
- `mcp_pool_health_fails_total` - Failed health checks
