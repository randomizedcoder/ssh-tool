# nix/lib/test-helpers.nix
#
# Shared shell script helpers for test scripts.
# Provides colors, pass/fail/skip functions, and utility functions.
#
{ lib }:
{
  # Shell script fragment with color codes and test helper functions
  # Include this at the top of test scripts
  shellHelpers = ''
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
  '';

  # Extended helpers for network tests (includes ssh_cmd helper)
  networkTestHelpers =
    constants:
    let
      users = constants.users;
      sshd = constants.sshd;
      sshOpts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10";
    in
    ''
      # Helper to run SSH command
      ssh_cmd() {
        sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString sshd.standard.port} \
          testuser@"$HOST" "$@" 2>/dev/null
      }
    '';

  # MCP health check script fragment
  mcpHealthCheck = mcpHost: ''
    echo "Checking MCP server health..."
    for i in $(seq 1 30); do
      if curl -sf "http://${mcpHost}:3000/health" >/dev/null 2>&1; then
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
}
