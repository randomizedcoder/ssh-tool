# mcp/lib/http.tcl - HTTP Server
#
# Simple HTTP/1.1 server using Tcl's native socket support.
# No tcllib dependency.

package require Tcl 8.6

namespace eval ::mcp::http {
    variable server_socket ""
    variable port 3000
    variable bind_addr "127.0.0.1"
    variable running 0

    # Request handlers by path
    variable routes [dict create]

    #=========================================================================
    # Server Lifecycle (Lines 20-80)
    #=========================================================================

    # Start the HTTP server
    # @param port_num   Port to listen on
    # @param bind_addr  Address to bind to (default: 127.0.0.1)
    proc start {port_num {addr "127.0.0.1"}} {
        variable server_socket
        variable port
        variable bind_addr
        variable running

        set port $port_num
        set bind_addr $addr

        if {$running} {
            error "HTTP server already running"
        }

        # Create server socket
        if {[catch {
            set server_socket [socket -server [namespace code _accept] -myaddr $bind_addr $port]
        } err]} {
            error "Failed to start HTTP server on ${bind_addr}:${port}: $err"
        }

        set running 1

        _log_info "HTTP server started" [dict create \
            address $bind_addr \
            port $port \
        ]

        return $server_socket
    }

    # Stop the HTTP server
    proc stop {} {
        variable server_socket
        variable running

        if {!$running} {
            return
        }

        if {$server_socket ne ""} {
            catch {close $server_socket}
            set server_socket ""
        }

        set running 0

        _log_info "HTTP server stopped" {}
    }

    # Check if server is running
    proc is_running {} {
        variable running
        return $running
    }

    # Enter event loop (blocking)
    proc serve_forever {} {
        variable running

        while {$running} {
            after 100
            update
        }
    }

    #=========================================================================
    # Connection Handler (Lines 85-180)
    #=========================================================================

    # Accept new connection
    proc _accept {chan addr port} {
        fconfigure $chan -translation binary -buffering full -blocking 0
        fileevent $chan readable [list [namespace code _handle_readable] $chan $addr]
    }

    # Handle readable event
    proc _handle_readable {chan addr} {
        if {[catch {
            # Read request
            set request [_read_request $chan]

            if {$request eq ""} {
                # Connection closed or incomplete
                if {[eof $chan]} {
                    close $chan
                }
                return
            }

            # Parse request
            set parsed [_parse_request $request]

            if {$parsed eq ""} {
                _send_error $chan 400 "Bad Request"
                close $chan
                return
            }

            # Handle request
            set response [_dispatch $parsed $addr]

            # Send response
            _send_response $chan $response

            # Close connection (HTTP/1.0 style for simplicity)
            close $chan

        } err]} {
            _log_error "Request handling error" [dict create error $err addr $addr]
            catch {
                _send_error $chan 500 "Internal Server Error"
                close $chan
            }
        }
    }

    # Read complete HTTP request
    proc _read_request {chan} {
        set request ""
        set content_length 0
        set headers_done 0

        # Read headers
        while {[gets $chan line] >= 0} {
            append request "$line\r\n"

            if {$line eq "" || $line eq "\r"} {
                set headers_done 1
                break
            }

            # Check for Content-Length
            if {[regexp -nocase {^Content-Length:\s*(\d+)} $line -> len]} {
                set content_length $len
            }
        }

        if {!$headers_done} {
            return ""
        }

        # Read body if present
        if {$content_length > 0} {
            set body [read $chan $content_length]
            append request $body
        }

        return $request
    }

    # Parse HTTP request
    proc _parse_request {request} {
        # Normalize line endings
        set request [string map {"\r\n" "\n" "\r" "\n"} $request]
        set lines [split $request "\n"]

        if {[llength $lines] < 1} {
            return ""
        }

        # Parse request line
        set request_line [string trim [lindex $lines 0]]
        if {![regexp {^(\w+)\s+(\S+)\s+HTTP/(\d+\.\d+)} $request_line -> method path version]} {
            return ""
        }

        # Parse headers
        set headers [dict create]
        set body_start 0
        for {set i 1} {$i < [llength $lines]} {incr i} {
            set line [string trim [lindex $lines $i]]
            if {$line eq ""} {
                set body_start [expr {$i + 1}]
                break
            }
            if {[regexp {^([^:]+):\s*(.*)$} $line -> name value]} {
                dict set headers [string tolower [string trim $name]] [string trim $value]
            }
        }

        # Get body
        set body ""
        if {$body_start > 0 && $body_start < [llength $lines]} {
            set body [join [lrange $lines $body_start end] "\n"]
        }

        return [dict create \
            method $method \
            path $path \
            version $version \
            headers $headers \
            body $body \
        ]
    }

    #=========================================================================
    # Request Dispatch (Lines 185-260)
    #=========================================================================

    proc _dispatch {request addr} {
        set method [dict get $request method]
        set path [dict get $request path]
        set headers [dict get $request headers]
        set body [dict get $request body]

        # Update metrics
        ::mcp::metrics::counter_inc "mcp_http_requests_total" 1 [list method $method]

        # Route to handler
        switch -glob $path {
            "/health" {
                return [_handle_health $request]
            }
            "/metrics" {
                return [_handle_metrics $request]
            }
            "/" {
                if {$method eq "POST"} {
                    return [_handle_jsonrpc $request $addr]
                } else {
                    return [_make_response 405 "Method Not Allowed" \
                        "text/plain" "Use POST for JSON-RPC requests"]
                }
            }
            "/mcp" {
                if {$method eq "POST"} {
                    return [_handle_jsonrpc $request $addr]
                } else {
                    return [_make_response 405 "Method Not Allowed" \
                        "text/plain" "Use POST for JSON-RPC requests"]
                }
            }
            default {
                return [_make_response 404 "Not Found" \
                    "text/plain" "Endpoint not found: $path"]
            }
        }
    }

    # Health check endpoint
    proc _handle_health {request} {
        set health [dict create \
            status "ok" \
            timestamp [::mcp::util::now_iso] \
            sessions [::mcp::session::count] \
            mcp_sessions [::mcp::mcp_session::count] \
        ]

        set body [::mcp::jsonrpc::dict_to_json $health]
        return [_make_response 200 "OK" "application/json" $body]
    }

    # Metrics endpoint (Prometheus format)
    proc _handle_metrics {request} {
        set metrics [::mcp::metrics::format]
        return [_make_response 200 "OK" "text/plain; charset=utf-8" $metrics]
    }

    # JSON-RPC endpoint
    proc _handle_jsonrpc {request addr} {
        set headers [dict get $request headers]
        set body [dict get $request body]

        # Get or create MCP session
        set mcp_session_id ""
        if {[dict exists $headers "mcp-session-id"]} {
            set mcp_session_id [dict get $headers "mcp-session-id"]
        }

        if {$mcp_session_id eq "" || ![::mcp::mcp_session::exists $mcp_session_id]} {
            # Create new MCP session
            set client_info [dict create \
                name "unknown" \
                address $addr \
            ]
            set mcp_session_id [::mcp::mcp_session::create $client_info]
        } else {
            ::mcp::mcp_session::touch $mcp_session_id
        }

        # Check rate limit
        if {[catch {::mcp::security::check_rate_limit $mcp_session_id} err]} {
            set error_response [::mcp::jsonrpc::error_response "null" 429 "Rate limit exceeded"]
            return [_make_response 429 "Too Many Requests" \
                "application/json" $error_response \
                [list "Retry-After" "60"]]
        }

        # Parse JSON-RPC request
        if {[catch {
            set json_request [::mcp::jsonrpc::parse $body]
        } err]} {
            set error_response [::mcp::jsonrpc::error_response "null" -32700 "Parse error"]
            return [_make_response 200 "OK" "application/json" $error_response]
        }

        # Validate request
        if {[catch {
            ::mcp::jsonrpc::validate $json_request
        } err]} {
            set id [::mcp::jsonrpc::get_id $json_request]
            set error_response [::mcp::jsonrpc::error_response $id -32600 "Invalid Request"]
            return [_make_response 200 "OK" "application/json" $error_response]
        }

        # Dispatch to router
        set response [::mcp::router::dispatch $json_request $mcp_session_id]

        # Add session header to response
        return [_make_response 200 "OK" "application/json" $response \
            [list "Mcp-Session-Id" $mcp_session_id]]
    }

    #=========================================================================
    # Response Helpers (Lines 265-320)
    #=========================================================================

    proc _make_response {status reason content_type body {extra_headers {}}} {
        return [dict create \
            status $status \
            reason $reason \
            content_type $content_type \
            body $body \
            extra_headers $extra_headers \
        ]
    }

    proc _send_response {chan response} {
        set status [dict get $response status]
        set reason [dict get $response reason]
        set content_type [dict get $response content_type]
        set body [dict get $response body]
        set extra_headers [dict get $response extra_headers]

        set body_bytes [encoding convertto utf-8 $body]
        set content_length [string length $body_bytes]

        # Build response
        set http_response "HTTP/1.1 $status $reason\r\n"
        append http_response "Content-Type: $content_type\r\n"
        append http_response "Content-Length: $content_length\r\n"
        append http_response "Connection: close\r\n"
        append http_response "Server: ssh-mcp-server/1.0\r\n"

        # Add extra headers
        foreach {name value} $extra_headers {
            append http_response "$name: $value\r\n"
        }

        append http_response "\r\n"
        append http_response $body

        # Send
        fconfigure $chan -translation binary -buffering full
        puts -nonewline $chan $http_response
        flush $chan
    }

    proc _send_error {chan status message} {
        set response [_make_response $status $message "text/plain" $message]
        _send_response $chan $response
    }

    #=========================================================================
    # Logging Helpers
    #=========================================================================

    proc _log_info {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::info $msg $data
        }
    }

    proc _log_error {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::error $msg $data
        }
    }
}

package provide mcp::http 1.0
