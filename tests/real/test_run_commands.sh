#!/bin/bash
# test_run_commands.sh - Test running commands on real host

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

: "${SSH_HOST:=192.168.122.163}"
: "${SSH_USER:=das}"

expect << EXPECT_EOF
# Test running commands on real host

package require Expect

set project_root [pwd]
source [file join \$project_root "tests/mock/helpers/test_utils.tcl"]
source [file join \$project_root "lib/common/debug.tcl"]
source [file join \$project_root "lib/common/prompt.tcl"]
source [file join \$project_root "lib/connection/ssh.tcl"]

debug::init 3

test::init "Run Commands (Real Host)"

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

# Test 1: Simple echo command
test::start "prompt::run captures echo output"
set output [prompt::run \$spawn_id "echo hello"]
set trimmed [string trim \$output]
if {\$trimmed eq "hello"} {
    test::pass
} else {
    test::fail "expected 'hello', got '\$trimmed'"
}

# Test 2: Multi-line output
test::start "prompt::run captures multi-line output"
set output [prompt::run \$spawn_id "echo -e 'line1\\nline2\\nline3'"]
set lines [split \$output "\\n"]
set count [llength \$lines]
if {\$count >= 3} {
    test::pass "captured \$count lines"
} else {
    test::fail "expected at least 3 lines, got \$count"
}

# Test 3: Command with special characters
test::start "prompt::run handles special characters"
set output [prompt::run \$spawn_id {echo 'test\$var'}]
set trimmed [string trim \$output]
# Shell should print test\$var literally (single quotes)
if {[string length \$trimmed] > 0} {
    test::pass "output: \$trimmed"
} else {
    test::fail "empty output"
}

# Test 4: pwd command
test::start "prompt::run returns working directory"
set output [prompt::run \$spawn_id "pwd"]
set trimmed [string trim \$output]
if {[string match "/*" \$trimmed]} {
    test::pass "pwd: \$trimmed"
} else {
    test::fail "expected path, got: \$trimmed"
}

# Test 5: Run uname to verify we're on the expected system
test::start "prompt::run gets system info"
set output [prompt::run \$spawn_id "uname -s"]
set trimmed [string trim \$output]
if {\$trimmed eq "Linux"} {
    test::pass "system: \$trimmed"
} else {
    test::fail "expected 'Linux', got '\$trimmed'"
}

# Test 6: Large output (test buffer handling)
test::start "prompt::run handles large output"
set output [prompt::run \$spawn_id "seq 1 100"]
set lines [split [string trim \$output] "\\n"]
set count [llength \$lines]
if {\$count == 100} {
    test::pass "captured \$count lines"
} else {
    test::fail "expected 100 lines, got \$count"
}

# Cleanup
connection::ssh::disconnect \$spawn_id

exit [test::summary]
EXPECT_EOF
