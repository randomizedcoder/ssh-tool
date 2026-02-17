# mcp/agent/loadtest/scenarios/sustained_load.tcl
#
# Sustained Load Test Scenario
#
# Runs a mixed workload over extended period to identify:
# - Memory leaks
# - Connection pool issues
# - Performance degradation over time

package require Tcl 9.0-

namespace eval ::loadtest::scenario::sustained_load {
    # Scenario configuration
    variable config [dict create \
        name "sustained_load" \
        description "10-minute stability test with mixed workload" \
        duration 600 \
        warmup 30 \
        workers 5 \
        target_rate_pct 50 \
        workload_mix [dict create \
            commands 70 \
            connect 20 \
            disconnect 10 \
        ] \
        sample_interval_ms 5000 \
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
            pattern "sustained_load" \
            duration $duration \
            mix [dict get $config workload_mix] \
        ]
    }

    # Analyze results specific to this scenario
    proc analyze {results} {
        set analysis [dict create]

        # Check for error rate increase
        if {[dict exists $results total_requests] && [dict exists $results total_errors]} {
            set total [dict get $results total_requests]
            set errors [dict get $results total_errors]
            set error_rate [expr {$errors * 100.0 / max(1, $total)}]

            dict set analysis error_rate $error_rate

            if {$error_rate > 1} {
                dict set analysis warning "Error rate ${error_rate}% exceeds 1% threshold"
            }
        }

        # Check throughput stability
        if {[dict exists $results throughput]} {
            set throughput [dict get $results throughput]
            set avg_rps [dict get $throughput avg_rps]
            set peak_rps [dict get $throughput peak_rps]

            # If peak is more than 2x average, there's instability
            if {$peak_rps > $avg_rps * 2} {
                dict set analysis warning "Throughput variance high (peak ${peak_rps} vs avg ${avg_rps})"
            }

            dict set analysis throughput_stable [expr {$peak_rps <= $avg_rps * 1.5}]
        }

        # Check latency trends (would need time-series data for proper analysis)
        if {[dict exists $results latency]} {
            set latency [dict get $results latency]
            set max_lat [dict get $latency max]
            set p99_lat [dict get $latency p99]

            # If max is much higher than p99, there were outlier spikes
            if {$max_lat > $p99_lat * 5} {
                dict set analysis warning "Latency spikes detected (max ${max_lat}ms vs p99 ${p99_lat}ms)"
            }
        }

        dict set analysis recommendation "Review resource metrics for memory growth patterns"

        return $analysis
    }
}

package provide loadtest::scenario::sustained_load 1.0
