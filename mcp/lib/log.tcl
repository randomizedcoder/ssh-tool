# mcp/lib/log.tcl - Structured JSON logging
#
# Provides machine-parseable logging for production environments.
# All log entries are JSON objects written to stdout.

package require Tcl 8.6

namespace eval ::mcp::log {
    # Log level constants (match syslog)
    variable LEVELS [dict create \
        ERROR   3 \
        WARN    4 \
        INFO    6 \
        DEBUG   7 \
    ]

    variable current_level 6  ;# Default: INFO
    variable output stdout

    # Line 15-25: Initialization
    proc init {level {output_chan stdout}} {
        variable LEVELS
        variable current_level
        variable output

        set output $output_chan

        if {[string is integer -strict $level]} {
            set current_level $level
        } elseif {[dict exists $LEVELS [string toupper $level]]} {
            set current_level [dict get $LEVELS [string toupper $level]]
        } else {
            error "Invalid log level: $level. Use ERROR, WARN, INFO, or DEBUG"
        }
    }

    # Line 27-55: Core emit function
    # @param severity One of: ERROR, WARN, INFO, DEBUG
    # @param message  Human-readable message
    # @param data     Optional dict of structured data
    # @return The JSON string if emitted, empty string if filtered
    proc emit {severity message {data {}}} {
        variable LEVELS
        variable current_level
        variable output

        set sev_upper [string toupper $severity]
        if {![dict exists $LEVELS $sev_upper]} {
            set sev_upper "INFO"
        }

        set sev_level [dict get $LEVELS $sev_upper]

        # Filter by log level
        if {$sev_level > $current_level} {
            return ""
        }

        # Build log entry
        set entry [dict create \
            timestamp [::mcp::util::now_iso] \
            level $sev_upper \
            message $message \
        ]

        # Merge additional data
        if {$data ne {}} {
            dict for {k v} $data {
                dict set entry $k $v
            }
        }

        set json [_to_json $entry]
        puts $output $json
        flush $output

        return $json
    }

    # Line 57-60: Convenience wrappers
    proc error {msg {data {}}} { emit ERROR $msg $data }
    proc warn  {msg {data {}}} { emit WARN  $msg $data }
    proc info  {msg {data {}}} { emit INFO  $msg $data }
    proc debug {msg {data {}}} { emit DEBUG $msg $data }

    # Line 62-75: JSON formatting (minimal, no tcllib dependency here)
    proc _to_json {value} {
        if {[llength $value] == 0} {
            return "null"
        }

        # Check if it's a dict (even number of elements)
        if {[llength $value] % 2 == 0} {
            set pairs [list]
            dict for {k v} $value {
                set escaped_key [_escape_string $k]
                set json_val [_json_value $v]
                lappend pairs "\"$escaped_key\":$json_val"
            }
            return "\{[join $pairs ","]\}"
        }

        # It's a list
        set items [list]
        foreach item $value {
            lappend items [_json_value $item]
        }
        return "\[[join $items ","]\]"
    }

    proc _json_value {v} {
        # Null
        if {$v eq "null"} {
            return "null"
        }
        # Boolean
        if {$v eq "true" || $v eq "false"} {
            return $v
        }
        # Number
        if {[string is double -strict $v] || [string is integer -strict $v]} {
            return $v
        }
        # Dict or list
        if {[llength $v] > 1 && [llength $v] % 2 == 0} {
            # Could be a dict - try it
            if {[catch {dict keys $v}] == 0} {
                return [_to_json $v]
            }
        }
        if {[llength $v] > 1} {
            return [_to_json $v]
        }
        # String
        return "\"[_escape_string $v]\""
    }

    proc _escape_string {str} {
        # JSON string escaping
        set str [string map {
            \\ \\\\
            \" \\\"
            \n \\n
            \r \\r
            \t \\t
            \b \\b
            \f \\f
        } $str]

        # Escape control characters (0x00-0x1F)
        set result ""
        foreach char [split $str ""] {
            scan $char %c code
            if {$code < 32 && $code != 10 && $code != 13 && $code != 9} {
                append result [format "\\u%04x" $code]
            } else {
                append result $char
            }
        }
        return $result
    }
}

package provide mcp::log 1.0
