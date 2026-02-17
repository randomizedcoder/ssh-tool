# mcp/lib/util.tcl - Common utilities
#
# Shared utility functions used across modules.

package require Tcl 8.6-

namespace eval ::mcp::util {
    # Line 10-20: Generate unique IDs
    # Uses /dev/urandom if available, falls back to clock
    proc generate_id {{prefix "id"}} {
        if {[file readable /dev/urandom]} {
            set fh [open /dev/urandom rb]
            set bytes [read $fh 4]
            close $fh
            binary scan $bytes H8 hex
        } else {
            # Fallback to clock + pid
            set hex [format %08x [expr {[clock clicks] ^ [pid]}]]
        }
        return "${prefix}_${hex}"
    }

    # Line 22-35: Timing utilities
    proc now_ms {} {
        return [clock milliseconds]
    }

    proc now_iso {} {
        return [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1]
    }

    # Line 37-50: Dict utilities for performance
    # Returns value from dict if key exists, otherwise returns default
    proc dict_get_default {d key default} {
        if {[dict exists $d $key]} {
            return [dict get $d $key]
        }
        return $default
    }

    # Line 52-60: String utilities
    # Truncate string to maxlen, appending suffix if truncated
    proc truncate {str maxlen {suffix "..."}} {
        if {[string length $str] <= $maxlen} {
            return $str
        }
        set cut_len [expr {$maxlen - [string length $suffix]}]
        if {$cut_len < 0} {
            set cut_len 0
        }
        return "[string range $str 0 [expr {$cut_len - 1}]]$suffix"
    }
}

package provide mcp::util 1.0
