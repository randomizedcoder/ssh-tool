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

  # Import shared test helpers
  nixLib = import ../lib { inherit pkgs lib; };
  mcpHealthCheck = nixLib.testHelpers.mcpHealthCheck network.mcpVmIp;

  # Common runtime inputs for load test scripts
  # Use TCL 9.0 as required by the load test framework
  runtimeInputs = with pkgs; [
    tcl-9_0
    curl
    jq
    netcat-gnu
    procps
    coreutils
  ];

  # Copy the entire MCP agent directory to preserve the loadtest structure
  mcpAgentDir = pkgs.stdenv.mkDerivation {
    name = "mcp-agent-loadtest";
    src = ../../mcp/agent;
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out
      cp -r $src/* $out/
    '';
  };

  # Path to the loadtest run script
  loadtestScript = "${mcpAgentDir}/loadtest/run.tcl";

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

      ${mcpHealthCheck}

      echo ""
      echo "Running quick load test..."
      tclsh ${loadtestScript} --quick \
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

      ${mcpHealthCheck}

      echo ""
      tclsh ${loadtestScript} \
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

      ${mcpHealthCheck}

      echo ""
      tclsh ${loadtestScript} --full \
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

      ${mcpHealthCheck}

      tclsh ${loadtestScript} \
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

      ${mcpHealthCheck}

      tclsh ${loadtestScript} \
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

      ${mcpHealthCheck}

      tclsh ${loadtestScript} \
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
      tclsh ${loadtestScript} --list-scenarios
    '';
  };

  # Metrics scraper (for debugging)
  scrapeMetrics = pkgs.writeShellApplication {
    name = "ssh-loadtest-metrics";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
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
