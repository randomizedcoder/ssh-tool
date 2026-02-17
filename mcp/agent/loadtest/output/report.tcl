# mcp/agent/loadtest/output/report.tcl - Report generator
#
# Generates human-readable reports from load test results.

package require Tcl 9.0-

namespace eval ::loadtest::output::report {
    # Generate summary report
    # @param results  Results dict from coordinator
    # @return formatted report string
    proc generate {results} {
        set lines [list]

        set scenario [dict get $results scenario]
        set test_id [dict get $results test_id]
        set duration_ms [dict get $results duration_ms]
        set duration_s [expr {$duration_ms / 1000.0}]

        # Header
        lappend lines [string repeat "=" 70]
        lappend lines [center "LOAD TEST RESULTS" 70]
        lappend lines [string repeat "=" 70]
        lappend lines ""
        lappend lines "Test ID:    $test_id"
        lappend lines "Scenario:   $scenario"
        lappend lines "Duration:   [format "%.1fs" $duration_s]"
        lappend lines ""

        # Scenario-specific output
        switch $scenario {
            "connection_rate" {
                lappend lines [generate_connection_rate_report $results]
            }
            "command_throughput" {
                lappend lines [generate_throughput_report $results]
            }
            "sustained_load" {
                lappend lines [generate_sustained_report $results]
            }
            "latency_test" {
                lappend lines [generate_latency_report $results]
            }
            "exhaustion_test" {
                lappend lines [generate_exhaustion_report $results]
            }
            default {
                lappend lines [generate_generic_report $results]
            }
        }

        # MCP metrics diff
        if {[dict exists $results mcp_metrics_before] && [dict exists $results mcp_metrics_after]} {
            lappend lines ""
            lappend lines [generate_metrics_diff $results]
        }

        # Extrapolation
        lappend lines ""
        lappend lines [generate_extrapolation $results]

        # Footer
        lappend lines ""
        lappend lines [string repeat "=" 70]

        return [join $lines "\n"]
    }

    # Connection rate scenario report
    proc generate_connection_rate_report {results} {
        set lines [list]
        lappend lines [string repeat "-" 70]
        lappend lines "CONNECTION RATE TEST"
        lappend lines [string repeat "-" 70]
        lappend lines ""
        lappend lines [format "%-10s %10s %10s %10s %10s" "Workers" "Conns/s" "p50 ms" "p95 ms" "p99 ms"]
        lappend lines [string repeat "-" 52]

        foreach iter [dict get $results iterations] {
            set num_workers [dict get $iter num_workers]
            set throughput [dict get $iter throughput]
            set latency [dict get $iter latency]

            set rps [format "%.1f" [dict get $throughput avg_rps]]
            set p50 [format "%.1f" [dict get $latency p50]]
            set p95 [format "%.1f" [dict get $latency p95]]
            set p99 [format "%.1f" [dict get $latency p99]]

            lappend lines [format "%-10d %10s %10s %10s %10s" $num_workers $rps $p50 $p95 $p99]
        }

        return [join $lines "\n"]
    }

    # Command throughput scenario report
    proc generate_throughput_report {results} {
        set lines [list]
        lappend lines [string repeat "-" 70]
        lappend lines "COMMAND THROUGHPUT TEST"
        lappend lines [string repeat "-" 70]
        lappend lines ""

        set total [dict get $results total_requests]
        set errors [dict get $results total_errors]
        set success_rate [dict get $results success_rate]
        set throughput [dict get $results throughput]
        set latency [dict get $results latency]

        lappend lines "THROUGHPUT"
        lappend lines [format "  Total Requests:     %d" $total]
        lappend lines [format "  Successful:         %d (%.1f%%)" [expr {$total - $errors}] $success_rate]
        lappend lines [format "  Failed:             %d" $errors]
        lappend lines [format "  Requests/Second:    %.1f avg, %.1f peak" \
            [dict get $throughput avg_rps] [dict get $throughput peak_rps]]
        lappend lines ""

        lappend lines "LATENCY (milliseconds)"
        lappend lines [format "  Min:    %.1f" [dict get $latency min]]
        lappend lines [format "  p50:    %.1f" [dict get $latency p50]]
        lappend lines [format "  p95:    %.1f" [dict get $latency p95]]
        lappend lines [format "  p99:    %.1f" [dict get $latency p99]]
        lappend lines [format "  Max:    %.1f" [dict get $latency max]]

        return [join $lines "\n"]
    }

    # Sustained load scenario report
    proc generate_sustained_report {results} {
        set lines [list]
        lappend lines [string repeat "-" 70]
        lappend lines "SUSTAINED LOAD TEST"
        lappend lines [string repeat "-" 70]
        lappend lines ""

        set total [dict get $results total_requests]
        set errors [dict get $results total_errors]
        set throughput [dict get $results throughput]
        set latency [dict get $results latency]

        lappend lines "STABILITY METRICS"
        lappend lines [format "  Total Operations:   %d" $total]
        lappend lines [format "  Error Count:        %d" $errors]
        lappend lines [format "  Error Rate:         %.2f%%" [expr {$errors * 100.0 / max(1, $total)}]]
        lappend lines [format "  Avg Throughput:     %.1f ops/s" [dict get $throughput avg_rps]]
        lappend lines ""

        lappend lines "LATENCY OVER TIME"
        lappend lines [format "  Average:   %.1f ms" [dict get $latency avg]]
        lappend lines [format "  p99:       %.1f ms" [dict get $latency p99]]
        lappend lines [format "  Max:       %.1f ms" [dict get $latency max]]

        # Check for degradation
        if {[dict get $latency max] > [expr {[dict get $latency p99] * 3}]} {
            lappend lines ""
            lappend lines "WARNING: Max latency significantly higher than p99 - possible degradation"
        }

        return [join $lines "\n"]
    }

    # Latency test scenario report
    proc generate_latency_report {results} {
        set lines [list]
        lappend lines [string repeat "-" 70]
        lappend lines "LATENCY SENSITIVITY TEST"
        lappend lines [string repeat "-" 70]
        lappend lines ""
        lappend lines [format "%-10s %10s %10s %10s %10s %10s" "Port" "Requests" "p50 ms" "p95 ms" "p99 ms" "Errors"]
        lappend lines [string repeat "-" 62]

        set baseline_p50 0

        foreach port_result [dict get $results port_results] {
            set port [dict get $port_result port]
            set total [dict get $port_result total_requests]
            set errors [dict get $port_result total_errors]
            set latency [dict get $port_result latency]

            set p50 [dict get $latency p50]
            set p95 [dict get $latency p95]
            set p99 [dict get $latency p99]

            if {$baseline_p50 == 0} {
                set baseline_p50 $p50
            }

            lappend lines [format "%-10d %10d %10.1f %10.1f %10.1f %10d" \
                $port $total $p50 $p95 $p99 $errors]
        }

        lappend lines ""
        lappend lines "Baseline p50 (port 2222): [format "%.1f" $baseline_p50] ms"

        return [join $lines "\n"]
    }

    # Exhaustion test scenario report
    proc generate_exhaustion_report {results} {
        set lines [list]
        lappend lines [string repeat "-" 70]
        lappend lines "POOL EXHAUSTION TEST"
        lappend lines [string repeat "-" 70]
        lappend lines ""

        set total [dict get $results total_requests]
        set errors [dict get $results total_errors]
        set success_rate [dict get $results success_rate]

        lappend lines "LIMIT BEHAVIOR"
        lappend lines [format "  Total Requests:     %d" $total]
        lappend lines [format "  Successful:         %d (%.1f%%)" [expr {$total - $errors}] $success_rate]
        lappend lines [format "  Rejected/Failed:    %d" $errors]
        lappend lines ""

        if {$errors > 0} {
            lappend lines "PASS: System correctly rejected excess requests"
        } else {
            lappend lines "NOTE: No rejections observed - may need higher load"
        }

        return [join $lines "\n"]
    }

    # Generic report for unknown scenarios
    proc generate_generic_report {results} {
        set lines [list]
        lappend lines [string repeat "-" 70]
        lappend lines "TEST RESULTS"
        lappend lines [string repeat "-" 70]

        if {[dict exists $results total_requests]} {
            lappend lines [format "Total Requests: %d" [dict get $results total_requests]]
        }
        if {[dict exists $results total_errors]} {
            lappend lines [format "Total Errors:   %d" [dict get $results total_errors]]
        }

        return [join $lines "\n"]
    }

    # Generate MCP metrics diff
    proc generate_metrics_diff {results} {
        set lines [list]
        lappend lines [string repeat "-" 70]
        lappend lines "MCP SERVER METRICS DELTA"
        lappend lines [string repeat "-" 70]

        set before [dict get $results mcp_metrics_before]
        set after [dict get $results mcp_metrics_after]

        # Key metrics to show (use list command to avoid TCL 9 brace issues)
        set interesting_metrics [list \
            "mcp_http_requests_total" \
            "mcp_ssh_sessions_total" \
            "mcp_ssh_commands_total" \
            "mcp_ssh_commands_blocked" \
        ]

        foreach metric $interesting_metrics {
            set before_val 0
            set after_val 0

            if {[dict exists $before $metric]} {
                set before_val [dict get $before $metric]
            }
            if {[dict exists $after $metric]} {
                set after_val [dict get $after $metric]
            }

            set delta [expr {$after_val - $before_val}]
            if {$delta != 0} {
                # Shorten metric name for display
                set short_name $metric
                # Remove mcp_ prefix
                if {[string match "mcp_*" $short_name]} {
                    set short_name [string range $short_name 4 end]
                }
                # Remove labels in braces if present
                set brace_pos [string first "\{" $short_name]
                if {$brace_pos >= 0} {
                    set short_name [string range $short_name 0 [expr {$brace_pos - 1}]]
                }
                lappend lines [format "  %-30s +%d" $short_name $delta]
            }
        }

        if {[llength $lines] == 3} {
            lappend lines "  (no significant changes)"
        }

        return [join $lines "\n"]
    }

    # Generate extrapolation estimates
    proc generate_extrapolation {results} {
        set lines [list]
        lappend lines [string repeat "-" 70]
        lappend lines "EXTRAPOLATION (to 8 CPU / 16GB RAM)"
        lappend lines [string repeat "-" 70]

        # Current test config: 4 cores on MCP VM
        set test_cpus 4
        set target_cpus 8
        set efficiency 0.85

        if {[dict exists $results throughput]} {
            set throughput [dict get $results throughput]
            set measured_rps [dict get $throughput avg_rps]

            set extrapolated_rps [expr {$measured_rps * ($target_cpus / double($test_cpus)) * $efficiency}]

            lappend lines ""
            lappend lines [format "  Measured RPS:      %.1f (on %d cores)" $measured_rps $test_cpus]
            lappend lines [format "  Estimated RPS:     %.1f (on %d cores)" $extrapolated_rps $target_cpus]
            lappend lines [format "  Scaling factor:    %.2fx" [expr {$extrapolated_rps / max(0.1, $measured_rps)}]]
            lappend lines ""

            # Confidence based on assumed CPU utilization
            # In a real implementation, we'd scrape actual CPU metrics
            lappend lines "  Confidence:        MEDIUM (based on linear scaling model)"
            lappend lines "  Assumptions:       CPU-bound workload, 85% scaling efficiency"
        } else {
            lappend lines "  (insufficient data for extrapolation)"
        }

        return [join $lines "\n"]
    }

    # Center text in field
    proc center {text width} {
        set len [string length $text]
        set pad [expr {($width - $len) / 2}]
        return [format "%*s%s" $pad "" $text]
    }

    # Print report to stdout
    proc print {results} {
        puts [generate $results]
    }

    # Save report to file
    proc save {results filepath} {
        set fh [open $filepath w]
        puts $fh [generate $results]
        close $fh
    }
}

package provide loadtest::output::report 1.0
