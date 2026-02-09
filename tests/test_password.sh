#!/bin/bash
# test_password.sh - Test password module

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test script for password module

set project_root [pwd]
source [file join $project_root "tests/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/auth/password.tcl"]

# Initialize debug
debug::init 0

test::init "Password Module"

# Test 1: PASSWORD env var is used
test::start "auth::password::get reads PASSWORD env var"
set ::env(PASSWORD) "testpass123"
set result [auth::password::get]
test::assert_eq "testpass123" $result

# Test 2: Cached password is returned
test::start "auth::password::get returns cached value"
# Change env var, should still get cached value
set ::env(PASSWORD) "differentpass"
set result [auth::password::get]
test::assert_eq "testpass123" $result "cached value should be returned"

# Test 3: Clear password
test::start "auth::password::clear removes cached password"
auth::password::clear
# Now is_available should check env var
set available [auth::password::is_available]
test::assert_true $available "env var should still be available"

# Test 4: is_available returns true when env set
test::start "auth::password::is_available returns true with PASSWORD set"
auth::password::clear
set ::env(PASSWORD) "anotherpass"
set result [auth::password::is_available]
test::assert_true $result

# Test 5: is_available returns false when no password
test::start "auth::password::is_available returns false when no password"
auth::password::clear
unset ::env(PASSWORD)
set result [auth::password::is_available]
test::assert_false $result

# Test 6: Empty PASSWORD env var is not used
test::start "auth::password::get ignores empty PASSWORD env var"
auth::password::clear
set ::env(PASSWORD) ""
set result [auth::password::is_available]
test::assert_false $result "empty PASSWORD should not be available"

# Cleanup
catch {unset ::env(PASSWORD)}

# Print summary and exit with appropriate code
exit [test::summary]
EXPECT_EOF
