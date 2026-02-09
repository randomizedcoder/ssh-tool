#!/bin/bash
# test_prompt_init.sh - Test prompt initialization on real host

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

: "${SSH_HOST:=192.168.122.163}"
: "${SSH_USER:=das}"

expect << EXPECT_EOF
# Test prompt initialization on real host

package require Expect

set project_root [pwd]
source [file join \$project_root "tests/mock/helpers/test_utils.tcl"]
source [file join \$project_root "lib/common/debug.tcl"]
source [file join \$project_root "lib/common/prompt.tcl"]
source [file join \$project_root "lib/connection/ssh.tcl"]

debug::init 3

test::init "Prompt Initialization (Real Host)"

set host "$SSH_HOST"
set user "$SSH_USER"
set password \$::env(PASSWORD)

# Connect first
set spawn_id [connection::ssh::connect \$host \$user \$password 1]
if {\$spawn_id == 0} {
    puts "ERROR: Failed to connect"
    exit 1
}

# Test 1: Initialize prompt
test::start "prompt::init sets custom prompt"
set result [prompt::init \$spawn_id 0]
test::assert_true \$result "prompt::init should succeed"

# Test 2: Verify prompt marker is correct format
test::start "prompt marker contains correct PID"
set marker [prompt::marker 0]
set mypid \$::prompt::mypid
if {[string match "XPCT\${mypid}>" \$marker]} {
    test::pass "marker: \$marker"
} else {
    test::fail "unexpected marker: \$marker"
}

# Test 3: prompt::wait works
test::start "prompt::wait detects custom prompt"
send -i \$spawn_id "\\r"
set result [prompt::wait \$spawn_id]
test::assert_true \$result "should detect prompt"

# Cleanup
connection::ssh::disconnect \$spawn_id

exit [test::summary]
EXPECT_EOF
