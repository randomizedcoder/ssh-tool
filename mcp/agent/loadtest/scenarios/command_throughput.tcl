# mcp/agent/loadtest/scenarios/command_throughput.tcl
#
# Command Throughput Test Scenario
#
# Measures maximum commands per second on established connections.
# Uses pre-warmed connection pool for pure command throughput.

package require Tcl 9.0-

namespace eval ::loadtest::scenario::command_throughput {
    # Scenario configuration
    variable config [dict create \
        name "command_throughput" \
        description "Measure max commands per second on warm connections" \
        duration 120 \
        warmup 10 \
        workers 10 \
        pre_warm_sessions 5 \
        commands {hostname whoami "cat /etc/hostname"} \
    ]

    # Get scenario config
    proc get_config {} {
        variable config
        return $config
    }

    # Run the scenario
    proc prepare {num_workers duration} {
        variable config

        return [dict create \
            pattern "command_throughput" \
            duration $duration \
            commands [dict get $config commands] \
        ]
    }

    # Analyze results specific to this scenario
    proc analyze {results} {
        set analysis [dict create]

        if {[dict exists $results throughput]} {
            set throughput [dict get $results throughput]
            set avg_rps [dict get $throughput avg_rps]
            set peak_rps [dict get $throughput peak_rps]

            dict set analysis avg_commands_per_sec $avg_rps
            dict set analysis peak_commands_per_sec $peak_rps
            dict set analysis efficiency [expr {$avg_rps / max(1, $peak_rps) * 100}]
        }

        if {[dict exists $results latency]} {
            set latency [dict get $results latency]
            set p99 [dict get $latency p99]

            if {$p99 > 500} {
                dict set analysis warning "High p99 latency (${p99}ms) - possible contention"
            }
        }

        return $analysis
    }
}

package provide loadtest::scenario::command_throughput 1.0
