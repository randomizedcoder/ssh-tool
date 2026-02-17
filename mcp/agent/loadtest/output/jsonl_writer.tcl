# mcp/agent/loadtest/output/jsonl_writer.tcl - JSONL output writer
#
# Writes load test results in JSON Lines format for easy parsing.

package require Tcl 9.0-

namespace eval ::loadtest::output::jsonl {
    variable file_handle ""
    variable file_path ""

    # Open output file
    # @param path  File path to write to
    proc open_file {path} {
        variable file_handle
        variable file_path

        set file_path $path
        set dir [file dirname $path]
        if {![file exists $dir]} {
            file mkdir $dir
        }

        set file_handle [open $path w]
        fconfigure $file_handle -buffering line
    }

    # Close output file
    proc close_file {} {
        variable file_handle
        if {$file_handle ne ""} {
            close $file_handle
            set file_handle ""
        }
    }

    # Write a single record
    # @param record  Dict to write as JSON
    proc write {record} {
        variable file_handle
        if {$file_handle eq ""} {
            error "JSONL file not open"
        }

        puts $file_handle [dict_to_json $record]
    }

    # Write request result
    # @param worker_id  Worker identifier
    # @param operation  Operation type (ssh_connect, ssh_run_command, etc.)
    # @param latency_ms Latency in milliseconds
    # @param status     success or error
    # @param error_msg  Error message (optional)
    proc write_request {worker_id operation latency_ms status {error_msg ""}} {
        set record [dict create \
            ts [clock milliseconds] \
            worker $worker_id \
            op $operation \
            latency_ms $latency_ms \
            status $status \
        ]

        if {$error_msg ne ""} {
            dict set record error $error_msg
        }

        write $record
    }

    # Write periodic aggregate
    # @param stats  Stats dict from ::loadtest::stats::calculate
    proc write_aggregate {window_start requests errors stats} {
        set record [dict create \
            ts $window_start \
            type "aggregate" \
            requests $requests \
            errors $errors \
            p50_ms [dict get $stats p50] \
            p95_ms [dict get $stats p95] \
            p99_ms [dict get $stats p99] \
        ]

        write $record
    }

    # Convert dict to JSON string
    # Simple implementation - handles strings, numbers, lists, dicts
    proc dict_to_json {d} {
        set pairs [list]

        dict for {k v} $d {
            set json_key "\"$k\""

            if {[string is double -strict $v]} {
                # Number
                set json_val $v
            } elseif {[string is boolean -strict $v]} {
                # Boolean
                set json_val [expr {$v ? "true" : "false"}]
            } elseif {[llength $v] > 1 && ![string match "{*}" $v]} {
                # List
                set items [list]
                foreach item $v {
                    if {[string is double -strict $item]} {
                        lappend items $item
                    } else {
                        lappend items "\"[escape_json_string $item]\""
                    }
                }
                set json_val "\[[join $items ","]\]"
            } elseif {[catch {dict size $v}] == 0 && [dict size $v] > 0} {
                # Nested dict
                set json_val [dict_to_json $v]
            } else {
                # String
                set json_val "\"[escape_json_string $v]\""
            }

            lappend pairs "${json_key}:${json_val}"
        }

        return "\{[join $pairs ","]\}"
    }

    # Escape special characters in JSON string
    proc escape_json_string {s} {
        set s [string map {
            "\\" "\\\\"
            "\"" "\\\""
            "\n" "\\n"
            "\r" "\\r"
            "\t" "\\t"
        } $s]
        return $s
    }

    # Read JSONL file and return list of dicts
    # @param path  File path to read
    # @return list of dicts
    proc read_file {path} {
        set results [list]

        set fh [open $path r]
        while {[gets $fh line] >= 0} {
            if {[string trim $line] eq ""} continue
            # Use the agent's json parser if available
            if {[namespace exists ::agent::json]} {
                lappend results [::agent::json::parse $line]
            } else {
                # Simple fallback - just store as string
                lappend results $line
            }
        }
        close $fh

        return $results
    }
}

package provide loadtest::output::jsonl 1.0
