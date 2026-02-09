#!/bin/bash
# test_hostname.sh - Test hostname command on real host

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

: "${SSH_HOST:=192.168.122.163}"
: "${SSH_USER:=das}"

expect << EXPECT_EOF
# Test hostname command on real host

package require Expect

set project_root [pwd]
source [file join \$project_root "tests/mock/helpers/test_utils.tcl"]
source [file join \$project_root "lib/common/debug.tcl"]
source [file join \$project_root "lib/common/prompt.tcl"]
source [file join \$project_root "lib/connection/ssh.tcl"]
source [file join \$project_root "lib/commands/hostname.tcl"]

debug::init 3

test::init "Hostname Command (Real Host)"

set host "$SSH_HOST"
set user "$SSH_USER"
set password \$::env(PASSWORD)

# Connect and init prompt
set spawn_id [connection::ssh::connect \$host \$user \$password 1]
if {\$spawn_id == 0} {
    puts "ERROR: Failed to connect"
    exit 1
}
prompt::init \$spawn_id 0

# Test 1: Get hostname
test::start "commands::hostname::get returns hostname"
set result [commands::hostname::get \$spawn_id]
if {[string length \$result] > 0} {
    test::pass "hostname: \$result"
} else {
    test::fail "empty hostname"
}

# Test 2: Get FQDN
test::start "commands::hostname::get_fqdn returns FQDN"
set result [commands::hostname::get_fqdn \$spawn_id]
if {[string length \$result] > 0} {
    test::pass "fqdn: \$result"
} else {
    test::fail "empty FQDN"
}

# Cleanup
connection::ssh::disconnect \$spawn_id

exit [test::summary]
EXPECT_EOF
