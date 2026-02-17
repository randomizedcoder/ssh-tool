#!/bin/bash
# run_all_tests.sh - Master test runner
#
# Runs all component tests in sequence

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/mock" || exit 1

TESTS=(
    "test_debug.sh"
    "test_prompt.sh"
    "test_password.sh"
    "test_sudo.sh"
    "test_ssh.sh"
    "test_sudo_exec.sh"
    "test_hostname.sh"
    "test_cat_file.sh"
    "test_escape_sequences.sh"
    "test_timeouts.sh"
    "test_edge_cases.sh"
)

PASS=0
FAIL=0
FAILED_TESTS=()

echo "========================================"
echo "SSH Automation Mock Test Suite"
echo "========================================"
echo ""

for test in "${TESTS[@]}"; do
    echo "========================================"
    echo "Running $test..."
    echo "========================================"

    if ./"$test"; then
        echo ""
        echo "PASSED: $test"
        ((++PASS))
    else
        echo ""
        echo "FAILED: $test"
        ((++FAIL))
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
