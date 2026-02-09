#!/bin/bash
# test_sudo_exec.sh - Test sudo execution module

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test script for sudo execution module

package require Expect

set project_root [pwd]
source [file join $project_root "tests/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/common/prompt.tcl"]
source [file join $project_root "lib/commands/sudo_exec.tcl"]
source [file join $project_root "tests/helpers/mock_ssh.tcl"]

# Initialize debug and mock_ssh
debug::init 0
mock_ssh::init $project_root

test::init "Sudo Execution Module"

# Test 1: Sudo password prompt detection
test::start "commands::sudo detects sudo password prompt"
set mock_spawn_id [mock_ssh::spawn_session "normal"]

# Get past initial password prompt
set timeout 5
expect -i $mock_spawn_id \
    "password:" {
        send -i $mock_spawn_id "testpass123\r"
        exp_continue
    } \
    -re {[$#] } { } \
    timeout { }

# Now send sudo command
send -i $mock_spawn_id "sudo -i\r"

set sudo_prompted 0
expect -i $mock_spawn_id \
    -re {\[sudo\] password for [^:]+:} {
        set sudo_prompted 1
        send -i $mock_spawn_id "sudopass\r"
        exp_continue
    } \
    "password:" {
        set sudo_prompted 1
        send -i $mock_spawn_id "sudopass\r"
        exp_continue
    } \
    -re {[#] } { } \
    timeout { }

if {$sudo_prompted} {
    test::pass "sudo password prompt detected"
} else {
    test::fail "sudo password prompt not detected"
}

mock_ssh::close_session

# Test 2: Sudo failure detection
test::start "commands::sudo detects sudo failure"
set mock_spawn_id [mock_ssh::spawn_session "sudo_fail"]

# Get past initial password prompt
set timeout 5
expect -i $mock_spawn_id \
    "password:" {
        send -i $mock_spawn_id "testpass123\r"
        exp_continue
    } \
    -re {[$#] } { } \
    timeout { }

# Now send sudo command
send -i $mock_spawn_id "sudo -i\r"

set sudo_failed 0
expect -i $mock_spawn_id \
    -re {\[sudo\] password for [^:]+:} {
        send -i $mock_spawn_id "wrongpass\r"
        exp_continue
    } \
    -re {Sorry, try again} {
        exp_continue
    } \
    -re {incorrect password attempt} {
        set sudo_failed 1
    } \
    timeout { } \
    eof { }

if {$sudo_failed} {
    test::pass "sudo failure detected"
} else {
    test::fail "sudo failure not detected"
}

catch {mock_ssh::close_session}

# Test 3: exit_sudo function exists
test::start "commands::sudo::exit_sudo procedure exists"
if {[info commands ::commands::sudo::exit_sudo] ne ""} {
    test::pass
} else {
    test::fail "exit_sudo procedure not found"
}

# Print summary and exit with appropriate code
exit [test::summary]
EXPECT_EOF
