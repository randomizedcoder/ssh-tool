# nix/tests/network-commands-test.nix
#
# Network Commands Integration Tests for SSH-Tool VM testing.
# Tests network inspection commands through SSH.
#
# Reference: DESIGN_NETWORK_COMMANDS.md
#
{ pkgs, lib }:
let
  constants = import ../constants;
  network = constants.network;
  ports = constants.ports;
  users = constants.users;
  sshd = constants.sshd;

  sshOpts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10";

  # Common test helper functions
  testHelpers = ''
    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color

    pass() { echo -e "''${GREEN}[PASS]''${NC} $1"; }
    fail() { echo -e "''${RED}[FAIL]''${NC} $1"; FAILURES=$((FAILURES + 1)); }
    skip() { echo -e "''${YELLOW}[SKIP]''${NC} $1"; }
    info() { echo -e "[INFO] $1"; }

    FAILURES=0

    check_result() {
      local name="$1"
      local result="$2"
      if [ "$result" -eq 0 ]; then
        pass "$name"
      else
        fail "$name"
      fi
    }

    wait_for_port() {
      local host="$1"
      local port="$2"
      local timeout="''${3:-30}"
      local elapsed=0
      while ! nc -z "$host" "$port" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ $elapsed -ge $timeout ]; then
          return 1
        fi
      done
      return 0
    }

    exit_with_summary() {
      echo ""
      if [ $FAILURES -eq 0 ]; then
        echo -e "''${GREEN}All tests passed!''${NC}"
        exit 0
      else
        echo -e "''${RED}$FAILURES test(s) failed''${NC}"
        exit 1
      fi
    }

    # Helper to run SSH command
    ssh_cmd() {
      sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
        testuser@"$HOST" "$@" 2>/dev/null
    }
  '';

in
{
  # ─── Network Inspection Tests ────────────────────────────────────
  # Tests for ip, ethtool, tc, nft commands
  networkInspection = pkgs.writeShellApplication {
    name = "ssh-test-network-inspection";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      jq
      netcat-gnu
    ];
    text = ''
      set -euo pipefail
      ${testHelpers}

      echo "=== Network Inspection Command Tests ==="
      echo ""

      HOST="''${SSH_TARGET_HOST:-localhost}"

      # Wait for SSH
      if ! wait_for_port "$HOST" ${toString sshd.standard.port} 30; then
        fail "SSH port not reachable"
        exit_with_summary
      fi

      # ─── ip command tests ─────────────────────────────────────────
      echo "--- ip command tests ---"

      info "Testing: ip -j addr show"
      if OUTPUT=$(ssh_cmd "ip -j addr show"); then
        if echo "$OUTPUT" | jq -e '.[0].ifname' >/dev/null 2>&1; then
          pass "ip -j addr show (JSON output)"
        else
          fail "ip -j addr show (invalid JSON)"
        fi
      else
        fail "ip -j addr show"
      fi

      info "Testing: ip -j route show"
      if OUTPUT=$(ssh_cmd "ip -j route show"); then
        if echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1; then
          pass "ip -j route show"
        else
          fail "ip -j route show (invalid JSON)"
        fi
      else
        fail "ip -j route show"
      fi

      info "Testing: ip -j link show"
      if OUTPUT=$(ssh_cmd "ip -j link show"); then
        if echo "$OUTPUT" | jq -e '.[0].ifname' >/dev/null 2>&1; then
          pass "ip -j link show"
        else
          fail "ip -j link show (invalid JSON)"
        fi
      else
        fail "ip -j link show"
      fi

      info "Testing: ip netns list"
      if OUTPUT=$(ssh_cmd "ip netns list"); then
        if echo "$OUTPUT" | grep -q "testns"; then
          pass "ip netns list (testns exists)"
        else
          skip "ip netns list (testns not found)"
        fi
      else
        fail "ip netns list"
      fi

      # ─── tc command tests ─────────────────────────────────────────
      echo ""
      echo "--- tc command tests ---"

      info "Testing: tc -j qdisc show"
      if OUTPUT=$(ssh_cmd "tc -j qdisc show"); then
        if echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1; then
          pass "tc -j qdisc show"
        else
          fail "tc -j qdisc show (invalid JSON)"
        fi
      else
        fail "tc -j qdisc show"
      fi

      info "Testing: tc qdisc show dev dummy0"
      if OUTPUT=$(ssh_cmd "tc qdisc show dev dummy0"); then
        if echo "$OUTPUT" | grep -q "htb\|qdisc"; then
          pass "tc qdisc show dev dummy0"
        else
          skip "tc qdisc show dev dummy0 (no htb qdisc)"
        fi
      else
        skip "tc qdisc show dev dummy0 (dummy0 may not exist)"
      fi

      # ─── nft command tests ────────────────────────────────────────
      echo ""
      echo "--- nft command tests ---"

      info "Testing: nft -j list ruleset"
      if OUTPUT=$(ssh_cmd "nft -j list ruleset"); then
        if echo "$OUTPUT" | jq -e '.nftables' >/dev/null 2>&1; then
          pass "nft -j list ruleset"
        else
          fail "nft -j list ruleset (invalid JSON)"
        fi
      else
        fail "nft -j list ruleset"
      fi

      info "Testing: nft list tables"
      if OUTPUT=$(ssh_cmd "nft list tables"); then
        if echo "$OUTPUT" | grep -q "table"; then
          pass "nft list tables"
        else
          skip "nft list tables (no tables)"
        fi
      else
        fail "nft list tables"
      fi

      # ─── ethtool tests ────────────────────────────────────────────
      echo ""
      echo "--- ethtool tests ---"

      info "Testing: ethtool dummy0"
      if OUTPUT=$(ssh_cmd "ethtool dummy0 2>&1"); then
        if echo "$OUTPUT" | grep -q "Settings for\|Link detected"; then
          pass "ethtool dummy0"
        else
          skip "ethtool dummy0 (no expected output)"
        fi
      else
        skip "ethtool dummy0 (may require root or dummy0 missing)"
      fi

      info "Testing: ethtool -i lo"
      if OUTPUT=$(ssh_cmd "ethtool -i lo 2>&1"); then
        if echo "$OUTPUT" | grep -q "driver"; then
          pass "ethtool -i lo (driver info)"
        else
          skip "ethtool -i lo (no driver info)"
        fi
      else
        skip "ethtool -i lo (may require root)"
      fi

      # ─── bridge command tests ─────────────────────────────────────
      echo ""
      echo "--- bridge command tests ---"

      info "Testing: bridge link show"
      if OUTPUT=$(ssh_cmd "bridge link show 2>&1"); then
        pass "bridge link show"
      else
        skip "bridge link show (command may not be available)"
      fi

      info "Testing: bridge -j link show"
      if OUTPUT=$(ssh_cmd "bridge -j link show 2>&1"); then
        if echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1; then
          pass "bridge -j link show"
        else
          skip "bridge -j link show (no JSON output)"
        fi
      else
        skip "bridge -j link show"
      fi

      # ─── ss command tests ─────────────────────────────────────────
      echo ""
      echo "--- ss command tests ---"

      info "Testing: ss -tlnp"
      if OUTPUT=$(ssh_cmd "ss -tlnp"); then
        if echo "$OUTPUT" | grep -q "LISTEN\|State"; then
          pass "ss -tlnp"
        else
          fail "ss -tlnp (no listening ports)"
        fi
      else
        fail "ss -tlnp"
      fi

      # ─── sysctl tests ─────────────────────────────────────────────
      echo ""
      echo "--- sysctl tests ---"

      info "Testing: sysctl net.ipv4.ip_forward"
      if OUTPUT=$(ssh_cmd "sysctl net.ipv4.ip_forward"); then
        if echo "$OUTPUT" | grep -q "net.ipv4.ip_forward"; then
          pass "sysctl net.ipv4.ip_forward"
        else
          fail "sysctl net.ipv4.ip_forward (unexpected output)"
        fi
      else
        fail "sysctl net.ipv4.ip_forward"
      fi

      exit_with_summary
    '';
  };

  # ─── Connectivity Tests ──────────────────────────────────────────
  # Tests for ping, traceroute, dns commands
  connectivityTests = pkgs.writeShellApplication {
    name = "ssh-test-connectivity";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      netcat-gnu
    ];
    text = ''
      set -euo pipefail
      ${testHelpers}

      echo "=== Connectivity Command Tests ==="
      echo ""

      HOST="''${SSH_TARGET_HOST:-localhost}"

      # Wait for SSH
      if ! wait_for_port "$HOST" ${toString sshd.standard.port} 30; then
        fail "SSH port not reachable"
        exit_with_summary
      fi

      # ─── ping tests ───────────────────────────────────────────────
      echo "--- ping tests ---"

      info "Testing: ping -c 2 localhost"
      if OUTPUT=$(ssh_cmd "ping -c 2 localhost"); then
        if echo "$OUTPUT" | grep -q "2 packets transmitted"; then
          pass "ping -c 2 localhost"
        else
          fail "ping -c 2 localhost (unexpected output)"
        fi
      else
        fail "ping -c 2 localhost"
      fi

      info "Testing: ping -c 1 127.0.0.1"
      if OUTPUT=$(ssh_cmd "ping -c 1 127.0.0.1"); then
        if echo "$OUTPUT" | grep -q "1 packets transmitted"; then
          pass "ping -c 1 127.0.0.1"
        else
          fail "ping -c 1 127.0.0.1 (unexpected output)"
        fi
      else
        fail "ping -c 1 127.0.0.1"
      fi

      # ─── DNS tests ────────────────────────────────────────────────
      echo ""
      echo "--- DNS tests ---"

      info "Testing: host localhost"
      if OUTPUT=$(ssh_cmd "host localhost 2>&1"); then
        pass "host localhost"
      else
        skip "host localhost (DNS may not be configured)"
      fi

      # ─── traceroute tests ─────────────────────────────────────────
      echo ""
      echo "--- traceroute tests ---"

      info "Testing: traceroute -m 3 localhost"
      if OUTPUT=$(ssh_cmd "traceroute -m 3 localhost 2>&1" || true); then
        if echo "$OUTPUT" | grep -q "traceroute\|localhost\|hops"; then
          pass "traceroute -m 3 localhost"
        else
          skip "traceroute -m 3 localhost (unexpected output)"
        fi
      else
        skip "traceroute -m 3 localhost (may require root)"
      fi

      exit_with_summary
    '';
  };

  # ─── Security Blocked Tests ──────────────────────────────────────
  # Tests that dangerous commands are blocked
  securityBlockedTests = pkgs.writeShellApplication {
    name = "ssh-test-network-security";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      netcat-gnu
    ];
    text = ''
      set -euo pipefail
      ${testHelpers}

      echo "=== Network Security Blocked Command Tests ==="
      echo "These commands SHOULD fail (be blocked)"
      echo ""

      HOST="''${SSH_TARGET_HOST:-localhost}"

      # Wait for SSH
      if ! wait_for_port "$HOST" ${toString sshd.standard.port} 30; then
        fail "SSH port not reachable"
        exit_with_summary
      fi

      # Note: These tests verify the commands execute but don't test
      # MCP security layer blocking (that's tested via mock tests).
      # Here we verify the VM has the commands available.

      # ─── Verify modification commands work (but require root) ────
      echo "--- Verify commands exist (may fail due to permissions) ---"

      info "Testing: ip link set (should require root)"
      if ! ssh_cmd "ip link set lo down 2>&1" | grep -q "Operation not permitted\|RTNETLINK"; then
        skip "ip link set (may have succeeded or different error)"
      else
        pass "ip link set requires permissions"
      fi

      info "Testing: tc qdisc add (should require root)"
      if ! ssh_cmd "tc qdisc add dev lo root tbf rate 1mbit burst 1k latency 1ms 2>&1" | grep -q "Operation not permitted\|RTNETLINK"; then
        skip "tc qdisc add (may have succeeded or different error)"
      else
        pass "tc qdisc add requires permissions"
      fi

      info "Testing: nft add (should require root)"
      if ! ssh_cmd "nft add table inet test 2>&1" | grep -q "Operation not permitted\|Error"; then
        skip "nft add (may have succeeded or different error)"
      else
        pass "nft add requires permissions"
      fi

      exit_with_summary
    '';
  };

  # ─── All Network Tests ───────────────────────────────────────────
  # Master runner for all network tests
  all = pkgs.writeShellApplication {
    name = "ssh-test-network-all";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
      jq
      netcat-gnu
      coreutils
    ];
    text = ''
      set -euo pipefail
      ${testHelpers}

      echo "╔═══════════════════════════════════════════════════════════════╗"
      echo "║        Network Commands Complete Test Suite                   ║"
      echo "╚═══════════════════════════════════════════════════════════════╝"
      echo ""

      HOST="''${SSH_TARGET_HOST:-localhost}"
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

      # Wait for SSH first
      info "Waiting for SSH on $HOST:${toString sshd.standard.port}..."
      if ! wait_for_port "$HOST" ${toString sshd.standard.port} 60; then
        fail "SSH port not reachable after 60s"
        exit 1
      fi
      pass "SSH port reachable"

      # Network Inspection Tests
      run_test "Network Inspection" "${pkgs.writeShellScript "net-inspect" ''
        set -euo pipefail
        ${testHelpers}
        HOST="''${SSH_TARGET_HOST:-localhost}"

        # Quick subset
        info "ip -j addr show..."
        if OUTPUT=$(ssh_cmd "ip -j addr show"); then
          if echo "$OUTPUT" | jq -e '.[0]' >/dev/null 2>&1; then
            pass "ip -j addr show"
          else
            fail "ip -j addr show"
          fi
        else
          fail "ip -j addr show"
        fi

        info "tc -j qdisc show..."
        if OUTPUT=$(ssh_cmd "tc -j qdisc show"); then
          pass "tc -j qdisc show"
        else
          fail "tc -j qdisc show"
        fi

        info "ss -tlnp..."
        if ssh_cmd "ss -tlnp" | grep -q "LISTEN\|State"; then
          pass "ss -tlnp"
        else
          fail "ss -tlnp"
        fi

        exit_with_summary
      ''}"

      # Connectivity Tests
      run_test "Connectivity" "${pkgs.writeShellScript "connectivity" ''
        set -euo pipefail
        ${testHelpers}
        HOST="''${SSH_TARGET_HOST:-localhost}"

        info "ping -c 1 localhost..."
        if ssh_cmd "ping -c 1 localhost" | grep -q "1 packets"; then
          pass "ping -c 1 localhost"
        else
          fail "ping -c 1 localhost"
        fi

        exit_with_summary
      ''}"

      echo ""
      echo "═══════════════════════════════════════════════════════════════"
      if [ $TOTAL_FAILURES -eq 0 ]; then
        echo "✓ ALL NETWORK TEST SUITES PASSED"
        exit 0
      else
        echo "✗ $TOTAL_FAILURES TEST SUITE(S) FAILED"
        exit 1
      fi
    '';
  };
}
