#!/bin/bash
# test_mcp_e2e.sh - End-to-End MCP Server Tests
#
# These tests require a real SSH target. Set environment variables:
#   SSH_HOST - Target hostname or IP
#   SSH_USER - SSH username
#   PASSWORD - SSH password
#   INSECURE - Set to "true" for ephemeral VMs (skip host key check)
#
# Usage: ./test_mcp_e2e.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=mcp_client.sh
source "$SCRIPT_DIR/mcp_client.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
PASS=0
FAIL=0
SKIP=0

# Check prerequisites
check_prereqs() {
    if [ -z "$SSH_HOST" ]; then
        echo -e "${RED}ERROR: SSH_HOST not set${NC}"
        echo "Set environment variables: SSH_HOST, SSH_USER, PASSWORD"
        exit 1
    fi

    if [ -z "$SSH_USER" ]; then
        SSH_USER="$USER"
        echo -e "${YELLOW}Using current user: $SSH_USER${NC}"
    fi

    if [ -z "$PASSWORD" ]; then
        echo -e "${RED}ERROR: PASSWORD not set${NC}"
        echo "Set PASSWORD environment variable"
        exit 1
    fi

    # Check if server is running
    if ! mcp_health > /dev/null 2>&1; then
        echo -e "${YELLOW}Starting MCP server on port ${MCP_PORT}...${NC}"
        cd "$SCRIPT_DIR/../.."
        ./server.tcl --port "${MCP_PORT:-3000}" &
        MCP_PID=$!
        trap 'kill $MCP_PID 2>/dev/null' EXIT
        sleep 2

        if ! mcp_health > /dev/null 2>&1; then
            echo -e "${RED}ERROR: Failed to start MCP server${NC}"
            exit 1
        fi
    fi
}

# Test assertion helpers
assert_pass() {
    local name="$1"
    echo -e "${GREEN}PASS${NC}: $name"
    ((PASS++))
}

assert_fail() {
    local name="$1"
    local details="$2"
    echo -e "${RED}FAIL${NC}: $name"
    if [ -n "$details" ]; then
        echo "  Details: $details"
    fi
    ((FAIL++))
}

assert_skip() {
    local name="$1"
    local reason="$2"
    echo -e "${YELLOW}SKIP${NC}: $name ($reason)"
    ((SKIP++))
}

#===========================================================================
# E2E TEST CASES
#===========================================================================

test_health_endpoint() {
    local response
    response=$(mcp_health)

    if echo "$response" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
        assert_pass "Health endpoint returns OK"
    else
        assert_fail "Health endpoint returns OK" "$response"
    fi
}

test_metrics_endpoint() {
    local response
    response=$(mcp_metrics)

    if echo "$response" | grep -q "mcp_"; then
        assert_pass "Metrics endpoint returns Prometheus format"
    else
        assert_fail "Metrics endpoint returns Prometheus format" "$response"
    fi
}

test_initialize() {
    local response
    response=$(mcp_initialize "test-client" "1.0.0")

    if echo "$response" | grep -q '"protocolVersion"'; then
        assert_pass "Initialize returns protocol version"
    else
        assert_fail "Initialize returns protocol version" "$response"
    fi
}

test_tools_list() {
    local response
    response=$(mcp_tools_list)

    if echo "$response" | grep -q '"ssh_connect"'; then
        assert_pass "tools/list returns ssh_connect"
    else
        assert_fail "tools/list returns ssh_connect" "$response"
    fi
}

test_ssh_connect() {
    local insecure="${INSECURE:-false}"
    local response
    response=$(mcp_ssh_connect "$SSH_HOST" "$SSH_USER" "$PASSWORD" "$insecure")

    if has_error "$response"; then
        assert_fail "SSH connect to $SSH_HOST" "$response"
        return 1
    fi

    SSH_SESSION_ID=$(extract_session_id "$response")
    if [ -n "$SSH_SESSION_ID" ]; then
        assert_pass "SSH connect to $SSH_HOST (session: $SSH_SESSION_ID)"
        return 0
    else
        assert_fail "SSH connect returns session_id" "$response"
        return 1
    fi
}

test_ssh_hostname() {
    if [ -z "$SSH_SESSION_ID" ]; then
        assert_skip "SSH hostname" "No active session"
        return
    fi

    local response
    response=$(mcp_ssh_hostname "$SSH_SESSION_ID")

    if has_error "$response"; then
        assert_fail "SSH hostname command" "$response"
    else
        assert_pass "SSH hostname command"
    fi
}

test_ssh_run_ls() {
    if [ -z "$SSH_SESSION_ID" ]; then
        assert_skip "SSH run ls" "No active session"
        return
    fi

    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ls -la /tmp")

    if has_error "$response"; then
        assert_fail "SSH run ls -la /tmp" "$response"
    else
        assert_pass "SSH run ls -la /tmp"
    fi
}

test_ssh_run_cat() {
    if [ -z "$SSH_SESSION_ID" ]; then
        assert_skip "SSH run cat" "No active session"
        return
    fi

    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "cat /etc/hostname")

    if has_error "$response"; then
        assert_fail "SSH run cat /etc/hostname" "$response"
    else
        assert_pass "SSH run cat /etc/hostname"
    fi
}

test_ssh_cat_file() {
    if [ -z "$SSH_SESSION_ID" ]; then
        assert_skip "SSH cat file" "No active session"
        return
    fi

    local response
    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/etc/os-release")

    if has_error "$response"; then
        assert_fail "SSH cat file /etc/os-release" "$response"
    else
        assert_pass "SSH cat file /etc/os-release"
    fi
}

test_ssh_list_sessions() {
    local response
    response=$(mcp_ssh_list_sessions)

    if echo "$response" | grep -q '"count"'; then
        assert_pass "SSH list sessions returns count"
    else
        assert_fail "SSH list sessions returns count" "$response"
    fi
}

test_ssh_disconnect() {
    if [ -z "$SSH_SESSION_ID" ]; then
        assert_skip "SSH disconnect" "No active session"
        return
    fi

    local response
    response=$(mcp_ssh_disconnect "$SSH_SESSION_ID")

    if has_error "$response"; then
        assert_fail "SSH disconnect" "$response"
    else
        assert_pass "SSH disconnect"
        SSH_SESSION_ID=""
    fi
}

test_metrics_after_ops() {
    local response
    response=$(mcp_metrics)

    if echo "$response" | grep -q "mcp_ssh_sessions_total"; then
        assert_pass "Metrics track SSH sessions"
    else
        assert_fail "Metrics track SSH sessions" "$response"
    fi
}

#===========================================================================
# MAIN
#===========================================================================

echo "=============================================="
echo "MCP Server End-to-End Tests"
echo "=============================================="
echo ""

check_prereqs

echo "Target: $SSH_USER@$SSH_HOST"
echo "Server: http://${MCP_HOST}:${MCP_PORT}"
echo ""
echo "Running tests..."
echo "----------------------------------------------"

# Run tests in order
test_health_endpoint
test_metrics_endpoint
test_initialize
test_tools_list
test_ssh_connect
test_ssh_hostname
test_ssh_run_ls
test_ssh_run_cat
test_ssh_cat_file
test_ssh_list_sessions
test_ssh_disconnect
test_metrics_after_ops

echo "----------------------------------------------"
echo ""
echo "=============================================="
echo "Test Results"
echo "=============================================="
echo -e "Passed:  ${GREEN}$PASS${NC}"
echo -e "Failed:  ${RED}$FAIL${NC}"
echo -e "Skipped: ${YELLOW}$SKIP${NC}"
echo "=============================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
