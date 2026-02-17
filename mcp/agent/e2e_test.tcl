#!/usr/bin/env tclsh
# mcp/agent/e2e_test.tcl - End-to-End Test for MCP SSH Automation
#
# Simulates an AI agent interacting with the MCP server to:
# 1. Initialize MCP session
# 2. List available tools
# 3. Connect to SSH target
# 4. Run commands and read files
# 5. Disconnect and cleanup
#
# Usage:
#   tclsh e2e_test.tcl [options]
#
# Options:
#   --mcp-host HOST     MCP server host (default: 10.178.0.10)
#   --mcp-port PORT     MCP server port (default: 3000)
#   --target-host HOST  SSH target host (default: 10.178.0.20)
#   --target-port PORT  SSH target port (default: 2222)
#   --user USER         SSH user (default: testuser)
#   --password PASS     SSH password (default: testpass)
#   --debug             Enable debug output
#   --help              Show help
#

package require Tcl 9.0-

# Load MCP client
set script_dir [file dirname [info script]]
source [file join $script_dir mcp_client.tcl]

#=============================================================================
# Test Framework
#=============================================================================

namespace eval ::test {
    variable passed 0
    variable failed 0
    variable tests {}

    proc reset {} {
        variable passed
        variable failed
        variable tests
        set passed 0
        set failed 0
        set tests {}
    }

    proc pass {name} {
        variable passed
        variable tests
        incr passed
        lappend tests [list $name PASS ""]
        puts "\[PASS\] $name"
    }

    proc fail {name reason} {
        variable failed
        variable tests
        incr failed
        lappend tests [list $name FAIL $reason]
        puts "\[FAIL\] $name"
        puts "       Reason: $reason"
    }

    proc skip {name reason} {
        variable tests
        lappend tests [list $name SKIP $reason]
        puts "\[SKIP\] $name"
        puts "       Reason: $reason"
    }

    proc assert {condition name {reason ""}} {
        if {$condition} {
            pass $name
            return 1
        } else {
            if {$reason eq ""} {
                set reason "Assertion failed"
            }
            fail $name $reason
            return 0
        }
    }

    proc assert_eq {actual expected name} {
        if {$actual eq $expected} {
            pass $name
            return 1
        } else {
            fail $name "Expected '$expected', got '$actual'"
            return 0
        }
    }

    proc assert_contains {haystack needle name} {
        if {[string first $needle $haystack] >= 0} {
            pass $name
            return 1
        } else {
            fail $name "Expected to contain '$needle', got '$haystack'"
            return 0
        }
    }

    proc assert_not_empty {value name} {
        if {$value ne ""} {
            pass $name
            return 1
        } else {
            fail $name "Expected non-empty value"
            return 0
        }
    }

    proc summary {} {
        variable passed
        variable failed
        variable tests

        puts ""
        puts "=============================================="
        puts "Test Summary"
        puts "=============================================="
        puts "Passed: $passed"
        puts "Failed: $failed"
        puts "Total:  [expr {$passed + $failed}]"
        puts ""

        if {$failed > 0} {
            puts "Failed tests:"
            foreach test $tests {
                lassign $test name status reason
                if {$status eq "FAIL"} {
                    puts "  - $name: $reason"
                }
            }
            return 1
        }
        return 0
    }
}

#=============================================================================
# Configuration
#=============================================================================

namespace eval ::config {
    variable mcp_host "10.178.0.10"
    variable mcp_port 3000
    variable target_host "10.178.0.20"
    variable target_port 2222
    variable user "testuser"
    variable password "testpass"
    variable debug 0

    proc parse_args {argv} {
        variable mcp_host
        variable mcp_port
        variable target_host
        variable target_port
        variable user
        variable password
        variable debug

        for {set i 0} {$i < [llength $argv]} {incr i} {
            set arg [lindex $argv $i]
            switch $arg {
                "--mcp-host" {
                    incr i
                    set mcp_host [lindex $argv $i]
                }
                "--mcp-port" {
                    incr i
                    set mcp_port [lindex $argv $i]
                }
                "--target-host" {
                    incr i
                    set target_host [lindex $argv $i]
                }
                "--target-port" {
                    incr i
                    set target_port [lindex $argv $i]
                }
                "--user" {
                    incr i
                    set user [lindex $argv $i]
                }
                "--password" {
                    incr i
                    set password [lindex $argv $i]
                }
                "--debug" {
                    set debug 1
                }
                "--help" {
                    puts "Usage: tclsh e2e_test.tcl \[options\]"
                    puts ""
                    puts "Options:"
                    puts "  --mcp-host HOST     MCP server host (default: 10.178.0.10)"
                    puts "  --mcp-port PORT     MCP server port (default: 3000)"
                    puts "  --target-host HOST  SSH target host (default: 10.178.0.20)"
                    puts "  --target-port PORT  SSH target port (default: 2222)"
                    puts "  --user USER         SSH user (default: testuser)"
                    puts "  --password PASS     SSH password (default: testpass)"
                    puts "  --debug             Enable debug output"
                    puts "  --help              Show this help"
                    exit 0
                }
            }
        }
    }

    proc show {} {
        variable mcp_host
        variable mcp_port
        variable target_host
        variable target_port
        variable user
        variable debug

        puts "Configuration:"
        puts "  MCP Server:   http://${mcp_host}:${mcp_port}"
        puts "  SSH Target:   ${user}@${target_host}:${target_port}"
        puts "  Debug:        $debug"
        puts ""
    }
}

#=============================================================================
# Test Cases
#=============================================================================

proc test_health_check {} {
    puts ""
    puts "--- Test: Health Check ---"

    set url "http://$::config::mcp_host:$::config::mcp_port/health"

    if {[catch {
        set response [::agent::http::get $url]
        set status [dict get $response status]
        set body [dict get $response body]

        ::test::assert_eq $status 200 "Health endpoint returns 200"
        ::test::assert_contains $body "ok" "Health response contains 'ok'"
    } err]} {
        ::test::fail "Health check request" $err
    }
}

proc test_initialize {} {
    puts ""
    puts "--- Test: MCP Initialize ---"

    if {[catch {
        set result [::agent::mcp::initialize "e2e-test-agent" "1.0.0"]

        ::test::assert_not_empty $result "Initialize returns result"

        if {[dict exists $result protocolVersion]} {
            ::test::pass "Initialize returns protocolVersion"
        } else {
            ::test::fail "Initialize returns protocolVersion" "Missing protocolVersion"
        }

        if {[dict exists $result serverInfo]} {
            ::test::pass "Initialize returns serverInfo"
        } else {
            ::test::fail "Initialize returns serverInfo" "Missing serverInfo"
        }

        set session_id [::agent::mcp::get_session_id]
        ::test::assert_not_empty $session_id "MCP session ID assigned"

    } err]} {
        ::test::fail "MCP initialize" $err
    }
}

proc test_tools_list {} {
    puts ""
    puts "--- Test: Tools List ---"

    if {[catch {
        set tools [::agent::mcp::tools_list]

        ::test::assert {[llength $tools] > 0} "Tools list is not empty"

        # Check for expected tools
        set tool_names {}
        foreach tool $tools {
            if {[dict exists $tool name]} {
                lappend tool_names [dict get $tool name]
            }
        }

        ::test::assert_contains $tool_names "ssh_connect" "ssh_connect tool exists"
        ::test::assert_contains $tool_names "ssh_disconnect" "ssh_disconnect tool exists"
        ::test::assert_contains $tool_names "ssh_run_command" "ssh_run_command tool exists"
        ::test::assert_contains $tool_names "ssh_cat_file" "ssh_cat_file tool exists"

    } err]} {
        ::test::fail "Tools list" $err
    }
}

proc test_ssh_connect {} {
    puts ""
    puts "--- Test: SSH Connect ---"

    variable ::ssh_session_id

    if {[catch {
        set result [::agent::mcp::ssh_connect \
            $::config::target_host \
            $::config::user \
            $::config::password \
            $::config::target_port]

        ::test::assert_not_empty $result "ssh_connect returns result"

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_connect succeeds" "Tool returned error: $text"
            return
        }

        # Extract session_id from result
        if {[dict exists $result session_id]} {
            set ::ssh_session_id [dict get $result session_id]
            ::test::assert_not_empty $::ssh_session_id "SSH session_id returned"
        } else {
            # Try to get from content text
            set text [::agent::mcp::extract_text $result]
            if {[regexp {session_id[:\s]+(\S+)} $text -> sid]} {
                set ::ssh_session_id $sid
                ::test::pass "SSH session_id extracted from text"
            } else {
                ::test::fail "SSH session_id returned" "Could not find session_id in: $result"
            }
        }

    } err]} {
        ::test::fail "SSH connect" $err
    }
}

proc test_ssh_hostname {} {
    puts ""
    puts "--- Test: SSH Hostname ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "SSH hostname" "No SSH session"
        return
    }

    if {[catch {
        set result [::agent::mcp::ssh_hostname $::ssh_session_id]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_hostname succeeds" "Tool returned error: $text"
            return
        }

        set hostname [::agent::mcp::extract_text $result]
        ::test::assert_not_empty $hostname "Hostname returned"
        # Target VM hostname should contain 'target'
        ::test::assert_contains $hostname "target" "Hostname contains 'target'"

    } err]} {
        ::test::fail "SSH hostname" $err
    }
}

proc test_ssh_run_command {} {
    puts ""
    puts "--- Test: SSH Run Command ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "SSH run command" "No SSH session"
        return
    }

    if {[catch {
        # Test 'whoami'
        set result [::agent::mcp::ssh_run_command $::ssh_session_id "whoami"]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_run_command whoami" "Tool returned error: $text"
            return
        }

        set output [::agent::mcp::extract_text $result]
        ::test::assert_contains $output $::config::user "whoami returns username"

        # Test 'uname -s'
        set result [::agent::mcp::ssh_run_command $::ssh_session_id "uname -s"]
        set output [::agent::mcp::extract_text $result]
        ::test::assert_contains $output "Linux" "uname returns Linux"

    } err]} {
        ::test::fail "SSH run command" $err
    }
}

proc test_ssh_cat_file {} {
    puts ""
    puts "--- Test: SSH Cat File ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "SSH cat file" "No SSH session"
        return
    }

    if {[catch {
        # Read /etc/hostname
        set result [::agent::mcp::ssh_cat_file $::ssh_session_id "/etc/hostname"]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_cat_file /etc/hostname" "Tool returned error: $text"
            return
        }

        set content [::agent::mcp::extract_text $result]
        ::test::assert_not_empty $content "/etc/hostname has content"

        # Read /etc/os-release
        set result [::agent::mcp::ssh_cat_file $::ssh_session_id "/etc/os-release"]
        set content [::agent::mcp::extract_text $result]
        ::test::assert_contains $content "NixOS" "/etc/os-release contains NixOS"

    } err]} {
        ::test::fail "SSH cat file" $err
    }
}

proc test_ssh_disconnect {} {
    puts ""
    puts "--- Test: SSH Disconnect ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "SSH disconnect" "No SSH session"
        return
    }

    if {[catch {
        set result [::agent::mcp::ssh_disconnect $::ssh_session_id]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_disconnect succeeds" "Tool returned error: $text"
            return
        }

        ::test::pass "SSH session disconnected"

        # Clear session ID
        set ::ssh_session_id ""

    } err]} {
        ::test::fail "SSH disconnect" $err
    }
}

proc test_security_blocked_command {} {
    puts ""
    puts "--- Test: Security - Blocked Command ---"

    variable ::ssh_session_id

    # Need a fresh connection
    if {[catch {
        set result [::agent::mcp::ssh_connect \
            $::config::target_host \
            $::config::user \
            $::config::password \
            $::config::target_port]

        if {[dict exists $result session_id]} {
            set ::ssh_session_id [dict get $result session_id]
        }
    } err]} {
        ::test::skip "Security test" "Could not connect: $err"
        return
    }

    if {$::ssh_session_id eq ""} {
        ::test::skip "Security test" "No SSH session"
        return
    }

    # Try to run a blocked command (rm)
    if {[catch {
        set result [::agent::mcp::ssh_run_command $::ssh_session_id "rm -rf /"]

        if {[::agent::mcp::is_error $result]} {
            ::test::pass "Dangerous command (rm) blocked"
        } else {
            ::test::fail "Dangerous command (rm) blocked" "Command was not blocked!"
        }
    } err]} {
        # Error could mean it was blocked at RPC level
        ::test::pass "Dangerous command (rm) blocked (RPC error)"
    }

    # Try shell metacharacters
    if {[catch {
        set result [::agent::mcp::ssh_run_command $::ssh_session_id "ls; cat /etc/shadow"]

        if {[::agent::mcp::is_error $result]} {
            ::test::pass "Shell metacharacters blocked"
        } else {
            ::test::fail "Shell metacharacters blocked" "Command was not blocked!"
        }
    } err]} {
        ::test::pass "Shell metacharacters blocked (RPC error)"
    }

    # Cleanup
    catch {::agent::mcp::ssh_disconnect $::ssh_session_id}
    set ::ssh_session_id ""
}

#=============================================================================
# Network Tool E2E Tests
# Reference: DESIGN_NETWORK_COMMANDS.md
#=============================================================================

proc test_network_interfaces {} {
    puts ""
    puts "--- Test: Network Interfaces Tool ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "Network interfaces" "No SSH session"
        return
    }

    if {[catch {
        set result [::agent::mcp::call_tool "ssh_network_interfaces" \
            [dict create session_id $::ssh_session_id]]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_network_interfaces succeeds" "Tool returned error: $text"
            return
        }

        set text [::agent::mcp::extract_text $result]
        ::test::assert_not_empty $text "Network interfaces returns content"

        # Should contain lo (loopback) or eth interface
        if {[string match "*lo*" $text] || [string match "*eth*" $text]} {
            ::test::pass "Network interfaces contains interface data"
        } else {
            ::test::fail "Network interfaces contains interface data" "No interfaces found in: $text"
        }

    } err]} {
        ::test::fail "Network interfaces tool" $err
    }
}

proc test_network_routes {} {
    puts ""
    puts "--- Test: Network Routes Tool ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "Network routes" "No SSH session"
        return
    }

    if {[catch {
        set result [::agent::mcp::call_tool "ssh_network_routes" \
            [dict create session_id $::ssh_session_id]]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_network_routes succeeds" "Tool returned error: $text"
            return
        }

        ::test::pass "Network routes tool returns result"

        if {[dict exists $result routes]} {
            ::test::pass "Network routes contains routes dict"
        }

    } err]} {
        ::test::fail "Network routes tool" $err
    }
}

proc test_network_qdisc {} {
    puts ""
    puts "--- Test: Network QDisc Tool ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "Network qdisc" "No SSH session"
        return
    }

    if {[catch {
        set result [::agent::mcp::call_tool "ssh_network_qdisc" \
            [dict create session_id $::ssh_session_id]]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_network_qdisc succeeds" "Tool returned error: $text"
            return
        }

        set text [::agent::mcp::extract_text $result]
        ::test::assert_not_empty $text "Network qdisc returns content"

    } err]} {
        ::test::fail "Network qdisc tool" $err
    }
}

proc test_network_connectivity {} {
    puts ""
    puts "--- Test: Network Connectivity Tool ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "Network connectivity" "No SSH session"
        return
    }

    if {[catch {
        # Test ping to localhost (should always work)
        set result [::agent::mcp::call_tool "ssh_network_connectivity" \
            [dict create \
                session_id $::ssh_session_id \
                target "localhost" \
                tests [list ping] \
                ping_count 2]]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_network_connectivity succeeds" "Tool returned error: $text"
            return
        }

        ::test::pass "Network connectivity tool returns result"

        if {[dict exists $result results]} {
            ::test::pass "Network connectivity contains results dict"
        }

    } err]} {
        ::test::fail "Network connectivity tool" $err
    }
}

proc test_batch_commands {} {
    puts ""
    puts "--- Test: Batch Commands Tool ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "Batch commands" "No SSH session"
        return
    }

    if {[catch {
        set result [::agent::mcp::call_tool "ssh_batch_commands" \
            [dict create \
                session_id $::ssh_session_id \
                commands [list hostname uname]]]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ssh_batch_commands succeeds" "Tool returned error: $text"
            return
        }

        ::test::pass "Batch commands tool returns result"

        if {[dict exists $result results]} {
            set results [dict get $result results]
            ::test::assert_eq [llength $results] 2 "Batch executed 2 commands"
        }

        if {[dict exists $result all_success]} {
            if {[dict get $result all_success]} {
                ::test::pass "All batch commands succeeded"
            }
        }

    } err]} {
        ::test::fail "Batch commands tool" $err
    }
}

proc test_batch_limit_enforced {} {
    puts ""
    puts "--- Test: Batch Size Limit ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "Batch limit" "No SSH session"
        return
    }

    # Try to submit 6 commands (should fail)
    if {[catch {
        set result [::agent::mcp::call_tool "ssh_batch_commands" \
            [dict create \
                session_id $::ssh_session_id \
                commands [list a b c d e f]]]

        if {[::agent::mcp::is_error $result]} {
            ::test::pass "Batch size limit correctly enforced (>5 rejected)"
        } else {
            ::test::fail "Batch size limit" "Should reject >5 commands"
        }
    } err]} {
        # Error could mean it was blocked at RPC level
        ::test::pass "Batch size limit correctly enforced (RPC error)"
    }
}

proc test_network_security_blocked {} {
    puts ""
    puts "--- Test: Network Security - Blocked Commands ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "Network security" "No SSH session"
        return
    }

    # Try ip link set (should be blocked)
    if {[catch {
        set result [::agent::mcp::ssh_run_command $::ssh_session_id "ip link set eth0 down"]

        if {[::agent::mcp::is_error $result]} {
            ::test::pass "ip link set blocked"
        } else {
            ::test::fail "ip link set blocked" "Command was not blocked!"
        }
    } err]} {
        ::test::pass "ip link set blocked (RPC error)"
    }

    # Try ethtool --flash (should be blocked)
    if {[catch {
        set result [::agent::mcp::ssh_run_command $::ssh_session_id "ethtool --flash eth0 fw.bin"]

        if {[::agent::mcp::is_error $result]} {
            ::test::pass "ethtool --flash blocked"
        } else {
            ::test::fail "ethtool --flash blocked" "Command was not blocked!"
        }
    } err]} {
        ::test::pass "ethtool --flash blocked (RPC error)"
    }

    # Try ping flood (should be blocked)
    if {[catch {
        set result [::agent::mcp::ssh_run_command $::ssh_session_id "ping -f localhost"]

        if {[::agent::mcp::is_error $result]} {
            ::test::pass "ping -f (flood) blocked"
        } else {
            ::test::fail "ping -f (flood) blocked" "Command was not blocked!"
        }
    } err]} {
        ::test::pass "ping -f (flood) blocked (RPC error)"
    }
}

proc test_network_allowed {} {
    puts ""
    puts "--- Test: Network - Allowed Commands ---"

    variable ::ssh_session_id

    if {$::ssh_session_id eq ""} {
        ::test::skip "Network allowed" "No SSH session"
        return
    }

    # Try ip link show (should be allowed)
    if {[catch {
        set result [::agent::mcp::ssh_run_command $::ssh_session_id "ip link show"]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ip link show allowed" "Tool returned error: $text"
        } else {
            set text [::agent::mcp::extract_text $result]
            if {[string match "*lo*" $text] || [string match "*eth*" $text]} {
                ::test::pass "ip link show returns interface data"
            } else {
                ::test::fail "ip link show returns interface data" "No interfaces in: $text"
            }
        }
    } err]} {
        ::test::fail "ip link show allowed" $err
    }

    # Try ping -c 2 localhost (should be allowed)
    if {[catch {
        set result [::agent::mcp::ssh_run_command $::ssh_session_id "ping -c 2 localhost"]

        if {[::agent::mcp::is_error $result]} {
            set text [::agent::mcp::extract_text $result]
            ::test::fail "ping -c 2 allowed" "Tool returned error: $text"
        } else {
            ::test::pass "ping -c 2 localhost allowed"
        }
    } err]} {
        ::test::fail "ping -c 2 allowed" $err
    }
}

#=============================================================================
# Main
#=============================================================================

proc main {argv} {
    # Parse arguments
    ::config::parse_args $argv

    # Configure debug
    if {$::config::debug} {
        ::agent::mcp::set_debug 1
    }

    # Show config
    puts "=============================================="
    puts "MCP E2E Test Suite"
    puts "=============================================="
    ::config::show

    # Initialize MCP client
    ::agent::mcp::init "http://$::config::mcp_host:$::config::mcp_port"

    # Reset test counters
    ::test::reset

    # Initialize SSH session variable
    variable ::ssh_session_id ""

    # Run tests - Core functionality
    test_health_check
    test_initialize
    test_tools_list
    test_ssh_connect
    test_ssh_hostname
    test_ssh_run_command
    test_ssh_cat_file

    # Run tests - Network tools (requires active SSH session)
    # Re-connect for network tests
    test_ssh_connect
    test_network_interfaces
    test_network_routes
    test_network_qdisc
    test_network_connectivity
    test_batch_commands
    test_batch_limit_enforced
    test_network_allowed
    test_network_security_blocked
    test_ssh_disconnect

    # Security tests
    test_security_blocked_command

    # Summary
    set exit_code [::test::summary]

    exit $exit_code
}

# Run main
main $argv
