# mcp/agent/loadtest/config.tcl - Load test configuration
#
# Default parameters for load testing scenarios.
# Can be overridden via command-line arguments.

package require Tcl 9.0-

namespace eval ::loadtest::config {
    # MCP server connection
    variable mcp_host "10.178.0.10"
    variable mcp_port 3000

    # SSH target defaults
    variable target_host "10.178.0.20"
    variable target_port 2222
    variable target_user "testuser"
    variable target_pass "testpass"

    # Worker configuration
    variable num_workers 5
    variable warmup_seconds 10

    # Output configuration
    variable results_dir "/tmp/loadtest_results"
    variable verbose 0

    # Scenario-specific defaults
    variable scenarios [dict create \
        connection_rate [dict create \
            duration 60 \
            workers {1 2 5 10} \
            description "Measure max SSH connections/second" \
        ] \
        command_throughput [dict create \
            duration 120 \
            workers 10 \
            pre_warm_sessions 5 \
            commands {hostname whoami "cat /etc/hostname"} \
            description "Measure max commands/second on warm connections" \
        ] \
        sustained_load [dict create \
            duration 600 \
            workers 5 \
            target_rate_pct 50 \
            workload_mix [dict create commands 70 connect 20 disconnect 10] \
            description "Identify resource leaks over 10 minutes" \
        ] \
        latency_test [dict create \
            duration 60 \
            workers 3 \
            target_rate 10 \
            ports {2222 2322 2323 2324 2325} \
            description "Measure latency impact via netem ports" \
        ] \
        exhaustion_test [dict create \
            duration 60 \
            workers 15 \
            target_connections 15 \
            target_rate 150 \
            description "Verify graceful degradation at limits" \
        ] \
    ]

    # Get scenario config
    proc get_scenario {name} {
        variable scenarios
        if {![dict exists $scenarios $name]} {
            error "Unknown scenario: $name. Available: [dict keys $scenarios]"
        }
        return [dict get $scenarios $name]
    }

    # List available scenarios
    proc list_scenarios {} {
        variable scenarios
        return [dict keys $scenarios]
    }

    # Override config from command line args
    proc parse_args {argv} {
        variable mcp_host
        variable mcp_port
        variable target_host
        variable target_port
        variable target_user
        variable target_pass
        variable num_workers
        variable warmup_seconds
        variable results_dir
        variable verbose

        for {set i 0} {$i < [llength $argv]} {incr i} {
            set arg [lindex $argv $i]
            switch -glob -- $arg {
                "--mcp-host"    { incr i; set mcp_host [lindex $argv $i] }
                "--mcp-port"    { incr i; set mcp_port [lindex $argv $i] }
                "--target-host" { incr i; set target_host [lindex $argv $i] }
                "--target-port" { incr i; set target_port [lindex $argv $i] }
                "--user"        { incr i; set target_user [lindex $argv $i] }
                "--password"    { incr i; set target_pass [lindex $argv $i] }
                "--workers"     { incr i; set num_workers [lindex $argv $i] }
                "--warmup"      { incr i; set warmup_seconds [lindex $argv $i] }
                "--results-dir" { incr i; set results_dir [lindex $argv $i] }
                "--verbose"     { set verbose 1 }
                "-v"            { set verbose 1 }
            }
        }
    }

    # Get full MCP URL
    proc mcp_url {} {
        variable mcp_host
        variable mcp_port
        return "http://${mcp_host}:${mcp_port}"
    }
}

package provide loadtest::config 1.0
