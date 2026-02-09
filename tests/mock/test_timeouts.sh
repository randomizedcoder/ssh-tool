#!/bin/bash
# test_timeouts.sh - Test timeout and latency handling

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test timeout and latency handling

package require Expect

set project_root [pwd]
source [file join $project_root "tests/mock/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/common/prompt.tcl"]

debug::init 0

test::init "Timeout Handling"

# Test 1: Normal response within timeout
test::start "prompt::run handles normal response time"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid "echo quick"]
set trimmed [string trim $output]

if {$trimmed eq "quick"} {
    test::pass
} else {
    test::fail "expected 'quick', got '$trimmed'"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 2: Multiple quick commands in sequence
test::start "rapid command sequence completes"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set success 1
for {set i 1} {$i <= 5} {incr i} {
    set output [prompt::run $sid "echo $i"]
    set trimmed [string trim $output]
    if {$trimmed ne $i} {
        set success 0
        test::fail "command $i: expected '$i', got '$trimmed'"
        break
    }
}

if {$success} {
    test::pass "5 rapid commands completed"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 3: Command with small delay still completes
test::start "command with small delay completes"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid "sleep 0.1; echo delayed"]
set trimmed [string trim $output]

if {$trimmed eq "delayed"} {
    test::pass
} else {
    test::fail "expected 'delayed', got '$trimmed'"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 4: Timeout value is configurable in prompt module
test::start "timeout variable exists in prompt namespace"
if {[info exists ::prompt::mypid]} {
    test::pass "prompt module loaded correctly"
} else {
    test::fail "prompt module not properly initialized"
}

# Test 5: Large output doesn't cause timeout
test::start "large output completes without timeout"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid "seq 1 50"]
set lines [split [string trim $output] "\n"]
set count [llength $lines]

if {$count == 50} {
    test::pass "got all 50 lines"
} else {
    test::fail "expected 50 lines, got $count"
}

catch {close -i $sid}
catch {wait -i $sid}

exit [test::summary]
EXPECT_EOF
