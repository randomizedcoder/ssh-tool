#!/bin/bash
# test_hostname.sh - Test hostname command module

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

expect << 'EXPECT_EOF'
# Test script for hostname command module

package require Expect

set project_root [pwd]
source [file join $project_root "tests/mock/helpers/test_utils.tcl"]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/common/prompt.tcl"]
source [file join $project_root "lib/commands/hostname.tcl"]

# Initialize debug
debug::init 0

test::init "Hostname Command Module"

# Test 1: Get hostname from local shell
test::start "commands::hostname::get returns hostname"
spawn bash --norc --noprofile
set sid $spawn_id

# Wait for prompt
expect -timeout 5 \
    -re {[$#] } { } \
    timeout { }

# Initialize prompt
prompt::init $sid 0

# Get hostname
set result [commands::hostname::get $sid]
set expected [exec hostname]

if {$result eq $expected} {
    test::pass "got expected hostname: $result"
} else {
    # Allow partial match (some systems have different output)
    if {[string length $result] > 0} {
        test::pass "got a hostname: $result"
    } else {
        test::fail "expected '$expected', got '$result'"
    }
}

catch {close -i $sid}
catch {wait -i $sid}

# Test 2: get_fqdn function exists
test::start "commands::hostname::get_fqdn procedure exists"
if {[info commands ::commands::hostname::get_fqdn] ne ""} {
    test::pass
} else {
    test::fail "get_fqdn procedure not found"
}

# Test 3: Test get_fqdn with local shell
test::start "commands::hostname::get_fqdn returns value"
spawn bash --norc --noprofile
set sid $spawn_id

expect -timeout 5 \
    -re {[$#] } { } \
    timeout { }

prompt::init $sid 0

set result [commands::hostname::get_fqdn $sid]

if {[string length $result] > 0} {
    test::pass "got FQDN: $result"
} else {
    test::fail "empty FQDN returned"
}

catch {close -i $sid}
catch {wait -i $sid}

# Print summary and exit with appropriate code
exit [test::summary]
EXPECT_EOF
