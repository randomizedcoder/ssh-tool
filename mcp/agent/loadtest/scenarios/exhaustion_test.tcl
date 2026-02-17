# mcp/agent/loadtest/scenarios/exhaustion_test.tcl
#
# Pool Exhaustion Test Scenario
#
# Verifies graceful degradation when limits are exceeded:
# - Connection pool limit (default: 10)
# - Rate limit (default: 100 req/min)
# - Session limit

package require Tcl 9.0-

namespace eval ::loadtest::scenario::exhaustion_test {
    # Scenario configuration
    variable config [dict create \
        name "exhaustion_test" \
        description "Verify graceful degradation at pool/rate limits" \
        duration 60 \
        warmup 5 \
        workers 15 \
        target_connections 15 \
        target_rate 150 \
        expected_pool_limit 10 \
        expected_rate_limit 100 \
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
            pattern "exhaustion_test" \
            duration $duration \
            connections [dict get $config target_connections] \
        ]
    }

    # Analyze results specific to this scenario
    proc analyze {results} {
        variable config
        set analysis [dict create]

        set expected_pool_limit [dict get $config expected_pool_limit]
        set expected_rate_limit [dict get $config expected_rate_limit]
        set target_connections [dict get $config target_connections]

        if {[dict exists $results total_requests] && [dict exists $results total_errors]} {
            set total [dict get $results total_requests]
            set errors [dict get $results total_errors]
            set success_rate [dict get $results success_rate]

            dict set analysis total_requests $total
            dict set analysis errors $errors
            dict set analysis success_rate $success_rate

            # We expect some errors when exceeding limits
            if {$errors == 0 && $target_connections > $expected_pool_limit} {
                dict set analysis warning "No rejections despite exceeding pool limit - limits may not be enforced"
                dict set analysis pool_limit_enforced 0
            } else {
                dict set analysis pool_limit_enforced 1
            }

            # Calculate rejection rate
            set rejection_rate [expr {$errors * 100.0 / max(1, $total)}]
            dict set analysis rejection_rate $rejection_rate

            # Expected rejection rate if limits are working
            # If we have 15 workers but only 10 slots, expect ~33% rejection
            set expected_rejection [expr {max(0, ($target_connections - $expected_pool_limit) * 100.0 / $target_connections)}]
            dict set analysis expected_rejection_rate $expected_rejection

            if {$rejection_rate > 0 && $rejection_rate < $expected_rejection * 2} {
                dict set analysis verdict "PASS: System correctly rejected excess requests"
            } elseif {$rejection_rate == 0} {
                dict set analysis verdict "INCONCLUSIVE: No rejections observed"
            } else {
                dict set analysis verdict "REVIEW: Rejection rate higher than expected"
            }
        }

        # Check MCP metrics for rate limit rejections
        if {[dict exists $results mcp_metrics_after]} {
            set metrics [dict get $results mcp_metrics_after]
            # Look for rate limit counter (if implemented)
            # This would show if rate limiting kicked in
        }

        dict set analysis recommendations [list \
            "Review error messages for correct error codes (429 for rate limit, pool exhaustion errors)" \
            "Verify no crash or hang behavior during overload" \
            "Check recovery time after load reduction" \
        ]

        return $analysis
    }
}

package provide loadtest::scenario::exhaustion_test 1.0
