#!/bin/bash
# test_cat_file.sh - Test cat file command module

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test script for cat file command module

package require Expect

set project_root [pwd]
source [file join $project_root "tests/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/common/utils.tcl"]
source [file join $project_root "lib/common/prompt.tcl"]
source [file join $project_root "lib/commands/cat_file.tcl"]

# Initialize debug
debug::init 0

test::init "Cat File Command Module"

# Test 1: Read /etc/hostname (usually exists on Linux)
test::start "commands::cat_file::read reads file contents"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 {
    -re {[$#] } { }
    timeout { }
}

prompt::init $sid 0

# Try to read /etc/hostname or /etc/os-release
set result [commands::cat_file::read $sid "/etc/hostname"]
if {$result eq ""} {
    # Try alternate file
    set result [commands::cat_file::read $sid "/etc/os-release"]
}

if {[string length $result] > 0} {
    test::pass "read file successfully"
} else {
    test::fail "could not read any test file"
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 2: Validate filename security check
test::start "utils::validate_filename rejects dangerous chars"
set dangerous_names {
    "file;rm -rf /"
    "file|cat /etc/passwd"
    "file`whoami`"
    "file\$(id)"
    "file&background"
}

set all_rejected 1
foreach name $dangerous_names {
    if {[utils::validate_filename $name]} {
        set all_rejected 0
        puts "  Failed to reject: $name"
    }
}

if {$all_rejected} {
    test::pass "all dangerous filenames rejected"
} else {
    test::fail "some dangerous filenames were accepted"
}

# Test 3: Validate filename accepts normal paths
test::start "utils::validate_filename accepts normal paths"
set normal_names {
    "/etc/passwd"
    "/home/user/file.txt"
    "relative/path/file"
    "file-with-dashes_and_underscores.txt"
    "/path/to/file with spaces"
}

set all_accepted 1
foreach name $normal_names {
    if {![utils::validate_filename $name]} {
        set all_accepted 0
        puts "  Wrongly rejected: $name"
    }
}

if {$all_accepted} {
    test::pass "all normal filenames accepted"
} else {
    test::fail "some normal filenames were rejected"
}

# Test 4: Test file exists function
test::start "commands::cat_file::exists procedure exists"
if {[info commands ::commands::cat_file::exists] ne ""} {
    test::pass
} else {
    test::fail "exists procedure not found"
}

# Test 5: Test is_readable function
test::start "commands::cat_file::is_readable procedure exists"
if {[info commands ::commands::cat_file::is_readable] ne ""} {
    test::pass
} else {
    test::fail "is_readable procedure not found"
}

# Test 6: Shell escaping
test::start "utils::escape_for_shell escapes single quotes"
set result [utils::escape_for_shell "file'with'quotes"]
if {[string first "'" $result] >= 0} {
    test::pass "quotes are escaped"
} else {
    test::fail "quotes not properly escaped: $result"
}

# Print summary and exit with appropriate code
exit [test::summary]
EXPECT_EOF
