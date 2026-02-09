#!/bin/bash
# test_cat_file.sh - Test cat file command on real host

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

: "${SSH_HOST:=192.168.122.163}"
: "${SSH_USER:=das}"

expect << EXPECT_EOF
# Test cat file command on real host

package require Expect

set project_root [pwd]
source [file join \$project_root "tests/mock/helpers/test_utils.tcl"]
source [file join \$project_root "lib/common/debug.tcl"]
source [file join \$project_root "lib/common/utils.tcl"]
source [file join \$project_root "lib/common/prompt.tcl"]
source [file join \$project_root "lib/connection/ssh.tcl"]
source [file join \$project_root "lib/commands/cat_file.tcl"]

debug::init 3

test::init "Cat File Command (Real Host)"

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

# Test 1: Read /etc/hostname
test::start "commands::cat_file::read reads /etc/hostname"
set result [commands::cat_file::read \$spawn_id "/etc/hostname"]
if {[string length \$result] > 0} {
    test::pass "content: [string trim \$result]"
} else {
    test::fail "empty content"
}

# Test 2: Read /etc/os-release
test::start "commands::cat_file::read reads /etc/os-release"
set result [commands::cat_file::read \$spawn_id "/etc/os-release"]
if {[string match "*Fedora*" \$result] || [string match "*Linux*" \$result]} {
    test::pass "found OS info"
} else {
    if {[string length \$result] > 0} {
        test::pass "got content (non-Fedora)"
    } else {
        test::fail "empty content"
    }
}

# Test 3: File exists check
test::start "commands::cat_file::exists returns true for /etc/passwd"
set result [commands::cat_file::exists \$spawn_id "/etc/passwd"]
test::assert_true \$result "/etc/passwd should exist"

# Test 4: File exists returns false for non-existent
test::start "commands::cat_file::exists returns false for non-existent"
set result [commands::cat_file::exists \$spawn_id "/nonexistent/file/path"]
test::assert_false \$result "non-existent file should return false"

# Test 5: is_readable check
test::start "commands::cat_file::is_readable works for /etc/hostname"
set result [commands::cat_file::is_readable \$spawn_id "/etc/hostname"]
test::assert_true \$result "/etc/hostname should be readable"

# Test 6: Read non-existent file returns empty
test::start "commands::cat_file::read returns empty for non-existent"
set result [commands::cat_file::read \$spawn_id "/nonexistent/file"]
if {\$result eq ""} {
    test::pass
} else {
    test::fail "expected empty, got: \$result"
}

# Cleanup
connection::ssh::disconnect \$spawn_id

exit [test::summary]
EXPECT_EOF
