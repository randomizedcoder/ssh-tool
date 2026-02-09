#!/bin/bash
# test_escape_sequences.sh - Test escape sequence handling

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test escape sequence stripping and handling

package require Expect

set project_root [pwd]
source [file join $project_root "tests/mock/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/common/prompt.tcl"]

debug::init 0

test::init "Escape Sequence Handling"

# Test 1: strip_escapes removes OSC window title
test::start "strip_escapes removes OSC window title sequences"
set input "\033]0;window title\007actual text"
set result [prompt::strip_escapes $input]
if {$result eq "actual text"} {
    test::pass
} else {
    test::fail "expected 'actual text', got '$result'"
}

# Test 2: strip_escapes removes OSC 3008 systemd markers
test::start "strip_escapes removes OSC 3008 sequences"
set input "\033]3008;start=id;user=test\033\\output here"
set result [prompt::strip_escapes $input]
if {$result eq "output here"} {
    test::pass
} else {
    test::fail "expected 'output here', got '$result'"
}

# Test 3: strip_escapes removes ANSI color codes
test::start "strip_escapes removes ANSI color codes"
set input "\033\[32mgreen text\033\[0m normal"
set result [prompt::strip_escapes $input]
if {$result eq "green text normal"} {
    test::pass
} else {
    test::fail "expected 'green text normal', got '$result'"
}

# Test 4: strip_escapes removes bracket paste mode
test::start "strip_escapes removes bracket paste sequences"
set input "\033\[?2004htext here\033\[?2004l"
set result [prompt::strip_escapes $input]
if {$result eq "text here"} {
    test::pass
} else {
    test::fail "expected 'text here', got '$result'"
}

# Test 5: strip_escapes handles multiple sequences
test::start "strip_escapes handles multiple sequences in one string"
set input "\033]0;title\007\033\[32m\033]3008;x\033\\text\033\[0m"
set result [prompt::strip_escapes $input]
if {$result eq "text"} {
    test::pass
} else {
    test::fail "expected 'text', got '$result'"
}

# Test 6: strip_escapes preserves normal text
test::start "strip_escapes preserves text without escapes"
set input "normal text without escapes"
set result [prompt::strip_escapes $input]
if {$result eq $input} {
    test::pass
} else {
    test::fail "text was modified: '$result'"
}

# Test 7: Test with real bash - escape stripping in prompt::run
test::start "prompt::run strips ANSI escapes from bash output"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

# Run command that outputs ANSI codes
set output [prompt::run $sid {printf '\033[32mgreen\033[0m text\n'}]
set trimmed [string trim $output]

# After stripping, should just be "green text"
if {$trimmed eq "green text"} {
    test::pass
} else {
    test::fail "expected 'green text', got '$trimmed'"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 8: Strip escapes from multi-line output with colors
test::start "prompt::run strips escapes from multi-line colored output"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 -re {[$#] } { } timeout { }
prompt::init $sid 0

set output [prompt::run $sid {printf '\033[31mred\033[0m\n\033[32mgreen\033[0m\n'}]
set lines [split [string trim $output] "\n"]

if {[llength $lines] >= 2 && [lindex $lines 0] eq "red" && [lindex $lines 1] eq "green"} {
    test::pass
} else {
    test::fail "expected 'red' and 'green', got: $output"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 9: Bold and other SGR codes
test::start "strip_escapes removes bold and SGR codes"
set input "\033\[1mbold\033\[0m \033\[4munderline\033\[0m"
set result [prompt::strip_escapes $input]
if {$result eq "bold underline"} {
    test::pass
} else {
    test::fail "expected 'bold underline', got '$result'"
}

# Test 10: Cursor movement codes
test::start "strip_escapes removes cursor movement codes"
set input "\033\[2Aup\033\[2Bdown\033\[5Cright\033\[3Dleft"
set result [prompt::strip_escapes $input]
if {$result eq "updownrightleft"} {
    test::pass
} else {
    test::fail "expected 'updownrightleft', got '$result'"
}

exit [test::summary]
EXPECT_EOF
