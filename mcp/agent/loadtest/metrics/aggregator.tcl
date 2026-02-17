# mcp/agent/loadtest/metrics/aggregator.tcl - Results aggregator
#
# Combines results from multiple worker output files.

package require Tcl 9.0-

set script_dir [file dirname [info script]]
source [file join $script_dir percentiles.tcl]

namespace eval ::loadtest::metrics::aggregator {
    # Aggregate results from multiple JSONL files
    # @param file_list  List of file paths to aggregate
    # @return aggregated results dict
    proc aggregate_files {file_list} {
        set all_latencies [list]
        set all_timestamps [list]
        set total_requests 0
        set total_errors 0
        set operations [dict create]

        foreach filepath $file_list {
            if {![file exists $filepath]} {
                continue
            }

            set fh [open $filepath r]
            while {[gets $fh line] >= 0} {
                if {[string trim $line] eq ""} continue

                # Parse JSON line (simple extraction)
                set record [parse_jsonl_line $line]

                # Skip aggregate records
                if {[dict exists $record type] && [dict get $record type] eq "aggregate"} {
                    continue
                }

                # Extract data
                if {[dict exists $record ts]} {
                    lappend all_timestamps [dict get $record ts]
                }

                if {[dict exists $record latency_ms]} {
                    set latency [dict get $record latency_ms]
                    lappend all_latencies $latency

                    # Track per-operation stats
                    if {[dict exists $record op]} {
                        set op [dict get $record op]
                        if {![dict exists $operations $op]} {
                            dict set operations $op [dict create latencies [list] count 0 errors 0]
                        }
                        dict lappend operations $op latencies $latency
                        dict incr operations $op count
                    }
                }

                if {[dict exists $record status]} {
                    set status [dict get $record status]
                    incr total_requests
                    if {$status eq "error"} {
                        incr total_errors
                        if {[dict exists $record op]} {
                            set op [dict get $record op]
                            dict incr operations $op errors
                        }
                    }
                }
            }
            close $fh
        }

        # Calculate aggregated stats
        set latency_stats [::loadtest::stats::calculate $all_latencies]
        set throughput_stats [::loadtest::stats::throughput $all_timestamps 1000]

        # Calculate per-operation stats
        set op_stats [dict create]
        dict for {op data} $operations {
            set op_latencies [dict get $data latencies]
            dict set op_stats $op [dict create \
                count [dict get $data count] \
                errors [dict get $data errors] \
                latency [::loadtest::stats::calculate $op_latencies] \
            ]
        }

        return [dict create \
            total_requests $total_requests \
            total_errors $total_errors \
            success_rate [expr {$total_requests > 0 ? (($total_requests - $total_errors) * 100.0 / $total_requests) : 0}] \
            latency $latency_stats \
            throughput $throughput_stats \
            operations $op_stats \
            files_processed [llength $file_list] \
        ]
    }

    # Parse a JSONL line into a dict
    # Simple parser - handles basic JSON
    proc parse_jsonl_line {line} {
        set result [dict create]

        # Remove outer braces
        set line [string trim $line " \t\{\}"]

        # Split by comma, then parse key:value pairs
        # This is a simple parser that handles the formats we generate
        foreach pair [split $line ","] {
            set pair [string trim $pair]
            if {$pair eq ""} continue

            if {[regexp {^"([^"]+)":\s*"([^"]*)"$} $pair -> key value]} {
                # String value
                dict set result $key $value
            } elseif {[regexp {^"([^"]+)":\s*([0-9.e+-]+)$} $pair -> key value]} {
                # Numeric value
                dict set result $key $value
            } elseif {[regexp {^"([^"]+)":\s*(true|false|null)$} $pair -> key value]} {
                # Boolean/null
                dict set result $key $value
            }
        }

        return $result
    }

    # Create time-series from timestamps
    # @param timestamps  List of epoch milliseconds
    # @param bucket_ms   Bucket size in milliseconds
    # @return list of {time count} pairs
    proc time_series {timestamps bucket_ms} {
        if {[llength $timestamps] == 0} {
            return [list]
        }

        set sorted [lsort -integer $timestamps]
        set start [lindex $sorted 0]
        set end [lindex $sorted end]

        set series [list]
        set bucket_start $start

        while {$bucket_start <= $end} {
            set bucket_end [expr {$bucket_start + $bucket_ms}]
            set count 0

            foreach ts $sorted {
                if {$ts >= $bucket_start && $ts < $bucket_end} {
                    incr count
                }
            }

            lappend series [list $bucket_start $count]
            set bucket_start $bucket_end
        }

        return $series
    }

    # Detect performance degradation over time
    # @param timestamps  List of timestamps
    # @param latencies   List of latencies (same order)
    # @param window_ms   Analysis window
    # @return dict with degradation analysis
    proc detect_degradation {timestamps latencies window_ms} {
        if {[llength $timestamps] < 10 || [llength $timestamps] != [llength $latencies]} {
            return [dict create detected 0 message "Insufficient data"]
        }

        # Combine and sort by timestamp
        set combined [list]
        for {set i 0} {$i < [llength $timestamps]} {incr i} {
            lappend combined [list [lindex $timestamps $i] [lindex $latencies $i]]
        }
        set combined [lsort -integer -index 0 $combined]

        # Split into first and last quarters
        set n [llength $combined]
        set quarter [expr {$n / 4}]

        set first_quarter_latencies [list]
        set last_quarter_latencies [list]

        for {set i 0} {$i < $quarter} {incr i} {
            lappend first_quarter_latencies [lindex [lindex $combined $i] 1]
        }
        for {set i [expr {$n - $quarter}]} {$i < $n} {incr i} {
            lappend last_quarter_latencies [lindex [lindex $combined $i] 1]
        }

        # Compare averages
        set first_avg [expr {[tcl::mathop::+ {*}$first_quarter_latencies] / double([llength $first_quarter_latencies])}]
        set last_avg [expr {[tcl::mathop::+ {*}$last_quarter_latencies] / double([llength $last_quarter_latencies])}]

        set increase_pct [expr {($last_avg - $first_avg) * 100.0 / $first_avg}]

        set detected [expr {$increase_pct > 20}]

        return [dict create \
            detected $detected \
            first_quarter_avg $first_avg \
            last_quarter_avg $last_avg \
            increase_percent $increase_pct \
            message [expr {$detected ? "Latency increased by [format %.1f $increase_pct]% over test duration" : "No significant degradation detected"}] \
        ]
    }
}

package provide loadtest::metrics::aggregator 1.0
