# mcp/lib/jsonrpc.tcl - JSON-RPC 2.0 Handler
#
# Parses requests and formats responses per JSON-RPC 2.0 spec.
# Includes built-in JSON parser (no tcllib dependency).

package require Tcl 8.6

namespace eval ::mcp::jsonrpc {
    # JSON-RPC 2.0 error codes
    variable ERROR_PARSE       -32700
    variable ERROR_INVALID_REQ -32600
    variable ERROR_METHOD      -32601
    variable ERROR_PARAMS      -32602
    variable ERROR_INTERNAL    -32603

    #=========================================================================
    # JSON Parser (Lines 15-120)
    # Simple recursive descent parser for JSON
    #=========================================================================

    variable _json_str ""
    variable _json_pos 0

    proc _json_parse {str} {
        variable _json_str
        variable _json_pos

        set _json_str $str
        set _json_pos 0

        _json_skip_ws
        set result [_json_parse_value]
        _json_skip_ws

        if {$_json_pos < [string length $_json_str]} {
            error "Unexpected characters after JSON value"
        }

        return $result
    }

    proc _json_skip_ws {} {
        variable _json_str
        variable _json_pos

        while {$_json_pos < [string length $_json_str]} {
            set c [string index $_json_str $_json_pos]
            if {$c ne " " && $c ne "\t" && $c ne "\n" && $c ne "\r"} {
                break
            }
            incr _json_pos
        }
    }

    proc _json_peek {} {
        variable _json_str
        variable _json_pos

        if {$_json_pos >= [string length $_json_str]} {
            return ""
        }
        return [string index $_json_str $_json_pos]
    }

    proc _json_consume {expected} {
        variable _json_str
        variable _json_pos

        set c [_json_peek]
        if {$c ne $expected} {
            error "Expected '$expected', got '$c' at position $_json_pos"
        }
        incr _json_pos
        return $c
    }

    proc _json_parse_value {} {
        _json_skip_ws
        set c [_json_peek]

        switch $c {
            "\{" { return [_json_parse_object] }
            "\[" { return [_json_parse_array] }
            "\"" { return [_json_parse_string] }
            "t"  { return [_json_parse_literal "true" "true"] }
            "f"  { return [_json_parse_literal "false" "false"] }
            "n"  { return [_json_parse_literal "null" "null"] }
            default {
                if {$c eq "-" || [string is digit $c]} {
                    return [_json_parse_number]
                }
                error "Unexpected character '$c' at position $::mcp::jsonrpc::_json_pos"
            }
        }
    }

    proc _json_parse_object {} {
        variable _json_pos

        _json_consume "\{"
        _json_skip_ws

        set result [dict create]

        if {[_json_peek] eq "\}"} {
            incr _json_pos
            return $result
        }

        while {1} {
            _json_skip_ws
            set key [_json_parse_string]
            _json_skip_ws
            _json_consume ":"
            _json_skip_ws
            set value [_json_parse_value]
            dict set result $key $value
            _json_skip_ws

            set c [_json_peek]
            if {$c eq "\}"} {
                incr _json_pos
                break
            }
            _json_consume ","
        }

        return $result
    }

    proc _json_parse_array {} {
        variable _json_pos

        _json_consume "\["
        _json_skip_ws

        set result [list]

        if {[_json_peek] eq "\]"} {
            incr _json_pos
            return $result
        }

        while {1} {
            _json_skip_ws
            lappend result [_json_parse_value]
            _json_skip_ws

            set c [_json_peek]
            if {$c eq "\]"} {
                incr _json_pos
                break
            }
            _json_consume ","
        }

        return $result
    }

    proc _json_parse_string {} {
        variable _json_str
        variable _json_pos

        _json_consume "\""

        set result ""
        while {1} {
            set c [_json_peek]
            if {$c eq ""} {
                error "Unterminated string"
            }
            if {$c eq "\""} {
                incr _json_pos
                break
            }
            if {$c eq "\\"} {
                incr _json_pos
                set escape [_json_peek]
                incr _json_pos
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
                        set hex [string range $_json_str $_json_pos [expr {$_json_pos + 3}]]
                        incr _json_pos 4
                        append result [format %c 0x$hex]
                    }
                    default { append result $escape }
                }
            } else {
                append result $c
                incr _json_pos
            }
        }

        return $result
    }

    proc _json_parse_number {} {
        variable _json_str
        variable _json_pos

        set start $_json_pos
        set c [_json_peek]

        # Optional minus
        if {$c eq "-"} {
            incr _json_pos
        }

        # Digits
        while {[string is digit [_json_peek]]} {
            incr _json_pos
        }

        # Optional decimal
        if {[_json_peek] eq "."} {
            incr _json_pos
            while {[string is digit [_json_peek]]} {
                incr _json_pos
            }
        }

        # Optional exponent
        set c [_json_peek]
        if {$c eq "e" || $c eq "E"} {
            incr _json_pos
            set c [_json_peek]
            if {$c eq "+" || $c eq "-"} {
                incr _json_pos
            }
            while {[string is digit [_json_peek]]} {
                incr _json_pos
            }
        }

        return [string range $_json_str $start [expr {$_json_pos - 1}]]
    }

    proc _json_parse_literal {expected value} {
        variable _json_str
        variable _json_pos

        set len [string length $expected]
        set actual [string range $_json_str $_json_pos [expr {$_json_pos + $len - 1}]]

        if {$actual ne $expected} {
            error "Expected '$expected', got '$actual'"
        }

        incr _json_pos $len
        return $value
    }

    #=========================================================================
    # Request Parsing (Lines 125-170)
    #=========================================================================

    # Parse JSON-RPC request
    # @param json_str  Raw JSON string
    # @return dict with jsonrpc, id, method, params
    proc parse {json_str} {
        variable ERROR_PARSE

        if {[catch {
            set request [_json_parse $json_str]
        } err]} {
            error [dict create \
                code $ERROR_PARSE \
                message "Parse error" \
                data $err \
            ]
        }

        return $request
    }

    # Validate JSON-RPC structure
    # @param request  Parsed request dict
    # @return 1 if valid, throws error if invalid
    proc validate {request} {
        variable ERROR_INVALID_REQ

        # Must have jsonrpc field
        if {![dict exists $request jsonrpc]} {
            error [dict create \
                code $ERROR_INVALID_REQ \
                message "Invalid Request: missing jsonrpc field" \
            ]
        }

        # Must be version 2.0
        if {[dict get $request jsonrpc] ne "2.0"} {
            error [dict create \
                code $ERROR_INVALID_REQ \
                message "Invalid Request: jsonrpc must be \"2.0\"" \
            ]
        }

        # Must have method field
        if {![dict exists $request method]} {
            error [dict create \
                code $ERROR_INVALID_REQ \
                message "Invalid Request: missing method field" \
            ]
        }

        # Method must be string
        set method [dict get $request method]
        if {$method eq ""} {
            error [dict create \
                code $ERROR_INVALID_REQ \
                message "Invalid Request: method cannot be empty" \
            ]
        }

        return 1
    }

    #=========================================================================
    # Response Formatting (Lines 175-240)
    #=========================================================================

    # Format success response
    # @param id      Request ID (can be null for notifications)
    # @param result  Result value (dict, list, or scalar)
    # @return JSON string
    proc success {id result} {
        set result_json [dict_to_json $result]

        if {$id eq "null" || $id eq ""} {
            set id_json "null"
        } elseif {[string is integer -strict $id]} {
            set id_json $id
        } else {
            set id_json "\"[_escape_string $id]\""
        }

        return "\{\"jsonrpc\":\"2.0\",\"id\":$id_json,\"result\":$result_json\}"
    }

    # Format error response
    # @param id       Request ID
    # @param code     Error code (integer)
    # @param message  Error message
    # @param data     Optional additional data
    # @return JSON string
    proc error_response {id code message {data {}}} {
        if {$id eq "null" || $id eq ""} {
            set id_json "null"
        } elseif {[string is integer -strict $id]} {
            set id_json $id
        } else {
            set id_json "\"[_escape_string $id]\""
        }

        set error_obj "\{\"code\":$code,\"message\":\"[_escape_string $message]\""
        if {$data ne {}} {
            append error_obj ",\"data\":[dict_to_json $data]"
        }
        append error_obj "\}"

        return "\{\"jsonrpc\":\"2.0\",\"id\":$id_json,\"error\":$error_obj\}"
    }

    # Format tool error (isError in result for MCP)
    # @param id      Request ID
    # @param code    Error code
    # @param message Error message
    # @return JSON string with isError=true in content
    proc tool_error {id code message} {
        set result [dict create \
            content [list [dict create type "text" text $message]] \
            isError true \
        ]
        return [success $id $result]
    }

    #=========================================================================
    # JSON Writer (Lines 245-320)
    #=========================================================================

    # Escape string for JSON
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

    # Convert Tcl value to JSON
    # Handles dicts, lists, strings, numbers, booleans, null
    proc dict_to_json {value} {
        # Null
        if {$value eq "null"} {
            return "null"
        }

        # Empty
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

        # Try as dict (even number of elements and valid dict)
        if {[llength $value] > 1 && [llength $value] % 2 == 0} {
            if {[catch {dict keys $value}] == 0} {
                return [_dict_to_json_obj $value]
            }
        }

        # Try as list (multiple elements)
        if {[llength $value] > 1} {
            return [_list_to_json_array $value]
        }

        # String
        return "\"[_escape_string $value]\""
    }

    # Convert dict to JSON object
    proc _dict_to_json_obj {d} {
        set pairs [list]
        dict for {k v} $d {
            set key_json "\"[_escape_string $k]\""
            set val_json [dict_to_json $v]
            lappend pairs "$key_json:$val_json"
        }
        return "\{[join $pairs ","]\}"
    }

    # Convert list to JSON array
    proc _list_to_json_array {lst} {
        set items [list]
        foreach item $lst {
            lappend items [dict_to_json $item]
        }
        return "\[[join $items ","]\]"
    }

    # JSON to dict wrapper with error handling
    # @param json_str  JSON string
    # @return Tcl dict
    proc json_to_dict {json_str} {
        variable ERROR_PARSE

        if {[catch {
            set result [_json_parse $json_str]
        } err]} {
            error [dict create \
                code $ERROR_PARSE \
                message "Failed to parse JSON" \
                data $err \
            ]
        }
        return $result
    }

    # Get request ID safely
    # @param request  Parsed request dict
    # @return id or "null"
    proc get_id {request} {
        if {[dict exists $request id]} {
            return [dict get $request id]
        }
        return "null"
    }

    # Get params safely
    # @param request  Parsed request dict
    # @return params dict or empty dict
    proc get_params {request} {
        if {[dict exists $request params]} {
            return [dict get $request params]
        }
        return {}
    }
}

package provide mcp::jsonrpc 1.0
