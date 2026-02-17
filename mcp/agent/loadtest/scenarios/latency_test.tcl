# mcp/agent/loadtest/scenarios/latency_test.tcl
#
# Latency Sensitivity Test Scenario
#
# Measures impact of network latency on throughput.
# Uses netem ports to test degraded network conditions.

package require Tcl 9.0-

namespace eval ::loadtest::scenario::latency_test {
    # Scenario configuration
    # Port mapping (from nix/constants/netem.nix):
    #   2222 - baseline (no latency)
    #   2322 - 100ms latency + 10ms jitter
    #   2323 - 50ms latency + 5% loss
    #   2324 - 200ms latency + 10% loss
    #   2325 - 500ms latency (slow auth)
    variable config [dict create \
        name "latency_test" \
        description "Measure latency impact on throughput via netem ports" \
        duration 60 \
        warmup 10 \
        workers 3 \
        target_rate 10 \
        ports [dict create \
            2222 "baseline" \
            2322 "100ms+jitter" \
            2323 "50ms+5%loss" \
            2324 "200ms+10%loss" \
            2325 "500ms" \
        ] \
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
            pattern "latency_test" \
            duration $duration \
            rate [dict get $config target_rate] \
        ]
    }

    # Analyze results specific to this scenario
    proc analyze {results} {
        variable config
        set analysis [dict create]

        if {![dict exists $results port_results]} {
            dict set analysis error "No port results found"
            return $analysis
        }

        set port_names [dict get $config ports]
        set baseline_p50 0
        set port_analysis [list]

        foreach port_result [dict get $results port_results] {
            set port [dict get $port_result port]
            set latency [dict get $port_result latency]
            set errors [dict get $port_result total_errors]

            set p50 [dict get $latency p50]
            set p99 [dict get $latency p99]

            set port_name "unknown"
            if {[dict exists $port_names $port]} {
                set port_name [dict get $port_names $port]
            }

            # Record baseline
            if {$port == 2222} {
                set baseline_p50 $p50
            }

            # Calculate amplification factor
            set amplification 1.0
            if {$baseline_p50 > 0 && $port != 2222} {
                set amplification [expr {$p50 / $baseline_p50}]
            }

            lappend port_analysis [dict create \
                port $port \
                name $port_name \
                p50 $p50 \
                p99 $p99 \
                errors $errors \
                amplification $amplification \
            ]
        }

        dict set analysis port_analysis $port_analysis
        dict set analysis baseline_p50 $baseline_p50

        # Recommendations
        set recommendations [list]
        foreach pa $port_analysis {
            set port [dict get $pa port]
            set errors [dict get $pa errors]
            set amp [dict get $pa amplification]

            if {$errors > 0} {
                lappend recommendations "Port $port: ${errors} errors - check timeout settings"
            } elseif {$amp > 10} {
                lappend recommendations "Port $port: ${amp}x latency amplification - severe degradation"
            }
        }

        dict set analysis recommendations $recommendations

        return $analysis
    }
}

package provide loadtest::scenario::latency_test 1.0
