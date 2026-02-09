#!/bin/bash
# test_ssh_connect.sh - Test SSH connection to real host

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

: "${SSH_HOST:=192.168.122.163}"
: "${SSH_USER:=das}"

expect << EXPECT_EOF
# Test SSH connection to real host

package require Expect

set project_root [pwd]
source [file join \$project_root "tests/mock/helpers/test_utils.tcl"]
source [file join \$project_root "lib/common/debug.tcl"]
source [file join \$project_root "lib/common/prompt.tcl"]
source [file join \$project_root "lib/connection/ssh.tcl"]

debug::init 3

test::init "SSH Connection (Real Host)"

set host "$SSH_HOST"
set user "$SSH_USER"
set password \$::env(PASSWORD)

# Test 1: Connect with password authentication
test::start "connection::ssh::connect establishes connection"
set result [connection::ssh::connect \$host \$user \$password 1]

if {\$result != 0} {
    test::pass "got spawn_id: \$result"
    set spawn_id \$result
} else {
    test::fail "connection failed"
    exit 1
}

# Test 2: Verify connection is alive
test::start "connection::ssh::is_connected returns true"
set connected [connection::ssh::is_connected \$spawn_id]
test::assert_true \$connected "connection should be alive"

# Test 3: Disconnect cleanly
test::start "connection::ssh::disconnect closes connection"
if {[catch {connection::ssh::disconnect \$spawn_id} err]} {
    test::fail "disconnect threw error: \$err"
} else {
    test::pass
}

# Test 4: Verify disconnected
test::start "connection after disconnect is not connected"
set connected [connection::ssh::is_connected \$spawn_id]
test::assert_false \$connected "connection should be closed"

exit [test::summary]
EXPECT_EOF
