#!/bin/bash
# run_shellcheck.sh - Run shellcheck on all shell scripts
#
# Runs shellcheck on all .sh files in the project and reports results

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
    echo "ERROR: shellcheck is not installed"
    echo "Install with: sudo dnf install shellcheck  # Fedora"
    echo "          or: sudo apt install shellcheck  # Debian/Ubuntu"
    exit 1
fi

echo "========================================"
echo "Running shellcheck on all shell scripts"
echo "========================================"
echo ""

# Find all .sh files
mapfile -t SCRIPTS < <(find . -name "*.sh" -type f | sort)

PASS=0
FAIL=0
FAILED_SCRIPTS=()

for script in "${SCRIPTS[@]}"; do
    echo -n "Checking $script ... "
    if shellcheck -x "$script" > /dev/null 2>&1; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        FAIL=$((FAIL + 1))
        FAILED_SCRIPTS+=("$script")
    fi
done

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failed scripts:"
    for script in "${FAILED_SCRIPTS[@]}"; do
        echo "  - $script"
        echo "    $(shellcheck -x "$script" 2>&1 | head -5)"
    done
    echo ""
    echo "Run 'shellcheck -x <script>' to see detailed errors"
fi

exit "$FAIL"
