#!/bin/bash
# test_prompt.sh - Test prompt module

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test script for prompt module

package require Expect

set project_root [pwd]
source [file join $project_root "tests/mock/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/common/prompt.tcl"]

# Initialize debug at low level for tests
debug::init 0

test::init "Prompt Module"

# Test 1: Marker generation
test::start "prompt::marker returns unique marker"
set marker [prompt::marker 0]
if {[regexp {XPCT[0-9]+>} $marker]} {
    test::pass "marker contains PID"
} else {
    test::fail "marker format incorrect: $marker"
}

# Test 2: Root marker generation
test::start "prompt::marker with is_root=1 returns root marker"
set root_marker [prompt::marker 1]
if {[regexp {XPCT[0-9]+#} $root_marker]} {
    test::pass "root marker contains PID and #"
} else {
    test::fail "root marker format incorrect: $root_marker"
}

# Test 3: Markers are different
test::start "user and root markers are different"
if {$marker ne $root_marker} {
    test::pass
} else {
    test::fail "markers should be different"
}

# Test 4: Test prompt init with mock shell
test::start "prompt::init sets prompt on mock shell"
spawn bash --norc --noprofile
set sid $spawn_id

# Wait for initial prompt
expect -timeout 5 \
    -re {[$#] } { } \
    timeout { }

# Try to init prompt
set result [prompt::init $sid 0]
if {$result == 1} {
    test::pass
} else {
    test::fail "prompt::init returned $result"
}

# Cleanup
catch {close -i $sid}
catch {wait -i $sid}

# Test 5: Test prompt::run with mock shell
test::start "prompt::run captures command output"
spawn bash --norc --noprofile
set sid $spawn_id

# Wait for initial prompt
expect -timeout 5 \
    -re {[$#] } { } \
    timeout { }

# Init prompt
prompt::init $sid 0

# Run a simple command
set output [prompt::run $sid "echo hello"]
set trimmed [string trim $output]

if {$trimmed eq "hello"} {
    test::pass
} else {
    test::fail "expected 'hello', got '$trimmed'"
}

# Cleanup
catch {close -i $sid}
catch {wait -i $sid}

# Test 6: Test prompt::wait
test::start "prompt::wait detects prompt"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 \
    -re {[$#] } { } \
    timeout { }

prompt::init $sid 0

# Send an empty command and wait
send -i $sid "\r"
set result [prompt::wait $sid]

if {$result == 1} {
    test::pass
} else {
    test::fail "prompt::wait returned $result"
}

# Cleanup
catch {close -i $sid}
catch {wait -i $sid}

# Print summary and exit with appropriate code
exit [test::summary]
EXPECT_EOF
