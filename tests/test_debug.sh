#!/bin/bash
# test_debug.sh - Test debug module

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test script for debug module

set project_root [pwd]
source [file join $project_root "tests/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]

test::init "Debug Module"

# Test 1: Initialize debug level
test::start "debug::init sets level correctly"
debug::init 3
test::assert_eq 3 [debug::get_level]

# Test 2: Set level at runtime
test::start "debug::set_level changes level"
debug::set_level 5
test::assert_eq 5 [debug::get_level]

# Test 3: Level clamping - too low
test::start "debug::set_level clamps negative values to 0"
debug::set_level -1
test::assert_eq 0 [debug::get_level]

# Test 4: Level clamping - too high
test::start "debug::set_level clamps values > 7 to 7"
debug::set_level 10
test::assert_eq 7 [debug::get_level]

# Test 5: Log procedure exists
test::start "debug::log procedure exists"
if {[info commands ::debug::log] ne ""} {
    test::pass
} else {
    test::fail "debug::log not found"
}

# Test 6: debug::log at level below threshold does not throw error
test::start "debug::log runs without error at valid level"
debug::set_level 3
if {[catch {debug::log 2 "test message"} err]} {
    test::fail "debug::log threw error: $err"
} else {
    test::pass
}

# Print summary and exit with appropriate code
exit [test::summary]
EXPECT_EOF
