#!/bin/bash
# run_all_tests.sh - Run all MCP server tests
#
# Usage:
#   ./run_all_tests.sh           # Run mock tests only
#   ./run_all_tests.sh --all     # Run mock + real tests (requires SSH target)
#
# For real tests, set: SSH_HOST, SSH_USER, PASSWORD

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TCLSH="${TCLSH:-tclsh}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

RUN_REAL=0
MOCK_PASS=0
MOCK_FAIL=0
REAL_PASS=0
REAL_FAIL=0

# Parse args
for arg in "$@"; do
    case $arg in
        --all|-a)
            RUN_REAL=1
            ;;
        --help|-h)
            echo "Usage: $0 [--all]"
            echo ""
            echo "Options:"
            echo "  --all, -a    Run integration tests (requires SSH_HOST, PASSWORD)"
            echo ""
            echo "Environment variables for integration tests:"
            echo "  SSH_HOST     Target hostname or IP"
            echo "  SSH_USER     SSH username (default: \$USER)"
            echo "  PASSWORD     SSH password"
            echo "  INSECURE     Set to 'true' for ephemeral VMs"
            exit 0
            ;;
    esac
done

echo -e "${CYAN}=============================================="
echo "MCP Server Test Suite"
echo -e "==============================================${NC}"
echo ""

#===========================================================================
# Mock Tests (Unit/Integration without SSH)
#===========================================================================

echo -e "${CYAN}--- Mock Tests ---${NC}"
echo ""

cd "$SCRIPT_DIR/mock"

for testfile in test_*.test; do
    if [ -f "$testfile" ]; then
        echo -n "Running $testfile... "
        result=$($TCLSH "$testfile" 2>&1)
        last_line=$(echo "$result" | grep "^${testfile}:" | tail -1)

        # Parse result line: "test_foo.test:\tTotal\t27\tPassed\t27\tSkipped\t0\tFailed\t0"
        # Fields are tab-separated: 1=name 2=Total 3=total_count 4=Passed 5=passed_count ...
        total=$(echo "$last_line" | awk -F'\t' '{print $3}')
        passed=$(echo "$last_line" | awk -F'\t' '{print $5}')
        failed=$(echo "$last_line" | awk -F'\t' '{print $9}')

        if [ "$failed" == "0" ]; then
            echo -e "${GREEN}$passed/$total passed${NC}"
            MOCK_PASS=$((MOCK_PASS + passed))
        else
            echo -e "${RED}$passed/$total passed, $failed failed${NC}"
            MOCK_PASS=$((MOCK_PASS + passed))
            MOCK_FAIL=$((MOCK_FAIL + failed))
        fi
    fi
done

echo ""
echo -e "Mock Test Total: ${GREEN}$MOCK_PASS passed${NC}"
if [ $MOCK_FAIL -gt 0 ]; then
    echo -e "                 ${RED}$MOCK_FAIL failed${NC}"
fi

#===========================================================================
# Real Tests (Integration with SSH target)
#===========================================================================

if [ $RUN_REAL -eq 1 ]; then
    echo ""
    echo -e "${CYAN}--- Integration Tests ---${NC}"
    echo ""

    if [ -z "$SSH_HOST" ] || [ -z "$PASSWORD" ]; then
        echo -e "${YELLOW}Skipping integration tests (SSH_HOST and PASSWORD not set)${NC}"
    else
        cd "$SCRIPT_DIR/real"

        echo "Running test_mcp_e2e.sh..."
        if ./test_mcp_e2e.sh; then
            REAL_PASS=$((REAL_PASS + 1))
            echo -e "${GREEN}E2E tests passed${NC}"
        else
            REAL_FAIL=$((REAL_FAIL + 1))
            echo -e "${RED}E2E tests failed${NC}"
        fi

        echo ""
        echo "Running test_security_e2e.sh..."
        if ./test_security_e2e.sh; then
            REAL_PASS=$((REAL_PASS + 1))
            echo -e "${GREEN}Security tests passed${NC}"
        else
            REAL_FAIL=$((REAL_FAIL + 1))
            echo -e "${RED}Security tests failed${NC}"
        fi
    fi
fi

#===========================================================================
# Summary
#===========================================================================

echo ""
echo -e "${CYAN}=============================================="
echo "Test Summary"
echo -e "==============================================${NC}"
echo ""
echo "Mock Tests:"
echo -e "  Passed: ${GREEN}$MOCK_PASS${NC}"
if [ $MOCK_FAIL -gt 0 ]; then
    echo -e "  Failed: ${RED}$MOCK_FAIL${NC}"
fi

if [ $RUN_REAL -eq 1 ]; then
    echo ""
    echo "Integration Tests:"
    if [ $REAL_PASS -gt 0 ] || [ $REAL_FAIL -gt 0 ]; then
        echo -e "  Passed: ${GREEN}$REAL_PASS${NC}"
        if [ $REAL_FAIL -gt 0 ]; then
            echo -e "  Failed: ${RED}$REAL_FAIL${NC}"
        fi
    else
        echo -e "  ${YELLOW}Skipped${NC}"
    fi
fi

echo ""
TOTAL_FAIL=$((MOCK_FAIL + REAL_FAIL))
if [ $TOTAL_FAIL -gt 0 ]; then
    echo -e "${RED}FAILED: $TOTAL_FAIL tests failed${NC}"
    exit 1
else
    echo -e "${GREEN}SUCCESS: All tests passed${NC}"
    exit 0
fi
