# nix/tests/loadtest.nix
#
# Load test runner scripts for SSH-Tool MicroVM infrastructure.
# Provides apps for running various load test scenarios.
#
{ pkgs, lib }:
let
  constants = import ../constants;
  network = constants.network;
  loadtest = constants.loadtest;

  # Common runtime inputs for load test scripts
  runtimeInputs = with pkgs; [
    tcl
    curl
    jq
    netcat-gnu
    procps
    coreutils
  ];

  # Health check helper
  healthCheck = ''
    echo "Checking MCP server health..."
    for i in $(seq 1 30); do
      if curl -sf "http://${network.mcpVmIp}:3000/health" >/dev/null 2>&1; then
        echo "MCP server is ready"
        break
      fi
      if [ "$i" -eq 30 ]; then
        echo "ERROR: MCP server not responding after 30 seconds"
        exit 1
      fi
      sleep 1
    done
  '';

in
{
  # Quick smoke test (30 seconds)
  quick = pkgs.writeShellApplication {
    name = "ssh-loadtest-quick";
    inherit runtimeInputs;
    text = ''
      set -euo pipefail

      echo "=== SSH-Tool Load Test: Quick (30s) ==="
      echo ""

      ${healthCheck}

      echo ""
      echo "Running quick load test..."
      tclsh ${../../mcp/agent/loadtest/run.tcl} --quick \
        --mcp-host ${network.mcpVmIp} \
        --target-host ${network.targetVmIp}

      echo ""
      echo "=== Quick Load Test Complete ==="
    '';
  };

  # Standard load test (single scenario)
  standard = pkgs.writeShellApplication {
    name = "ssh-loadtest";
    inherit runtimeInputs;
    text = ''
      set -euo pipefail

      SCENARIO="''${1:-command_throughput}"
      DURATION="''${2:-60}"
      WORKERS="''${3:-5}"

      echo "=== SSH-Tool Load Test ==="
      echo "Scenario: $SCENARIO"
      echo "Duration: ''${DURATION}s"
      echo "Workers:  $WORKERS"
      echo ""

      ${healthCheck}

      echo ""
      tclsh ${../../mcp/agent/loadtest/run.tcl} \
        --scenario "$SCENARIO" \
        --duration "$DURATION" \
        --workers "$WORKERS" \
        --mcp-host ${network.mcpVmIp} \
        --target-host ${network.targetVmIp}
    '';
  };

  # Full load test suite (all scenarios)
  full = pkgs.writeShellApplication {
    name = "ssh-loadtest-full";
    inherit runtimeInputs;
    text = ''
      set -euo pipefail

      echo "=== SSH-Tool Load Test: Full Suite ==="
      echo ""
      echo "This will run all 5 load test scenarios."
      echo "Estimated time: 15-20 minutes"
      echo ""

      ${healthCheck}

      echo ""
      tclsh ${../../mcp/agent/loadtest/run.tcl} --full \
        --mcp-host ${network.mcpVmIp} \
        --target-host ${network.targetVmIp}

      echo ""
      echo "=== Full Load Test Suite Complete ==="
    '';
  };

  # Connection rate test
  connectionRate = pkgs.writeShellApplication {
    name = "ssh-loadtest-connection-rate";
    inherit runtimeInputs;
    text = ''
      set -euo pipefail

      DURATION="''${1:-60}"

      echo "=== Connection Rate Test ==="

      ${healthCheck}

      tclsh ${../../mcp/agent/loadtest/run.tcl} \
        --scenario connection_rate \
        --duration "$DURATION" \
        --mcp-host ${network.mcpVmIp} \
        --target-host ${network.targetVmIp}
    '';
  };

  # Command throughput test
  commandThroughput = pkgs.writeShellApplication {
    name = "ssh-loadtest-throughput";
    inherit runtimeInputs;
    text = ''
      set -euo pipefail

      DURATION="''${1:-120}"
      WORKERS="''${2:-10}"

      echo "=== Command Throughput Test ==="

      ${healthCheck}

      tclsh ${../../mcp/agent/loadtest/run.tcl} \
        --scenario command_throughput \
        --duration "$DURATION" \
        --workers "$WORKERS" \
        --mcp-host ${network.mcpVmIp} \
        --target-host ${network.targetVmIp}
    '';
  };

  # Latency sensitivity test
  latencyTest = pkgs.writeShellApplication {
    name = "ssh-loadtest-latency";
    inherit runtimeInputs;
    text = ''
      set -euo pipefail

      echo "=== Latency Sensitivity Test ==="
      echo "Testing against netem ports (2322-2328)"

      ${healthCheck}

      tclsh ${../../mcp/agent/loadtest/run.tcl} \
        --scenario latency_test \
        --mcp-host ${network.mcpVmIp} \
        --target-host ${network.targetVmIp}
    '';
  };

  # List available scenarios
  listScenarios = pkgs.writeShellApplication {
    name = "ssh-loadtest-list";
    inherit runtimeInputs;
    text = ''
      tclsh ${../../mcp/agent/loadtest/run.tcl} --list-scenarios
    '';
  };

  # Metrics scraper (for debugging)
  scrapeMetrics = pkgs.writeShellApplication {
    name = "ssh-loadtest-metrics";
    runtimeInputs = with pkgs; [ curl jq ];
    text = ''
      set -euo pipefail

      echo "=== MCP Server Metrics ==="
      echo ""

      if ! curl -sf "http://${network.mcpVmIp}:3000/metrics"; then
        echo "ERROR: Could not fetch metrics from MCP server"
        exit 1
      fi
    '';
  };
}
