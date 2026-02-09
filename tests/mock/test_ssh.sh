#!/bin/bash
# test_ssh.sh - Test SSH connection module

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test script for SSH connection module

package require Expect

set project_root [pwd]
source [file join $project_root "tests/mock/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/common/prompt.tcl"]
source [file join $project_root "lib/connection/ssh.tcl"]
source [file join $project_root "tests/mock/helpers/mock_ssh.tcl"]

# Initialize debug and mock_ssh
debug::init 0
mock_ssh::init $project_root

test::init "SSH Connection Module"

# Test 1: Connect with mock server (normal flow)
test::start "connection::ssh handles password prompt"
set mock_spawn_id [mock_ssh::spawn_session "normal"]

# Manually test the expect patterns
set timeout 5
set password_prompted 0
expect -i $mock_spawn_id \
    "password:" {
        set password_prompted 1
        send -i $mock_spawn_id "testpass123\r"
        exp_continue
    } \
    -re {[$#] } {
        # Got prompt
    } \
    timeout {
        # Timeout
    }

if {$password_prompted} {
    test::pass "password prompt detected"
} else {
    test::fail "password prompt not detected"
}

mock_ssh::close_session

# Test 2: Test disconnect function exists and works
test::start "connection::ssh::disconnect handles spawn_id"
spawn bash -c "echo test; sleep 1"
set sid $spawn_id
# Should not throw error
if {[catch {connection::ssh::disconnect $sid} err]} {
    test::fail "disconnect threw error: $err"
} else {
    test::pass
}

# Test 3: is_connected returns false for invalid spawn_id
test::start "connection::ssh::is_connected returns false for unknown spawn_id"
set result [connection::ssh::is_connected "invalid_spawn_id"]
test::assert_false $result

# Test 4: Test with auth_fail behavior
test::start "mock_ssh handles auth failure scenario"
set mock_spawn_id [mock_ssh::spawn_session "auth_fail"]

set auth_failed 0
set timeout 5
expect -i $mock_spawn_id \
    -re {Permission denied} {
        set auth_failed 1
    } \
    "password:" {
        send -i $mock_spawn_id "wrongpass\r"
        exp_continue
    } \
    timeout { } \
    eof { }

if {$auth_failed} {
    test::pass "auth failure detected"
} else {
    test::fail "auth failure not detected"
}

catch {mock_ssh::close_session}

# Test 5: Test with connection_refused behavior
test::start "mock_ssh handles connection refused scenario"
set mock_spawn_id [mock_ssh::spawn_session "connection_refused"]

set conn_refused 0
set timeout 5
expect -i $mock_spawn_id \
    -re {Connection refused} {
        set conn_refused 1
    } \
    timeout { } \
    eof { }

if {$conn_refused} {
    test::pass "connection refused detected"
} else {
    test::fail "connection refused not detected"
}

catch {mock_ssh::close_session}

# Print summary and exit with appropriate code
exit [test::summary]
EXPECT_EOF
