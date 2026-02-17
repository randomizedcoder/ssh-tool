# mcp/agent/loadtest/metrics/collector.tcl - Metrics collector
#
# Scrapes Prometheus metrics from MCP server and parses them.

package require Tcl 9.0-

namespace eval ::loadtest::metrics::collector {
    variable mcp_url ""
    variable snapshots [list]

    # Initialize collector
    proc init {url} {
        variable mcp_url
        variable snapshots

        set mcp_url $url
        set snapshots [list]
    }

    # Scrape metrics from MCP server
    # @return dict of metric_name -> value
    proc scrape {} {
        variable mcp_url

        set url "${mcp_url}/metrics"

        if {[catch {
            set response [::agent::http::get $url]
            set body [dict get $response body]
        } err]} {
            return [dict create _error $err]
        }

        return [parse_prometheus $body]
    }

    # Parse Prometheus text format
    # @param text  Prometheus metrics text
    # @return dict of metric_name -> value
    proc parse_prometheus {text} {
        set metrics [dict create]

        foreach line [split $text "\n"] {
            set line [string trim $line]

            # Skip comments and empty lines
            if {$line eq "" || [string match "#*" $line]} {
                continue
            }

            # Parse metric line
            # Format: metric_name{label1="val1",label2="val2"} value
            # or:     metric_name value
            if {[string first "\{" $line] >= 0} {
                # Has labels
                set brace_start [string first "\{" $line]
                set brace_end [string first "\}" $line]
                if {$brace_end > $brace_start} {
                    set name [string range $line 0 [expr {$brace_start - 1}]]
                    set labels [string range $line [expr {$brace_start + 1}] [expr {$brace_end - 1}]]
                    set rest [string trimleft [string range $line [expr {$brace_end + 1}] end]]
                    if {[string is double -strict $rest]} {
                        dict set metrics "${name}\{${labels}\}" $rest
                    }
                }
            } else {
                # No labels
                set parts [split [string trim $line]]
                if {[llength $parts] == 2} {
                    set name [lindex $parts 0]
                    set value [lindex $parts 1]
                    if {[string is double -strict $value]} {
                        dict set metrics $name $value
                    }
                }
            }
        }

        return $metrics
    }

    # Take a snapshot of current metrics
    # @return snapshot dict with timestamp and metrics
    proc snapshot {} {
        variable snapshots

        set metrics [scrape]
        set snap [dict create \
            timestamp [clock milliseconds] \
            metrics $metrics \
        ]

        lappend snapshots $snap
        return $snap
    }

    # Get all snapshots
    proc get_snapshots {} {
        variable snapshots
        return $snapshots
    }

    # Clear snapshots
    proc clear_snapshots {} {
        variable snapshots
        set snapshots [list]
    }

    # Calculate delta between two snapshots
    # @param before  Earlier snapshot
    # @param after   Later snapshot
    # @return dict of metric_name -> delta
    proc delta {before after} {
        set deltas [dict create]

        set before_metrics [dict get $before metrics]
        set after_metrics [dict get $after metrics]

        # Find all metrics in after
        dict for {name value} $after_metrics {
            if {[dict exists $before_metrics $name]} {
                set before_val [dict get $before_metrics $name]
                set delta [expr {$value - $before_val}]
                if {$delta != 0} {
                    dict set deltas $name $delta
                }
            } else {
                # New metric
                dict set deltas $name $value
            }
        }

        return $deltas
    }

    # Get specific metric value
    # @param metrics  Dict from scrape
    # @param pattern  Metric name or pattern
    # @return value or empty string
    proc get_metric {metrics pattern} {
        # Try exact match first
        if {[dict exists $metrics $pattern]} {
            return [dict get $metrics $pattern]
        }

        # Try glob pattern
        dict for {name value} $metrics {
            if {[string match $pattern $name]} {
                return $value
            }
        }

        return ""
    }

    # Get histogram percentiles from scraped metrics
    # @param metrics  Dict from scrape
    # @param name     Base histogram name (without _bucket suffix)
    # @param labels   Labels to match
    # @return dict with p50, p95, p99 (approximated from buckets)
    proc get_histogram_percentiles {metrics name labels} {
        set label_str [format_labels $labels]

        # Get bucket counts
        set buckets [dict create]
        set total 0

        dict for {metric_name value} $metrics {
            if {[string match "${name}_bucket{*${label_str}*}" $metric_name]} {
                # Extract le value
                if {[regexp {le="([^"]+)"} $metric_name -> le]} {
                    dict set buckets $le $value
                    if {$le eq "+Inf"} {
                        set total $value
                    }
                }
            }
        }

        if {$total == 0} {
            return [dict create p50 0 p95 0 p99 0]
        }

        # Approximate percentiles from buckets
        set bucket_list [list]
        dict for {le count} $buckets {
            if {$le ne "+Inf"} {
                lappend bucket_list [list $le $count]
            }
        }
        set bucket_list [lsort -real -index 0 $bucket_list]

        set p50 [interpolate_percentile $bucket_list $total 0.50]
        set p95 [interpolate_percentile $bucket_list $total 0.95]
        set p99 [interpolate_percentile $bucket_list $total 0.99]

        return [dict create p50 $p50 p95 $p95 p99 $p99]
    }

    # Interpolate percentile from histogram buckets
    proc interpolate_percentile {bucket_list total percentile} {
        set target [expr {$total * $percentile}]

        set prev_le 0
        set prev_count 0

        foreach bucket $bucket_list {
            lassign $bucket le count

            if {$count >= $target} {
                # Linear interpolation between prev and current bucket
                if {$count == $prev_count} {
                    return $le
                }
                set ratio [expr {($target - $prev_count) / double($count - $prev_count)}]
                return [expr {$prev_le + $ratio * ($le - $prev_le)}]
            }

            set prev_le $le
            set prev_count $count
        }

        # Return highest bucket
        return $prev_le
    }

    # Format labels dict as Prometheus label string
    proc format_labels {labels} {
        set pairs [list]
        dict for {k v} $labels {
            lappend pairs "$k=\"$v\""
        }
        return [join $pairs ","]
    }

    # Pretty print metrics
    proc print_metrics {metrics} {
        dict for {name value} $metrics {
            puts [format "%-60s %s" $name $value]
        }
    }
}

package provide loadtest::metrics::collector 1.0
