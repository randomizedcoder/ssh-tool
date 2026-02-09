# mcp/lib/metrics.tcl - Prometheus metrics
#
# Exposes metrics in Prometheus text format at /metrics endpoint.

package require Tcl 8.6

namespace eval ::mcp::metrics {
    # Storage: dict of metric_name -> {type help value labels_data}
    # labels_data is dict of label_key -> value
    variable gauges   [dict create]
    variable counters [dict create]
    variable histograms [dict create]

    # Histogram buckets (seconds) for command duration
    variable duration_buckets {0.01 0.05 0.1 0.25 0.5 1.0 2.5 5.0 10.0}

    # Line 18-25: Gauge operations
    proc gauge_set {name value {labels {}}} {
        variable gauges
        set key [_make_key $name $labels]
        dict set gauges $key [dict create value $value labels $labels]
    }

    proc gauge_inc {name {delta 1} {labels {}}} {
        variable gauges
        set key [_make_key $name $labels]
        if {[dict exists $gauges $key]} {
            set current [dict get $gauges $key value]
            dict set gauges $key value [expr {$current + $delta}]
        } else {
            dict set gauges $key [dict create value $delta labels $labels]
        }
    }

    proc gauge_dec {name {delta 1} {labels {}}} {
        gauge_inc $name [expr {-$delta}] $labels
    }

    # Line 27-35: Counter operations
    proc counter_inc {name {delta 1} {labels {}}} {
        variable counters
        set key [_make_key $name $labels]
        if {[dict exists $counters $key]} {
            set current [dict get $counters $key value]
            dict set counters $key value [expr {$current + $delta}]
        } else {
            dict set counters $key [dict create value $delta labels $labels]
        }
    }

    # Line 37-55: Histogram operations
    proc histogram_observe {name value {labels {}}} {
        variable histograms
        variable duration_buckets

        set key [_make_key $name $labels]
        if {![dict exists $histograms $key]} {
            # Initialize histogram
            set buckets [dict create]
            foreach bucket $duration_buckets {
                dict set buckets $bucket 0
            }
            dict set buckets "+Inf" 0
            dict set histograms $key [dict create \
                labels $labels \
                buckets $buckets \
                sum 0.0 \
                count 0 \
            ]
        }

        # Update histogram
        set hist [dict get $histograms $key]
        dict set hist sum [expr {[dict get $hist sum] + $value}]
        dict set hist count [expr {[dict get $hist count] + 1}]

        set buckets [dict get $hist buckets]
        foreach bucket $duration_buckets {
            if {$value <= $bucket} {
                dict set buckets $bucket [expr {[dict get $buckets $bucket] + 1}]
            }
        }
        dict set buckets "+Inf" [expr {[dict get $buckets "+Inf"] + 1}]
        dict set hist buckets $buckets

        dict set histograms $key $hist
    }

    # Line 57-90: Prometheus format output
    proc format {} {
        variable gauges
        variable counters
        variable histograms

        set lines [list]

        # Gauges
        dict for {key data} $gauges {
            set name [lindex [split $key "|"] 0]
            set labels [dict get $data labels]
            set value [dict get $data value]
            set label_str [_format_labels $labels]
            if {$label_str ne ""} {
                lappend lines "${name}\{${label_str}\} $value"
            } else {
                lappend lines "$name $value"
            }
        }

        # Counters
        dict for {key data} $counters {
            set name [lindex [split $key "|"] 0]
            set labels [dict get $data labels]
            set value [dict get $data value]
            set label_str [_format_labels $labels]
            if {$label_str ne ""} {
                lappend lines "${name}\{${label_str}\} $value"
            } else {
                lappend lines "$name $value"
            }
        }

        # Histograms
        dict for {key data} $histograms {
            set name [lindex [split $key "|"] 0]
            set labels [dict get $data labels]
            set label_str [_format_labels $labels]

            set buckets [dict get $data buckets]
            dict for {bucket count} $buckets {
                if {$bucket eq "+Inf"} {
                    set le_str "le=\"+Inf\""
                } else {
                    set le_str "le=\"$bucket\""
                }
                if {$label_str ne ""} {
                    lappend lines "${name}_bucket\{${label_str},${le_str}\} $count"
                } else {
                    lappend lines "${name}_bucket\{${le_str}\} $count"
                }
            }

            set sum [dict get $data sum]
            set count [dict get $data count]
            if {$label_str ne ""} {
                lappend lines "${name}_sum\{${label_str}\} $sum"
                lappend lines "${name}_count\{${label_str}\} $count"
            } else {
                lappend lines "${name}_sum $sum"
                lappend lines "${name}_count $count"
            }
        }

        return [join $lines "\n"]
    }

    # Reset all metrics (useful for testing)
    proc reset {} {
        variable gauges
        variable counters
        variable histograms
        set gauges [dict create]
        set counters [dict create]
        set histograms [dict create]
    }

    # Line 92-100: Helper for label formatting
    proc _format_labels {labels} {
        if {$labels eq {} || [llength $labels] == 0} {
            return ""
        }
        set pairs [list]
        dict for {k v} $labels {
            lappend pairs "$k=\"$v\""
        }
        return [join $pairs ","]
    }

    proc _make_key {name labels} {
        if {$labels eq {} || [llength $labels] == 0} {
            return $name
        }
        set sorted_labels [list]
        foreach k [lsort [dict keys $labels]] {
            lappend sorted_labels $k [dict get $labels $k]
        }
        return "${name}|[join $sorted_labels ,]"
    }
}

package provide mcp::metrics 1.0
