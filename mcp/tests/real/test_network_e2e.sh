#!/bin/bash
# test_network_e2e.sh - Network Commands E2E Tests
#
# Tests network tools through the MCP server with real SSH connections.
# Reference: DESIGN_NETWORK_COMMANDS.md
#
# Requires:
#   SSH_HOST - Target hostname or IP
#   PASSWORD - SSH password
#   SSH_USER - SSH username (optional, defaults to $USER)
#
# Usage: ./test_network_e2e.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=mcp_client.sh
source "$SCRIPT_DIR/mcp_client.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
SKIP=0

# Check prerequisites
check_prereqs() {
    if [ -z "$SSH_HOST" ] || [ -z "$PASSWORD" ]; then
        echo -e "${RED}ERROR: SSH_HOST and PASSWORD must be set${NC}"
        exit 1
    fi

    SSH_USER="${SSH_USER:-$USER}"

    # Check server
    if ! mcp_health > /dev/null 2>&1; then
        echo -e "${YELLOW}Starting MCP server...${NC}"
        cd "$SCRIPT_DIR/../.."
        ./server.tcl --port "${MCP_PORT:-3000}" &
        MCP_PID=$!
        trap 'kill $MCP_PID 2>/dev/null' EXIT
        sleep 2
    fi
}

# Setup SSH session
setup() {
    check_prereqs
    mcp_initialize "network-e2e-test" "1.0.0" > /dev/null

    local connect_response
    INSECURE="${INSECURE:-false}"
    connect_response=$(mcp_ssh_connect "$SSH_HOST" "$SSH_USER" "$PASSWORD" "$INSECURE")

    if has_error "$connect_response"; then
        echo -e "${RED}Failed to establish SSH session: $connect_response${NC}"
        exit 1
    fi

    SSH_SESSION_ID=$(extract_session_id "$connect_response")
    if [ -z "$SSH_SESSION_ID" ]; then
        echo -e "${RED}Failed to get SSH session ID${NC}"
        exit 1
    fi
    echo "SSH Session: $SSH_SESSION_ID"
}

# Cleanup
teardown() {
    if [ -n "$SSH_SESSION_ID" ]; then
        mcp_ssh_disconnect "$SSH_SESSION_ID" > /dev/null 2>&1 || true
    fi
}

trap teardown EXIT

#===========================================================================
# NETWORK INSPECTION TESTS (should pass)
#===========================================================================

test_ip_addr_show() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip -j addr show")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ip -j addr show"
        echo "  Error: $response"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ip -j addr show"
        ((PASS++))
    fi
}

test_ip_route_show() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip -j route show")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ip -j route show"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ip -j route show"
        ((PASS++))
    fi
}

test_ip_link_show() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip -j -d link show")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ip -j -d link show"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ip -j -d link show"
        ((PASS++))
    fi
}

test_tc_qdisc_show() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc -j qdisc show")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: tc -j qdisc show"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: tc -j qdisc show"
        ((PASS++))
    fi
}

test_ping_within_limit() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -c 2 localhost")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ping -c 2 localhost"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ping -c 2 localhost"
        ((PASS++))
    fi
}

test_ss_command() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ss -tlnp")

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: ss -tlnp"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: ss -tlnp"
        ((PASS++))
    fi
}

test_netstat_command() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "netstat -tlnp" 2>&1 || true)

    if [[ "$response" =~ "not found" ]]; then
        echo -e "${YELLOW}SKIP${NC}: netstat not installed"
        ((SKIP++))
    elif has_error "$response"; then
        echo -e "${RED}FAIL${NC}: netstat -tlnp"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: netstat -tlnp"
        ((PASS++))
    fi
}

#===========================================================================
# NETWORK MODIFICATION TESTS (should FAIL - security blocked)
#===========================================================================

test_ip_link_set_blocked() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip link set lo down")

    if has_error "$response"; then
        echo -e "${GREEN}PASS${NC}: ip link set BLOCKED"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: ip link set should be BLOCKED"
        ((FAIL++))
    fi
}

test_ip_addr_add_blocked() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ip addr add 10.0.0.1/24 dev lo")

    if has_error "$response"; then
        echo -e "${GREEN}PASS${NC}: ip addr add BLOCKED"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: ip addr add should be BLOCKED"
        ((FAIL++))
    fi
}

test_tc_qdisc_add_blocked() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "tc qdisc add dev lo root tbf rate 1mbit")

    if has_error "$response"; then
        echo -e "${GREEN}PASS${NC}: tc qdisc add BLOCKED"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: tc qdisc add should be BLOCKED"
        ((FAIL++))
    fi
}

test_ping_flood_blocked() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -f localhost")

    if has_error "$response"; then
        echo -e "${GREEN}PASS${NC}: ping -f (flood) BLOCKED"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: ping -f should be BLOCKED"
        ((FAIL++))
    fi
}

test_ping_excess_count_blocked() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ping -c 100 localhost")

    if has_error "$response"; then
        echo -e "${GREEN}PASS${NC}: ping -c 100 BLOCKED"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: ping -c 100 should be BLOCKED"
        ((FAIL++))
    fi
}

test_ethtool_flash_blocked() {
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ethtool --flash eth0 firmware.bin")

    if has_error "$response"; then
        echo -e "${GREEN}PASS${NC}: ethtool --flash BLOCKED"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: ethtool --flash should be BLOCKED"
        ((FAIL++))
    fi
}

#===========================================================================
# MAIN
#===========================================================================

echo ""
echo "=============================================="
echo "Network Commands E2E Tests"
echo "=============================================="
echo ""

setup

echo "--- Inspection Commands (should PASS) ---"
echo ""

test_ip_addr_show
test_ip_route_show
test_ip_link_show
test_tc_qdisc_show
test_ping_within_limit
test_ss_command
test_netstat_command

echo ""
echo "--- Modification Commands (should be BLOCKED) ---"
echo ""

test_ip_link_set_blocked
test_ip_addr_add_blocked
test_tc_qdisc_add_blocked
test_ping_flood_blocked
test_ping_excess_count_blocked
test_ethtool_flash_blocked

echo ""
echo "=============================================="
echo "Summary"
echo "=============================================="
echo ""
echo -e "Passed:  ${GREEN}$PASS${NC}"
echo -e "Failed:  ${RED}$FAIL${NC}"
echo -e "Skipped: ${YELLOW}$SKIP${NC}"
echo ""

if [ $FAIL -gt 0 ]; then
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

echo -e "${GREEN}SUCCESS${NC}"
exit 0
