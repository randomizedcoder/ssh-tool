#!/usr/bin/env tclsh
# mcp/agent/loadtest/run.tcl - Load test main entry point
#
# Usage:
#   tclsh run.tcl --scenario <name> [options]
#   tclsh run.tcl --list-scenarios
#   tclsh run.tcl --quick
#   tclsh run.tcl --full
#
# Examples:
#   tclsh run.tcl --scenario command_throughput --duration 60
#   tclsh run.tcl --scenario connection_rate --workers 10
#   tclsh run.tcl --quick  # 30-second smoke test
#   tclsh run.tcl --full   # All 5 scenarios

package require Tcl 9.0-

# Use unique variable names to avoid collision with sourced files
# Normalize to absolute paths so sourcing works from any cwd
set _loadtest_dir [file normalize [file dirname [info script]]]
set _agent_dir [file dirname $_loadtest_dir]

# Source dependencies - order matters!
# 1. Loadtest config and utilities first (before agent files that may overwrite globals)
source [file join $_loadtest_dir config.tcl]
source [file join $_loadtest_dir metrics percentiles.tcl]
source [file join $_loadtest_dir output jsonl_writer.tcl]
# 2. Agent HTTP/JSON libraries (may overwrite script_dir global)
source [file join $_agent_dir http_client.tcl]
source [file join $_agent_dir json.tcl]
source [file join $_agent_dir mcp_client.tcl]
# 3. Higher-level modules that depend on the above
source [file join $_loadtest_dir coordinator.tcl]
source [file join $_loadtest_dir output report.tcl]
source [file join $_loadtest_dir metrics collector.tcl]

namespace eval ::loadtest::main {
    # Print usage
    proc usage {} {
        puts {
Load Test Runner for MCP SSH Automation

Usage:
    tclsh run.tcl [options]

Options:
    --scenario <name>   Run a specific scenario
    --list-scenarios    List available scenarios
    --quick             Run quick smoke test (30s)
    --full              Run all scenarios
    --duration <secs>   Override test duration
    --workers <num>     Override number of workers
    --mcp-host <host>   MCP server host (default: 10.178.0.10)
    --mcp-port <port>   MCP server port (default: 3000)
    --target-host <h>   SSH target host (default: 10.178.0.20)
    --target-port <p>   SSH target port (default: 2222)
    --user <user>       SSH username (default: testuser)
    --password <pass>   SSH password (default: testpass)
    --results-dir <d>   Results directory (default: /tmp/loadtest_results)
    --verbose           Enable verbose output
    --help              Show this help

Scenarios:
    connection_rate     Measure max SSH connections/second
    command_throughput  Measure max commands/second
    sustained_load      10-minute stability test
    latency_test        Network degradation impact
    exhaustion_test     Pool limit behavior

Examples:
    tclsh run.tcl --scenario command_throughput
    tclsh run.tcl --quick
    tclsh run.tcl --full
    tclsh run.tcl --scenario latency_test --duration 120
        }
    }

    # List available scenarios
    proc list_scenarios {} {
        puts "Available scenarios:"
        puts ""

        foreach scenario [::loadtest::config::list_scenarios] {
            set config [::loadtest::config::get_scenario $scenario]
            set desc [dict get $config description]
            set duration [dict get $config duration]

            puts [format "  %-20s %s" $scenario $desc]
            puts [format "  %-20s Duration: %ds" "" $duration]
            puts ""
        }
    }

    # Run quick smoke test
    proc run_quick {} {
        puts "Running quick smoke test (30s)..."
        puts ""

        set overrides [dict create duration 30 workers 3]
        set results [::loadtest::coordinator::run_scenario "command_throughput" $overrides]

        ::loadtest::output::report::print $results

        return [expr {[dict get $results total_errors] == 0}]
    }

    # Run full test suite
    proc run_full {} {
        puts "Running full load test suite..."
        puts "This will take approximately 15-20 minutes."
        puts ""

        set all_results [list]

        foreach scenario [::loadtest::config::list_scenarios] {
            puts "=========================================="
            puts "Scenario: $scenario"
            puts "=========================================="

            set results [::loadtest::coordinator::run_scenario $scenario]
            lappend all_results $results

            ::loadtest::output::report::print $results
            puts ""
        }

        puts "=========================================="
        puts "FULL TEST SUITE COMPLETE"
        puts "=========================================="

        # Summary
        set total_scenarios [llength $all_results]
        set passed 0

        foreach r $all_results {
            if {[dict exists $r total_errors] && [dict get $r total_errors] == 0} {
                incr passed
            } elseif {![dict exists $r total_errors]} {
                incr passed  ;# No errors key means scenario didn't track errors
            }
        }

        puts "Scenarios run: $total_scenarios"
        puts "Scenarios passed: $passed"

        return [expr {$passed == $total_scenarios}]
    }

    # Check MCP server health
    proc check_health {} {
        set url "[::loadtest::config::mcp_url]/health"

        puts -nonewline "Checking MCP server at $url... "
        flush stdout

        if {[catch {
            set response [::agent::http::get $url]
            set status [dict get $response status]
        } err]} {
            puts "FAILED"
            puts "Error: $err"
            return 0
        }

        if {$status != 200} {
            puts "FAILED (HTTP $status)"
            return 0
        }

        puts "OK"
        return 1
    }

    # Main entry point
    proc main {argv} {
        set scenario ""
        set quick 0
        set full 0
        set list_only 0
        set show_help 0
        set overrides [dict create]

        # Parse arguments
        ::loadtest::config::parse_args $argv

        for {set i 0} {$i < [llength $argv]} {incr i} {
            set arg [lindex $argv $i]
            switch -glob -- $arg {
                "--scenario"        { incr i; set scenario [lindex $argv $i] }
                "--list-scenarios"  { set list_only 1 }
                "--quick"           { set quick 1 }
                "--full"            { set full 1 }
                "--duration"        { incr i; dict set overrides duration [lindex $argv $i] }
                "--workers"         { incr i; dict set overrides workers [lindex $argv $i] }
                "--help"            { set show_help 1 }
                "-h"                { set show_help 1 }
            }
        }

        # Handle help and list
        if {$show_help} {
            usage
            return 0
        }

        if {$list_only} {
            list_scenarios
            return 0
        }

        # Print banner
        puts "============================================"
        puts "  MCP SSH Automation Load Tester"
        puts "============================================"
        puts ""

        # Check health first
        if {![check_health]} {
            puts ""
            puts "ERROR: MCP server not available."
            puts "Make sure the MCP server is running at [::loadtest::config::mcp_url]"
            return 1
        }
        puts ""

        # Run appropriate test
        set success 0

        if {$quick} {
            set success [run_quick]
        } elseif {$full} {
            set success [run_full]
        } elseif {$scenario ne ""} {
            # Validate scenario
            if {$scenario ni [::loadtest::config::list_scenarios]} {
                puts "ERROR: Unknown scenario '$scenario'"
                puts ""
                list_scenarios
                return 1
            }

            puts "Running scenario: $scenario"
            puts ""

            set results [::loadtest::coordinator::run_scenario $scenario $overrides]
            ::loadtest::output::report::print $results

            set success [expr {![dict exists $results total_errors] || [dict get $results total_errors] == 0}]
        } else {
            puts "ERROR: No scenario specified."
            puts ""
            usage
            return 1
        }

        puts ""
        if {$success} {
            puts "TEST PASSED"
            return 0
        } else {
            puts "TEST COMPLETED WITH ERRORS"
            return 1
        }
    }
}

# Run if executed directly
if {[info script] eq $::argv0} {
    exit [::loadtest::main::main $::argv]
}
