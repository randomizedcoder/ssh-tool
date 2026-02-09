#!/bin/bash
# test_sudo.sh - Test sudo password module

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test script for sudo password module

set project_root [pwd]
source [file join $project_root "tests/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/auth/sudo.tcl"]

# Initialize debug
debug::init 0

test::init "Sudo Password Module"

# Test 1: SUDO env var is used
test::start "auth::sudo::get reads SUDO env var"
set ::env(SUDO) "sudopass123"
set result [auth::sudo::get]
test::assert_eq "sudopass123" $result

# Test 2: Cached password is returned
test::start "auth::sudo::get returns cached value"
# Change env var, should still get cached value
set ::env(SUDO) "differentpass"
set result [auth::sudo::get]
test::assert_eq "sudopass123" $result "cached value should be returned"

# Test 3: Clear password
test::start "auth::sudo::clear removes cached password"
auth::sudo::clear
# Now is_available should check env var
set available [auth::sudo::is_available]
test::assert_true $available "env var should still be available"

# Test 4: is_available returns true when env set
test::start "auth::sudo::is_available returns true with SUDO set"
auth::sudo::clear
set ::env(SUDO) "anotherpass"
set result [auth::sudo::is_available]
test::assert_true $result

# Test 5: is_available returns false when no password
test::start "auth::sudo::is_available returns false when no password"
auth::sudo::clear
unset ::env(SUDO)
set result [auth::sudo::is_available]
test::assert_false $result

# Test 6: Empty SUDO env var is not used
test::start "auth::sudo::get ignores empty SUDO env var"
auth::sudo::clear
set ::env(SUDO) ""
set result [auth::sudo::is_available]
test::assert_false $result "empty SUDO should not be available"

# Cleanup
catch {unset ::env(SUDO)}

# Print summary and exit with appropriate code
exit [test::summary]
EXPECT_EOF
