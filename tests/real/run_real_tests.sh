#!/bin/bash
# run_real_tests.sh - Run tests against real SSH host
#
# Requires:
#   - SSH_HOST environment variable (or defaults to 192.168.122.163)
#   - SSH_USER environment variable (or defaults to das)
#   - PASSWORD environment variable (SSH password)
#   - SUDO environment variable (optional, for sudo tests)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR" || exit 1

# Default test host
: "${SSH_HOST:=192.168.122.163}"
: "${SSH_USER:=das}"

export SSH_HOST SSH_USER

# Check prerequisites
if [[ -z "$PASSWORD" ]]; then
    echo "ERROR: PASSWORD environment variable is required"
    echo "Usage: PASSWORD=<password> $0"
    exit 1
fi

# Check if host is reachable
if ! ping -c 1 -W 2 "$SSH_HOST" > /dev/null 2>&1; then
    echo "ERROR: Host $SSH_HOST is not reachable"
    exit 1
fi

TESTS=(
    "test_ssh_connect.sh"
    "test_prompt_init.sh"
    "test_run_commands.sh"
    "test_hostname.sh"
    "test_cat_file.sh"
)

PASS=0
FAIL=0
FAILED_TESTS=()

echo "========================================"
echo "SSH Automation Real Tests"
echo "========================================"
echo "Host: $SSH_HOST"
echo "User: $SSH_USER"
echo ""

for test in "${TESTS[@]}"; do
    echo "========================================"
    echo "Running $test..."
    echo "========================================"

    if ./"$test"; then
        echo ""
        echo "PASSED: $test"
        PASS=$((PASS + 1))
    else
        echo ""
        echo "FAILED: $test"
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$test")
    fi
    echo ""
done

echo "========================================"
echo "Final Results"
echo "========================================"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS + FAIL))"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
fi

echo "========================================"

exit $FAIL
