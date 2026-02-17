# mcp/agent/loadtest/scenarios/connection_rate.tcl
#
# Connection Rate Test Scenario
#
# Measures maximum SSH connection establishment rate.
# Tests connect/disconnect cycles at various worker counts.

package require Tcl 9.0-

namespace eval ::loadtest::scenario::connection_rate {
    # Scenario configuration
    variable config [dict create \
        name "connection_rate" \
        description "Measure max SSH connections per second" \
        duration 60 \
        warmup 10 \
        worker_counts {1 2 5 10} \
        delay_between_cycles_ms 10 \
    ]

    # Get scenario config
    proc get_config {} {
        variable config
        return $config
    }

    # Run the scenario
    # Called by coordinator, returns pattern-specific args
    proc prepare {num_workers duration} {
        return [dict create \
            pattern "connection_rate" \
            duration $duration \
        ]
    }

    # Analyze results specific to this scenario
    proc analyze {results} {
        set analysis [dict create]

        # Find the worker count with best throughput
        set best_rps 0
        set best_workers 0

        if {[dict exists $results iterations]} {
            foreach iter [dict get $results iterations] {
                set throughput [dict get $iter throughput]
                set rps [dict get $throughput avg_rps]
                set workers [dict get $iter num_workers]

                if {$rps > $best_rps} {
                    set best_rps $rps
                    set best_workers $workers
                }
            }
        }

        dict set analysis best_workers $best_workers
        dict set analysis best_rps $best_rps
        dict set analysis recommendation "Optimal worker count: $best_workers (${best_rps} conn/s)"

        return $analysis
    }
}

package provide loadtest::scenario::connection_rate 1.0
