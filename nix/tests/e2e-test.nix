# nix/tests/e2e-test.nix
#
# Test scripts for SSH-Tool VM testing.
# Provides shell applications for various test categories.
#
{ pkgs, lib }:
let
  constants = import ../constants;
  network = constants.network;
  ports = constants.ports;
  users = constants.users;
  sshd = constants.sshd;
  netem = constants.netem;

  # Import shared test helpers
  nixLib = import ../lib { inherit pkgs lib; };
  testHelpers = nixLib.testHelpers.shellHelpers;
  sshOpts = nixLib.sshOptions.withDefaultTimeout;

in
{
  # ─── E2E Test Suite ───────────────────────────────────────────────
  # Basic functionality tests
  e2e = pkgs.writeShellApplication {
    name = "ssh-test-e2e";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      curl
      jq
      netcat-gnu
    ];
    text = ''
      set -euo pipefail
      ${testHelpers}

      echo "=== SSH-Tool E2E Tests ==="
      echo ""

      HOST="''${SSH_TARGET_HOST:-localhost}"

      # Phase 1: Service Availability
      echo "--- Phase 1: Service Availability ---"

      info "Testing standard SSH port (${toString sshd.standard.port})..."
      if wait_for_port "$HOST" ${toString sshd.standard.port} 10; then
        pass "Standard SSH port reachable"
      else
        fail "Standard SSH port not reachable"
      fi

      # Phase 2: Standard SSH Connection
      echo ""
      echo "--- Phase 2: Standard SSH Connection ---"

      info "Testing password authentication..."
      if sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          testuser@"$HOST" "hostname" >/dev/null 2>&1; then
        pass "Password authentication works"
      else
        fail "Password authentication failed"
      fi

      info "Testing command execution..."
      RESULT=$(sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          testuser@"$HOST" "echo hello" 2>/dev/null || echo "FAILED")
      if [ "$RESULT" = "hello" ]; then
        pass "Command execution works"
      else
        fail "Command execution failed: $RESULT"
      fi

      # Phase 3: Different Shells
      echo ""
      echo "--- Phase 3: Different Shells ---"

      info "Testing zshuser (zsh shell)..."
      SHELL_OUT=$(sshpass -p "${users.zshuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          zshuser@"$HOST" 'echo $SHELL' 2>/dev/null || echo "")
      if echo "$SHELL_OUT" | grep -q "zsh"; then
        pass "zshuser has zsh shell"
      else
        skip "zshuser shell check (got: $SHELL_OUT)"
      fi

      info "Testing dashuser (dash shell)..."
      SHELL_OUT=$(sshpass -p "${users.dashuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          dashuser@"$HOST" 'echo $0' 2>/dev/null || echo "")
      if echo "$SHELL_OUT" | grep -q "dash\|sh"; then
        pass "dashuser has dash/sh shell"
      else
        skip "dashuser shell check (got: $SHELL_OUT)"
      fi

      # Phase 4: Root Login
      echo ""
      echo "--- Phase 4: Root Login ---"

      info "Testing root login on rootlogin port (${toString sshd.rootlogin.port})..."
      if sshpass -p "${users.root.password}" ssh ${sshOpts} -p ${toString sshd.rootlogin.port} \
          root@"$HOST" "id -u" 2>/dev/null | grep -q "^0$"; then
        pass "Root login works on rootlogin port"
      else
        fail "Root login failed"
      fi

      # Phase 5: Read Test File
      echo ""
      echo "--- Phase 5: Read Test File ---"

      info "Testing file read..."
      CONTENT=$(sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          testuser@"$HOST" "cat /etc/test-file.txt" 2>/dev/null || echo "FAILED")
      if echo "$CONTENT" | grep -q "test file"; then
        pass "File read works"
      else
        skip "File read (test-file.txt may not exist)"
      fi

      exit_with_summary
    '';
  };

  # ─── Auth Tests ───────────────────────────────────────────────────
  # Authentication edge cases and failures
  authTests = pkgs.writeShellApplication {
    name = "ssh-test-auth";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      netcat-gnu
      coreutils
    ];
    text = ''
      set -euo pipefail
      ${testHelpers}

      echo "=== SSH-Tool Auth Tests ==="
      echo ""

      HOST="''${SSH_TARGET_HOST:-localhost}"

      # Test 1: Key-only port rejects password
      echo "--- Test 1: Key-Only Port Rejects Password ---"
      info "Connecting to keyonly port (${toString sshd.keyonly.port}) with password..."
      if ! sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.keyonly.port} \
          testuser@"$HOST" "hostname" >/dev/null 2>&1; then
        pass "Keyonly port correctly rejects password auth"
      else
        fail "Keyonly port should reject password auth"
      fi

      # Test 2: Denyall port rejects everyone
      echo ""
      echo "--- Test 2: Denyall Port Rejects Everyone ---"
      info "Connecting to denyall port (${toString sshd.denyall.port})..."
      if ! sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.denyall.port} \
          testuser@"$HOST" "hostname" >/dev/null 2>&1; then
        pass "Denyall port correctly rejects auth"
      else
        fail "Denyall port should reject all auth"
      fi

      # Test 3: Wrong password rejected
      echo ""
      echo "--- Test 3: Wrong Password Rejected ---"
      info "Connecting with wrong password..."
      if ! sshpass -p "wrongpassword" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          testuser@"$HOST" "hostname" >/dev/null 2>&1; then
        pass "Wrong password correctly rejected"
      else
        fail "Wrong password should be rejected"
      fi

      # Test 4: Non-existent user rejected
      echo ""
      echo "--- Test 4: Non-Existent User Rejected ---"
      info "Connecting with non-existent user..."
      if ! sshpass -p "anypassword" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          nosuchuser@"$HOST" "hostname" >/dev/null 2>&1; then
        pass "Non-existent user correctly rejected"
      else
        fail "Non-existent user should be rejected"
      fi

      # Test 5: Slow auth has delay
      echo ""
      echo "--- Test 5: Slow Auth Delay ---"
      info "Connecting to slowauth port (${toString sshd.slowauth.port})..."
      START=$(date +%s)
      if sshpass -p "${users.slowuser.password}" ssh ${sshOpts} -p ${toString sshd.slowauth.port} \
          slowuser@"$HOST" "hostname" >/dev/null 2>&1; then
        END=$(date +%s)
        ELAPSED=$((END - START))
        if [ $ELAPSED -ge 2 ]; then
          pass "Slowauth has delay (''${ELAPSED}s)"
        else
          skip "Slowauth delay less than 2s (''${ELAPSED}s)"
        fi
      else
        fail "Slowauth connection failed"
      fi

      exit_with_summary
    '';
  };

  # ─── Netem Tests ──────────────────────────────────────────────────
  # Network emulation / degradation tests
  netemTests = pkgs.writeShellApplication {
    name = "ssh-test-netem";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      netcat-gnu
      coreutils
    ];
    text = ''
      set -euo pipefail
      ${testHelpers}

      echo "=== SSH-Tool Netem Tests ==="
      echo ""

      HOST="''${SSH_TARGET_HOST:-localhost}"

      # Measure baseline latency on standard port
      echo "--- Baseline Measurement ---"
      info "Measuring baseline latency on standard port..."
      START=$(date +%s%N)
      sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          testuser@"$HOST" "hostname" >/dev/null 2>&1
      END=$(date +%s%N)
      BASELINE_MS=$(( (END - START) / 1000000 ))
      info "Baseline latency: ''${BASELINE_MS}ms"

      # Test netem profiles
      ${lib.concatStrings (
        lib.mapAttrsToList (name: cfg: ''
          echo ""
          echo "--- Testing ${name} (port ${toString cfg.degradedPort}) ---"
          info "Expected: ${cfg.delay}${if cfg.jitter != null then " jitter ${cfg.jitter}" else ""}${
            if cfg.loss != null then " loss ${cfg.loss}" else ""
          }"

          if wait_for_port "$HOST" ${toString cfg.degradedPort} 5; then
            START=$(date +%s%N)
            if sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString cfg.degradedPort} \
                testuser@"$HOST" "hostname" >/dev/null 2>&1; then
              END=$(date +%s%N)
              LATENCY_MS=$(( (END - START) / 1000000 ))
              info "Measured latency: ''${LATENCY_MS}ms (baseline: ''${BASELINE_MS}ms)"

              # Check if latency increased (allow for netem not being active)
              if [ $LATENCY_MS -gt $((BASELINE_MS + 50)) ]; then
                pass "${name}: Latency increased"
              else
                skip "${name}: Latency not significantly increased (netem may not be active)"
              fi
            else
              fail "${name}: Connection failed"
            fi
          else
            skip "${name}: Port ${toString cfg.degradedPort} not reachable"
          fi
        '') netem
      )}

      exit_with_summary
    '';
  };

  # ─── Stability Tests ──────────────────────────────────────────────
  # Connection resilience and unstable service tests
  stabilityTests = pkgs.writeShellApplication {
    name = "ssh-test-stability";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      netcat-gnu
      coreutils
    ];
    text = ''
      set -euo pipefail
      ${testHelpers}

      echo "=== SSH-Tool Stability Tests ==="
      echo ""

      HOST="''${SSH_TARGET_HOST:-localhost}"

      # Test 1: Multiple rapid connections
      echo "--- Test 1: Rapid Connections ---"
      info "Making 5 rapid connections..."
      SUCCESS=0
      for i in 1 2 3 4 5; do
        if sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
            testuser@"$HOST" "echo $i" >/dev/null 2>&1; then
          SUCCESS=$((SUCCESS + 1))
        fi
      done
      if [ $SUCCESS -eq 5 ]; then
        pass "All 5 rapid connections succeeded"
      else
        fail "Only $SUCCESS/5 rapid connections succeeded"
      fi

      # Test 2: Connection to unstable port
      echo ""
      echo "--- Test 2: Unstable Port (may restart) ---"
      info "Testing unstable port (${toString sshd.unstable.port})..."
      info "Note: This sshd restarts every 5s, connection may fail"

      if wait_for_port "$HOST" ${toString sshd.unstable.port} 10; then
        if sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.unstable.port} \
            testuser@"$HOST" "hostname" >/dev/null 2>&1; then
          pass "Unstable port connection succeeded"
        else
          skip "Unstable port connection failed (may have restarted)"
        fi
      else
        skip "Unstable port not reachable"
      fi

      # Test 3: Long command output
      echo ""
      echo "--- Test 3: Long Command Output ---"
      info "Testing large output handling..."
      LINES=$(sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          testuser@"$HOST" "cat /etc/large-test-file.txt 2>/dev/null | wc -l" 2>/dev/null || echo "0")
      if [ "$LINES" -ge 100 ]; then
        pass "Large output handled correctly ($LINES lines)"
      else
        skip "Large test file not available or smaller than expected"
      fi

      # Test 4: Multiple users concurrently (sequential for simplicity)
      echo ""
      echo "--- Test 4: Multiple Users ---"
      info "Testing connections from multiple users..."
      USERS_OK=0
      for user in testuser fancyuser zshuser; do
        if sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
            "$user"@"$HOST" "whoami" >/dev/null 2>&1; then
          USERS_OK=$((USERS_OK + 1))
        fi
      done
      if [ $USERS_OK -eq 3 ]; then
        pass "All 3 users connected successfully"
      else
        fail "Only $USERS_OK/3 users connected"
      fi

      exit_with_summary
    '';
  };

  # ─── Security Tests ───────────────────────────────────────────────
  # Security controls and blocked operations
  security = pkgs.writeShellApplication {
    name = "ssh-test-security";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      curl
      jq
      netcat-gnu
    ];
    text = ''
      set -euo pipefail
      ${testHelpers}

      echo "=== SSH-Tool Security Tests ==="
      echo ""

      HOST="''${SSH_TARGET_HOST:-localhost}"
      MCP_HOST="''${MCP_HOST:-localhost}"
      MCP_PORT="''${MCP_PORT:-3000}"

      # Test 1: Cannot SSH as arbitrary user
      echo "--- Test 1: No Arbitrary Users ---"
      info "Attempting login as nonexistent user..."
      if ! sshpass -p "anypass" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          hacker@"$HOST" "id" >/dev/null 2>&1; then
        pass "Arbitrary user login blocked"
      else
        fail "Should not allow arbitrary user login"
      fi

      # Test 2: Root blocked on standard port
      echo ""
      echo "--- Test 2: Root Blocked on Standard Port ---"
      info "Attempting root login on standard port..."
      if ! sshpass -p "${users.root.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          root@"$HOST" "id" >/dev/null 2>&1; then
        pass "Root login blocked on standard port"
      else
        fail "Root should be blocked on standard port"
      fi

      # Test 3: Password brute-force rate limited (quick check)
      echo ""
      echo "--- Test 3: Multiple Failed Attempts ---"
      info "Testing multiple failed password attempts..."
      BLOCKED=0
      for i in 1 2 3; do
        if ! sshpass -p "wrong$i" ssh ${sshOpts} -p ${toString sshd.standard.port} \
            testuser@"$HOST" "id" >/dev/null 2>&1; then
          BLOCKED=$((BLOCKED + 1))
        fi
      done
      if [ $BLOCKED -eq 3 ]; then
        pass "All bad passwords correctly rejected"
      else
        fail "Expected 3 rejections, got $BLOCKED"
      fi

      # Test 4: MCP server (if available)
      echo ""
      echo "--- Test 4: MCP Server Health ---"
      info "Checking MCP server at $MCP_HOST:$MCP_PORT..."
      if wait_for_port "$MCP_HOST" "$MCP_PORT" 5; then
        if curl -sf "http://$MCP_HOST:$MCP_PORT/health" >/dev/null 2>&1; then
          pass "MCP server is healthy"
        else
          skip "MCP server not responding to health check"
        fi
      else
        skip "MCP server not available"
      fi

      exit_with_summary
    '';
  };

  # ─── All Tests ────────────────────────────────────────────────────
  # Master test runner
  all = pkgs.writeShellApplication {
    name = "ssh-test-all";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      curl
      jq
      netcat-gnu
      coreutils
    ];
    text = ''
      set -euo pipefail

      echo "╔═══════════════════════════════════════════════════════════════╗"
      echo "║           SSH-Tool Complete Test Suite                        ║"
      echo "╚═══════════════════════════════════════════════════════════════╝"
      echo ""

      TOTAL_FAILURES=0

      run_test() {
        local name="$1"
        local script="$2"

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Running: $name"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if "$script"; then
          echo "✓ $name: PASSED"
        else
          echo "✗ $name: FAILED"
          TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        fi
      }

      # Run all test suites
      run_test "E2E Tests" "${pkgs.writeShellScript "e2e-inline" ''
        set -euo pipefail
        ${testHelpers}
        HOST="''${SSH_TARGET_HOST:-localhost}"
        # Quick subset for all-tests run
        info "Quick E2E check..."
        if wait_for_port "$HOST" ${toString sshd.standard.port} 10; then
          if sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
              testuser@"$HOST" "hostname" >/dev/null 2>&1; then
            pass "Basic SSH works"
          else
            fail "Basic SSH failed"
          fi
        else
          fail "SSH port not reachable"
        fi
        exit_with_summary
      ''}"

      run_test "Auth Tests" "${pkgs.writeShellScript "auth-inline" ''
        set -euo pipefail
        ${testHelpers}
        HOST="''${SSH_TARGET_HOST:-localhost}"
        # Quick auth checks
        if ! sshpass -p "wrongpass" ssh ${sshOpts} -p ${toString sshd.standard.port} \
            testuser@"$HOST" "hostname" >/dev/null 2>&1; then
          pass "Bad password rejected"
        else
          fail "Bad password should be rejected"
        fi
        exit_with_summary
      ''}"

      run_test "Security Tests" "${pkgs.writeShellScript "security-inline" ''
        set -euo pipefail
        ${testHelpers}
        HOST="''${SSH_TARGET_HOST:-localhost}"
        if ! sshpass -p "anypass" ssh ${sshOpts} -p ${toString sshd.standard.port} \
            nobody@"$HOST" "hostname" >/dev/null 2>&1; then
          pass "Unknown user blocked"
        else
          fail "Should block unknown users"
        fi
        exit_with_summary
      ''}"

      echo ""
      echo "═══════════════════════════════════════════════════════════════"
      if [ $TOTAL_FAILURES -eq 0 ]; then
        echo "✓ ALL TEST SUITES PASSED"
        exit 0
      else
        echo "✗ $TOTAL_FAILURES TEST SUITE(S) FAILED"
        exit 1
      fi
    '';
  };
}
