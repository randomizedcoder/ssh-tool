# mcp/agent/json.tcl - JSON Parser and Encoder for TCL 9
#
# Simple recursive descent JSON parser and encoder.
# No external dependencies.
#

package require Tcl 9.0-

namespace eval ::agent::json {
    #=========================================================================
    # JSON Parser
    #=========================================================================

    variable _str ""
    variable _pos 0

    proc decode {json_str} {
        variable _str
        variable _pos

        set _str $json_str
        set _pos 0

        _skip_ws
        set result [_parse_value]
        _skip_ws

        if {$_pos < [string length $_str]} {
            error "Unexpected characters after JSON value at position $_pos"
        }

        return $result
    }

    proc _skip_ws {} {
        variable _str
        variable _pos

        while {$_pos < [string length $_str]} {
            set c [string index $_str $_pos]
            if {$c ne " " && $c ne "\t" && $c ne "\n" && $c ne "\r"} {
                break
            }
            incr _pos
        }
    }

    proc _peek {} {
        variable _str
        variable _pos

        if {$_pos >= [string length $_str]} {
            return ""
        }
        return [string index $_str $_pos]
    }

    proc _consume {expected} {
        variable _pos

        set c [_peek]
        if {$c ne $expected} {
            error "Expected '$expected', got '$c' at position $_pos"
        }
        incr _pos
        return $c
    }

    proc _parse_value {} {
        _skip_ws
        set c [_peek]

        switch $c {
            "\{" { return [_parse_object] }
            "\[" { return [_parse_array] }
            "\"" { return [_parse_string] }
            "t"  { return [_parse_literal "true" "true"] }
            "f"  { return [_parse_literal "false" "false"] }
            "n"  { return [_parse_literal "null" "null"] }
            default {
                if {$c eq "-" || [string is digit $c]} {
                    return [_parse_number]
                }
                variable _pos
                error "Unexpected character '$c' at position $_pos"
            }
        }
    }

    proc _parse_object {} {
        variable _pos

        _consume "\{"
        _skip_ws

        set result [dict create]

        if {[_peek] eq "\}"} {
            incr _pos
            return $result
        }

        while {1} {
            _skip_ws
            set key [_parse_string]
            _skip_ws
            _consume ":"
            _skip_ws
            set value [_parse_value]
            dict set result $key $value
            _skip_ws

            set c [_peek]
            if {$c eq "\}"} {
                incr _pos
                break
            }
            _consume ","
        }

        return $result
    }

    proc _parse_array {} {
        variable _pos

        _consume "\["
        _skip_ws

        set result [list]

        if {[_peek] eq "\]"} {
            incr _pos
            return $result
        }

        while {1} {
            _skip_ws
            lappend result [_parse_value]
            _skip_ws

            set c [_peek]
            if {$c eq "\]"} {
                incr _pos
                break
            }
            _consume ","
        }

        return $result
    }

    proc _parse_string {} {
        variable _str
        variable _pos

        _consume "\""

        set result ""
        while {1} {
            set c [_peek]
            if {$c eq ""} {
                error "Unterminated string"
            }
            if {$c eq "\""} {
                incr _pos
                break
            }
            if {$c eq "\\"} {
                incr _pos
                set escape [_peek]
                incr _pos
                switch $escape {
                    "n" { append result "\n" }
                    "r" { append result "\r" }
                    "t" { append result "\t" }
                    "\"" { append result "\"" }
                    "\\" { append result "\\" }
                    "/" { append result "/" }
                    "b" { append result "\b" }
                    "f" { append result "\f" }
                    "u" {
                        set hex [string range $_str $_pos [expr {$_pos + 3}]]
                        incr _pos 4
                        append result [format %c 0x$hex]
                    }
                    default { append result $escape }
                }
            } else {
                append result $c
                incr _pos
            }
        }

        return $result
    }

    proc _parse_number {} {
        variable _str
        variable _pos

        set start $_pos

        # Optional minus
        if {[_peek] eq "-"} {
            incr _pos
        }

        # Digits
        while {[string is digit [_peek]]} {
            incr _pos
        }

        # Optional decimal
        if {[_peek] eq "."} {
            incr _pos
            while {[string is digit [_peek]]} {
                incr _pos
            }
        }

        # Optional exponent
        set c [_peek]
        if {$c eq "e" || $c eq "E"} {
            incr _pos
            set c [_peek]
            if {$c eq "+" || $c eq "-"} {
                incr _pos
            }
            while {[string is digit [_peek]]} {
                incr _pos
            }
        }

        return [string range $_str $start [expr {$_pos - 1}]]
    }

    proc _parse_literal {expected value} {
        variable _str
        variable _pos

        set len [string length $expected]
        set actual [string range $_str $_pos [expr {$_pos + $len - 1}]]

        if {$actual ne $expected} {
            error "Expected '$expected', got '$actual'"
        }

        incr _pos $len
        return $value
    }

    #=========================================================================
    # JSON Encoder
    #=========================================================================

    proc encode {value} {
        # Null
        if {$value eq "null"} {
            return "null"
        }

        # Empty dict
        if {$value eq {} || $value eq "{}"} {
            return "\{\}"
        }

        # Boolean
        if {$value eq "true"} {
            return "true"
        }
        if {$value eq "false"} {
            return "false"
        }

        # Number
        if {[string is double -strict $value]} {
            return $value
        }

        # Try as dict (even number of elements)
        if {[llength $value] > 1 && [llength $value] % 2 == 0} {
            if {[catch {dict keys $value}] == 0} {
                return [_encode_object $value]
            }
        }

        # Try as list (multiple elements)
        if {[llength $value] > 1} {
            return [_encode_array $value]
        }

        # String
        return "\"[_escape_string $value]\""
    }

    proc _encode_object {d} {
        set pairs [list]
        dict for {k v} $d {
            set key_json "\"[_escape_string $k]\""
            set val_json [encode $v]
            lappend pairs "$key_json:$val_json"
        }
        return "\{[join $pairs ","]\}"
    }

    proc _encode_array {lst} {
        set items [list]
        foreach item $lst {
            lappend items [encode $item]
        }
        return "\[[join $items ","]\]"
    }

    proc _escape_string {str} {
        set result ""
        foreach char [split $str ""] {
            switch $char {
                "\\" { append result "\\\\" }
                "\"" { append result "\\\"" }
                "\n" { append result "\\n" }
                "\r" { append result "\\r" }
                "\t" { append result "\\t" }
                "\b" { append result "\\b" }
                "\f" { append result "\\f" }
                default {
                    scan $char %c code
                    if {$code < 32} {
                        append result [format "\\u%04x" $code]
                    } else {
                        append result $char
                    }
                }
            }
        }
        return $result
    }
}

package provide agent::json 1.0
