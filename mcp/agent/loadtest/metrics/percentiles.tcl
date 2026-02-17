# mcp/agent/loadtest/metrics/percentiles.tcl - Statistical calculations
#
# Provides percentile calculations and statistical aggregation
# for load test results.

package require Tcl 9.0-

namespace eval ::loadtest::stats {
    # Calculate percentile from sorted list
    # @param sorted_list  Pre-sorted list of values
    # @param percentile   Percentile (0-100)
    # @return value at percentile
    proc percentile {sorted_list percentile} {
        set n [llength $sorted_list]
        if {$n == 0} {
            return 0
        }
        if {$n == 1} {
            return [lindex $sorted_list 0]
        }

        # Calculate index using nearest-rank method
        set rank [expr {($percentile / 100.0) * ($n - 1)}]
        set lower_idx [expr {int($rank)}]
        set upper_idx [expr {min($lower_idx + 1, $n - 1)}]
        set frac [expr {$rank - $lower_idx}]

        set lower_val [lindex $sorted_list $lower_idx]
        set upper_val [lindex $sorted_list $upper_idx]

        return [expr {$lower_val + $frac * ($upper_val - $lower_val)}]
    }

    # Calculate multiple percentiles at once
    # @param values  List of values (will be sorted)
    # @param pcts    List of percentiles to calculate
    # @return dict of percentile -> value
    proc percentiles {values pcts} {
        if {[llength $values] == 0} {
            set result [dict create]
            foreach p $pcts {
                dict set result p$p 0
            }
            return $result
        }

        set sorted [lsort -real $values]
        set result [dict create]

        foreach p $pcts {
            dict set result p$p [percentile $sorted $p]
        }

        return $result
    }

    # Calculate full statistics
    # @param values  List of numeric values
    # @return dict with count, min, max, avg, sum, p50, p95, p99
    proc calculate {values} {
        set n [llength $values]

        if {$n == 0} {
            return [dict create \
                count 0 \
                min 0 \
                max 0 \
                avg 0 \
                sum 0 \
                p50 0 \
                p95 0 \
                p99 0 \
            ]
        }

        set sorted [lsort -real $values]
        set sum 0.0
        foreach v $values {
            set sum [expr {$sum + $v}]
        }

        return [dict create \
            count $n \
            min [lindex $sorted 0] \
            max [lindex $sorted end] \
            avg [expr {$sum / $n}] \
            sum $sum \
            p50 [percentile $sorted 50] \
            p95 [percentile $sorted 95] \
            p99 [percentile $sorted 99] \
        ]
    }

    # Calculate throughput (requests per second) over time windows
    # @param timestamps  List of request timestamps (epoch ms)
    # @param window_ms   Window size in milliseconds
    # @return dict with avg_rps, peak_rps, windows
    proc throughput {timestamps window_ms} {
        if {[llength $timestamps] < 2} {
            return [dict create avg_rps 0 peak_rps 0 windows {}]
        }

        set sorted [lsort -integer $timestamps]
        set start_ts [lindex $sorted 0]
        set end_ts [lindex $sorted end]
        set total_duration_ms [expr {$end_ts - $start_ts}]

        if {$total_duration_ms <= 0} {
            return [dict create avg_rps 0 peak_rps 0 windows {}]
        }

        # Calculate per-window counts
        set windows [list]
        set window_start $start_ts
        set peak_count 0

        while {$window_start < $end_ts} {
            set window_end [expr {$window_start + $window_ms}]
            set count 0

            foreach ts $sorted {
                if {$ts >= $window_start && $ts < $window_end} {
                    incr count
                }
            }

            lappend windows [dict create \
                start $window_start \
                end $window_end \
                count $count \
                rps [expr {$count * 1000.0 / $window_ms}] \
            ]

            if {$count > $peak_count} {
                set peak_count $count
            }

            set window_start $window_end
        }

        set total_requests [llength $timestamps]
        set avg_rps [expr {$total_requests * 1000.0 / $total_duration_ms}]
        set peak_rps [expr {$peak_count * 1000.0 / $window_ms}]

        return [dict create \
            avg_rps $avg_rps \
            peak_rps $peak_rps \
            total_requests $total_requests \
            duration_ms $total_duration_ms \
            windows $windows \
        ]
    }

    # Merge statistics from multiple sources
    # @param stats_list  List of stats dicts (from calculate)
    # @return merged stats dict
    proc merge {stats_list} {
        if {[llength $stats_list] == 0} {
            return [calculate {}]
        }

        if {[llength $stats_list] == 1} {
            return [lindex $stats_list 0]
        }

        # Collect all values for proper percentile calculation
        # Note: This is approximate since we don't have raw values
        set total_count 0
        set total_sum 0.0
        set global_min ""
        set global_max ""

        foreach s $stats_list {
            set count [dict get $s count]
            if {$count == 0} continue

            incr total_count $count
            set total_sum [expr {$total_sum + [dict get $s sum]}]

            set smin [dict get $s min]
            set smax [dict get $s max]

            if {$global_min eq "" || $smin < $global_min} {
                set global_min $smin
            }
            if {$global_max eq "" || $smax > $global_max} {
                set global_max $smax
            }
        }

        if {$total_count == 0} {
            return [calculate {}]
        }

        # Approximate percentiles using weighted average
        set p50_sum 0.0
        set p95_sum 0.0
        set p99_sum 0.0
        set weight_sum 0

        foreach s $stats_list {
            set count [dict get $s count]
            if {$count == 0} continue

            set p50_sum [expr {$p50_sum + [dict get $s p50] * $count}]
            set p95_sum [expr {$p95_sum + [dict get $s p95] * $count}]
            set p99_sum [expr {$p99_sum + [dict get $s p99] * $count}]
            incr weight_sum $count
        }

        return [dict create \
            count $total_count \
            min $global_min \
            max $global_max \
            avg [expr {$total_sum / $total_count}] \
            sum $total_sum \
            p50 [expr {$p50_sum / $weight_sum}] \
            p95 [expr {$p95_sum / $weight_sum}] \
            p99 [expr {$p99_sum / $weight_sum}] \
        ]
    }

    # Format duration in human-readable form
    proc format_duration_ms {ms} {
        if {$ms < 1} {
            return [format "%.3fms" $ms]
        } elseif {$ms < 1000} {
            return [format "%.1fms" $ms]
        } elseif {$ms < 60000} {
            return [format "%.2fs" [expr {$ms / 1000.0}]]
        } else {
            set mins [expr {int($ms / 60000)}]
            set secs [expr {($ms % 60000) / 1000.0}]
            return [format "%dm%.1fs" $mins $secs]
        }
    }
}

package provide loadtest::stats 1.0
