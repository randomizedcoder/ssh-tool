#!/bin/bash
# test_edge_cases.sh - Test edge cases: output handling, special chars, etc.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test edge cases

package require Expect

set project_root [pwd]
source [file join $project_root "tests/mock/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/common/prompt.tcl"]

debug::init 0

test::init "Edge Cases"

# Test 1: Moderate output (100 lines)
test::start "prompt::run handles 100 lines of output"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid "seq 1 100"]
set lines [split [string trim $output] "\n"]
set count [llength $lines]

if {$count == 100} {
    test::pass "captured $count lines"
} else {
    test::fail "expected 100, got $count"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 2: Empty output
test::start "prompt::run handles empty output"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid "true"]
set trimmed [string trim $output]

if {$trimmed eq ""} {
    test::pass
} else {
    test::fail "expected empty, got '$trimmed'"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 3: Output with quotes
test::start "prompt::run handles quoted output"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid {echo "hello world"}]
set trimmed [string trim $output]

if {$trimmed eq "hello world"} {
    test::pass
} else {
    test::fail "got '$trimmed'"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 4: Tab characters
test::start "prompt::run handles tabs"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid {printf 'a\tb\n'}]
set trimmed [string trim $output]

if {[string match "*a*b*" $trimmed]} {
    test::pass
} else {
    test::fail "got '$trimmed'"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 5: Multi-line with blank lines
test::start "prompt::run handles blank lines in output"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid {printf 'line1\n\nline3\n'}]
set lines [split $output "\n"]

if {[llength $lines] >= 2} {
    test::pass "got [llength $lines] lines"
} else {
    test::fail "expected multiple lines"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 6: Numbers and math output
test::start "prompt::run captures numeric output"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid {echo $((2+2))}]
set trimmed [string trim $output]

if {$trimmed eq "4"} {
    test::pass
} else {
    test::fail "expected 4, got '$trimmed'"
}

catch {close -i $sid}
catch {wait -i $sid}

exit [test::summary]
EXPECT_EOF
