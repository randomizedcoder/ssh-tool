#!/usr/bin/env tclsh
# exp_close_crash.tcl - Reproduces SIGILL crash in exp_close/exp_event_disarm_fg
#
# This test reproduces the crash found in MCP integration tests where
# closing a spawn channel causes SIGILL in libtcl9.0.so
#
# Run: expect exp_close_crash.tcl
#
# Expected: Test completes without SIGILL crash
# Current:  Crashes with "trap invalid opcode" in exp_event_disarm_fg

package require Expect

puts "Testing exp_close with Tcl [info patchlevel]"
puts "Expect version: [package require Expect]"
puts ""

# Test 1: Basic spawn and close
puts "Test 1: spawn echo and close..."
spawn echo "hello"
expect eof
close
wait
puts "PASS"

# Test 2: Spawn cat (interactive) and close before eof
puts "Test 2: spawn cat and close before eof..."
spawn cat
after 100
close
wait
puts "PASS"

# Test 3: Multiple spawn/close cycles (stress test)
puts "Test 3: 10 spawn/close cycles..."
for {set i 0} {$i < 10} {incr i} {
    spawn echo "cycle $i"
    expect eof
    close
    wait
}
puts "PASS"

# Test 4: Spawn with timeout expect then close
puts "Test 4: spawn sleep with timeout..."
spawn sleep 10
set timeout 1
expect {
    timeout { }
    eof { }
}
close
wait
puts "PASS"

# Test 5: Spawn ssh (most similar to MCP crash scenario)
puts "Test 5: spawn ssh to invalid host..."
if {[catch {exec which ssh}]} {
    puts "SKIP (ssh not available)"
} else {
    spawn ssh -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no invalid.host.local
    expect {
        -re "." { exp_continue }
        timeout { }
        eof { }
    }
    close
    wait
    puts "PASS"
}

puts ""
puts "All tests passed - no SIGILL crash"
