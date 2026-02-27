# nix/tests/parallel-test.nix
#
# Parallel SSH command test for MCP server.
# Tests how fast N parallel SSH commands complete through the MCP server.
#
{ pkgs, lib }:
let
  constants = import ../constants;
  network = constants.network;
  users = constants.users;

  # Import shared test helpers
  nixLib = import ../lib { inherit pkgs lib; };
  mcpHealthCheck = nixLib.testHelpers.mcpHealthCheck network.mcpVmIp;

  # Common runtime inputs
  runtimeInputs = with pkgs; [
    curl
    jq
    coreutils
    bc
    gnugrep
    gnused
  ];

  # MCP JSON-RPC request helper (inline)
  mcpRequestScript = ''
    MCP_SESSION_ID=""
    REQUEST_ID=0
    # Temp file for session ID (shared across subshells)
    MCP_SESSION_FILE=""

    mcp_request() {
      local method="$1"
      local params="$2"

      ((REQUEST_ID++))

      local request
      if [ -z "$params" ] || [ "$params" == "{}" ]; then
        request="{\"jsonrpc\":\"2.0\",\"id\":$REQUEST_ID,\"method\":\"$method\",\"params\":{}}"
      else
        request="{\"jsonrpc\":\"2.0\",\"id\":$REQUEST_ID,\"method\":\"$method\",\"params\":$params}"
      fi

      local headers=()
      headers+=(-H "Content-Type: application/json")
      # Read session ID from file if available (works across subshells)
      if [ -n "$MCP_SESSION_FILE" ] && [ -f "$MCP_SESSION_FILE" ]; then
        MCP_SESSION_ID=$(cat "$MCP_SESSION_FILE")
      fi
      if [ -n "$MCP_SESSION_ID" ]; then
        headers+=(-H "Mcp-Session-Id: $MCP_SESSION_ID")
      fi

      local response
      response=$(curl -s -D - "''${headers[@]}" \
        -d "$request" \
        "http://''${MCP_HOST}:''${MCP_PORT}/")

      # Extract session ID from headers and save to file
      local new_session
      new_session=$(echo "$response" | grep -i "Mcp-Session-Id:" | cut -d: -f2 | tr -d ' \r\n')
      if [ -n "$new_session" ]; then
        MCP_SESSION_ID="$new_session"
        if [ -n "$MCP_SESSION_FILE" ]; then
          echo "$new_session" > "$MCP_SESSION_FILE"
        fi
      fi

      # Return body only (after blank line)
      echo "$response" | sed -n '/^\r$/,''${/^\r$/!p}'
    }

    mcp_initialize() {
      local params='{"protocolVersion":"2024-11-05","clientInfo":{"name":"parallel-test","version":"1.0.0"}}'
      # Session file should be set by caller via MCP_SESSION_FILE env var
      mcp_request "initialize" "$params"
    }

    ssh_connect() {
      local host="$1" user="$2" password="$3" port="$4"
      local params
      params=$(printf '{"host":"%s","user":"%s","password":"%s","port":%d}' "$host" "$user" "$password" "$port")
      mcp_request "tools/call" "{\"name\":\"ssh_connect\",\"arguments\":$params}"
    }

    ssh_run_command() {
      local session_id="$1" command="$2"
      local params
      params=$(printf '{"session_id":"%s","command":"%s"}' "$session_id" "$command")
      mcp_request "tools/call" "{\"name\":\"ssh_run_command\",\"arguments\":$params}"
    }

    ssh_disconnect() {
      local session_id="$1"
      local params
      params=$(printf '{"session_id":"%s"}' "$session_id")
      mcp_request "tools/call" "{\"name\":\"ssh_disconnect\",\"arguments\":$params}"
    }

    extract_session_id() {
      echo "$1" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4
    }
  '';

in
{
  # Parallel command test - configurable count
  parallel = pkgs.writeShellApplication {
    name = "ssh-test-parallel";
    inherit runtimeInputs;
    text = ''
      set -euo pipefail

      # Configuration with defaults for VM infrastructure
      MCP_HOST="''${MCP_HOST:-${network.mcpVmIp}}"
      MCP_PORT="''${MCP_PORT:-3000}"
      SSH_HOST="''${SSH_HOST:-${network.targetVmIp}}"
      SSH_USER="''${SSH_USER:-testuser}"
      SSH_PASSWORD="''${PASSWORD:-${users.testuser.password}}"
      SSH_PORT="''${SSH_PORT:-2222}"
      NUM_COMMANDS="''${NUM_COMMANDS:-20}"
      COMMAND="''${COMMAND:-hostname}"

      ${mcpRequestScript}

      echo "=============================================="
      echo "Parallel SSH Commands Test"
      echo "=============================================="
      echo "MCP Server: http://''${MCP_HOST}:''${MCP_PORT}"
      echo "SSH Target: ''${SSH_USER}@''${SSH_HOST}:''${SSH_PORT}"
      echo "Commands: ''${NUM_COMMANDS} x '$COMMAND'"
      echo ""

      ${mcpHealthCheck}

      # Create temp dir for results (needed for session file)
      RESULTS_DIR=$(mktemp -d)
      trap 'rm -rf "$RESULTS_DIR"' EXIT

      # Initialize MCP session - set up session file first to persist across subshells
      echo "Initializing MCP session..."
      MCP_SESSION_FILE="$RESULTS_DIR/mcp_session_id"
      export MCP_SESSION_FILE
      response=$(mcp_initialize)
      if echo "$response" | grep -q '"error"'; then
        echo "ERROR: Failed to initialize: $response"
        exit 1
      fi
      # Read session ID from file (subshell wrote it there)
      if [ -f "$MCP_SESSION_FILE" ]; then
        MCP_SESSION_ID=$(cat "$MCP_SESSION_FILE")
      fi
      echo "MCP Session: $MCP_SESSION_ID"

      echo ""
      echo "Creating $NUM_COMMANDS parallel SSH sessions..."
      echo ""

      # Start timing for connection phase
      CONNECT_START=$(date +%s.%N)

      # Create multiple SSH sessions in parallel (one per command)
      # Each session runs independently to avoid pty race conditions
      # Server returns "busy" if another connection is in progress - retry with backoff
      for i in $(seq 1 "$NUM_COMMANDS"); do
        (
          session_id=""
          max_retries=30
          retry=0

          # Retry loop for "busy" responses
          while [ -z "$session_id" ] && [ "$retry" -lt "$max_retries" ]; do
            conn_response=$(ssh_connect "$SSH_HOST" "$SSH_USER" "$SSH_PASSWORD" "$SSH_PORT")

            # Check if server is busy
            if echo "$conn_response" | grep -q "busy\|Server busy"; then
              ((retry++)) || true
              # Random backoff (0.5-2 seconds) to avoid thundering herd
              sleep "0.$((RANDOM % 15 + 5))"
              continue
            fi

            session_id=$(echo "$conn_response" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
            if [ -z "$session_id" ]; then
              # Not busy but no session - real error
              echo "connect_failed" > "$RESULTS_DIR/result_$i.json"
              break
            fi
          done

          if [ -z "$session_id" ]; then
            # Max retries reached
            echo "max_retries" > "$RESULTS_DIR/result_$i.json"
          else
            echo "$session_id" > "$RESULTS_DIR/session_$i.txt"
            # Run command on this session
            result=$(ssh_run_command "$session_id" "$COMMAND")
            echo "$result" > "$RESULTS_DIR/result_$i.json"
            # Disconnect this session
            ssh_disconnect "$session_id" > /dev/null 2>&1 || true
          fi
        ) &
      done

      # Wait for all parallel operations to complete
      echo "Waiting for $NUM_COMMANDS parallel operations..."
      wait

      END_TIME=$(date +%s.%N)
      ELAPSED=$(echo "$END_TIME - $CONNECT_START" | bc)

      # Count successes/failures
      SUCCESS=0
      FAILED=0
      for i in $(seq 1 "$NUM_COMMANDS"); do
        result_file="$RESULTS_DIR/result_$i.json"
        if [ -f "$result_file" ]; then
          content=$(cat "$result_file")
          if [ "$content" = "connect_failed" ] || [ "$content" = "max_retries" ]; then
            ((FAILED++)) || true
          elif echo "$content" | grep -q '"isError":true'; then
            ((FAILED++)) || true
          elif echo "$content" | grep -q '"content"'; then
            ((SUCCESS++)) || true
          else
            ((FAILED++)) || true
          fi
        else
          ((FAILED++)) || true
        fi
      done

      echo ""
      echo "All sessions completed."

      # Report
      echo ""
      echo "=============================================="
      echo "Results"
      echo "=============================================="
      echo "Total commands: $NUM_COMMANDS"
      echo "Successful: $SUCCESS"
      echo "Failed: $FAILED"
      echo "Total time: ''${ELAPSED}s"

      if [ "$SUCCESS" -gt 0 ]; then
        RATE=$(echo "scale=2; $SUCCESS / $ELAPSED" | bc)
        echo "Throughput: ''${RATE} commands/second"
      fi

      if [ "$FAILED" -gt 0 ]; then
        echo "WARNING: Some commands failed"
        exit 1
      fi

      echo ""
      echo "Test PASSED"
    '';
  };

  # Quick parallel test (10 commands)
  quick = pkgs.writeShellApplication {
    name = "ssh-test-parallel-quick";
    inherit runtimeInputs;
    text = ''
      NUM_COMMANDS=10 exec ${
        pkgs.writeShellApplication {
          name = "ssh-test-parallel-inner";
          inherit runtimeInputs;
          text = "exec $0 \"$@\"";
        }
      }/bin/ssh-test-parallel-inner
    '';
  };

  # Stress test (100 commands)
  stress = pkgs.writeShellApplication {
    name = "ssh-test-parallel-stress";
    inherit runtimeInputs;
    text = ''
      set -euo pipefail
      NUM_COMMANDS="''${1:-100}"
      export NUM_COMMANDS
      echo "Running stress test with $NUM_COMMANDS parallel commands..."
      # Re-exec with the parallel test
      MCP_HOST="''${MCP_HOST:-${network.mcpVmIp}}"
      MCP_PORT="''${MCP_PORT:-3000}"
      SSH_HOST="''${SSH_HOST:-${network.targetVmIp}}"
      SSH_USER="''${SSH_USER:-testuser}"
      PASSWORD="''${PASSWORD:-${users.testuser.password}}"
      SSH_PORT="''${SSH_PORT:-2222}"
      export MCP_HOST MCP_PORT SSH_HOST SSH_USER PASSWORD SSH_PORT NUM_COMMANDS

      # Inline the test since we can't easily cross-reference
      ${mcpRequestScript}

      echo "=============================================="
      echo "Parallel SSH Stress Test"
      echo "=============================================="
      echo "MCP Server: http://''${MCP_HOST}:''${MCP_PORT}"
      echo "SSH Target: ''${SSH_USER}@''${SSH_HOST}:''${SSH_PORT}"
      echo "Commands: ''${NUM_COMMANDS}"
      echo ""

      ${mcpHealthCheck}

      # Create temp dir for results (needed for session file)
      RESULTS_DIR=$(mktemp -d)
      trap 'rm -rf "$RESULTS_DIR"' EXIT

      # Initialize MCP session - set up session file first to persist across subshells
      echo "Initializing MCP session..."
      MCP_SESSION_FILE="$RESULTS_DIR/mcp_session_id"
      export MCP_SESSION_FILE
      response=$(mcp_initialize)
      if echo "$response" | grep -q '"error"'; then
        echo "ERROR: Failed to initialize: $response"
        exit 1
      fi
      # Read session ID from file (subshell wrote it there)
      if [ -f "$MCP_SESSION_FILE" ]; then
        MCP_SESSION_ID=$(cat "$MCP_SESSION_FILE")
      fi
      echo "MCP Session: $MCP_SESSION_ID"

      echo ""
      echo "Creating $NUM_COMMANDS parallel SSH sessions..."

      START_TIME=$(date +%s.%N)

      # Each parallel worker creates its own SSH session to avoid pty race conditions
      # Server returns "busy" if another connection is in progress - retry with backoff
      for i in $(seq 1 "$NUM_COMMANDS"); do
        (
          session_id=""
          max_retries=60
          retry=0

          # Retry loop for "busy" responses
          while [ -z "$session_id" ] && [ "$retry" -lt "$max_retries" ]; do
            conn_response=$(ssh_connect "$SSH_HOST" "$SSH_USER" "$PASSWORD" "$SSH_PORT")

            # Check if server is busy
            if echo "$conn_response" | grep -q "busy\|Server busy"; then
              ((retry++)) || true
              sleep "0.$((RANDOM % 15 + 5))"
              continue
            fi

            session_id=$(echo "$conn_response" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
            if [ -z "$session_id" ]; then
              echo "connect_failed" > "$RESULTS_DIR/result_$i.json"
              break
            fi
          done

          if [ -z "$session_id" ]; then
            [ ! -f "$RESULTS_DIR/result_$i.json" ] && echo "max_retries" > "$RESULTS_DIR/result_$i.json"
          else
            # Run command on this session
            result=$(ssh_run_command "$session_id" "hostname")
            echo "$result" > "$RESULTS_DIR/result_$i.json"
            # Disconnect this session
            ssh_disconnect "$session_id" > /dev/null 2>&1 || true
          fi
        ) &
      done

      echo "Waiting for $NUM_COMMANDS parallel operations..."
      wait

      END_TIME=$(date +%s.%N)
      ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)

      SUCCESS=0
      FAILED=0
      for i in $(seq 1 "$NUM_COMMANDS"); do
        result_file="$RESULTS_DIR/result_$i.json"
        if [ -f "$result_file" ]; then
          content=$(cat "$result_file")
          if [ "$content" = "connect_failed" ] || [ "$content" = "max_retries" ]; then
            ((FAILED++)) || true
          elif echo "$content" | grep -q '"isError":true'; then
            ((FAILED++)) || true
          elif echo "$content" | grep -q '"content"'; then
            ((SUCCESS++)) || true
          else
            ((FAILED++)) || true
          fi
        else
          ((FAILED++)) || true
        fi
      done

      echo ""
      echo "=============================================="
      echo "Stress Test Results"
      echo "=============================================="
      echo "Total commands: $NUM_COMMANDS"
      echo "Successful: $SUCCESS"
      echo "Failed: $FAILED"
      echo "Total time: ''${ELAPSED}s"

      if [ "$SUCCESS" -gt 0 ]; then
        RATE=$(echo "scale=2; $SUCCESS / $ELAPSED" | bc)
        echo "Throughput: ''${RATE} commands/second"
      fi

      [ "$FAILED" -eq 0 ] && echo "Test PASSED" || { echo "Test FAILED"; exit 1; }
    '';
  };
}
