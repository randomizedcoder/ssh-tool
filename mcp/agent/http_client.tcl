# mcp/agent/http_client.tcl - Simple HTTP Client for TCL 9
#
# Minimal HTTP/1.1 client using raw sockets.
# No external dependencies - pure TCL.
#

package require Tcl 9.0-

namespace eval ::agent::http {
    variable debug 0

    # Set debug level (0=off, 1=on)
    proc set_debug {level} {
        variable debug
        set debug $level
    }

    # Make an HTTP request
    # @param method  HTTP method (GET, POST, etc.)
    # @param url     Full URL (http://host:port/path)
    # @param body    Request body (optional)
    # @param headers Extra headers as dict (optional)
    # @return dict with status, headers, body
    proc request {method url {body ""} {headers {}}} {
        variable debug

        # Parse URL
        if {![regexp {^http://([^:/]+)(?::(\d+))?(/.*)?$} $url -> host port path]} {
            error "Invalid URL: $url"
        }
        if {$port eq ""} { set port 80 }
        if {$path eq ""} { set path "/" }

        if {$debug} {
            puts stderr "HTTP: $method $host:$port$path"
        }

        # Connect
        set sock [socket $host $port]
        fconfigure $sock -translation {auto crlf} -buffering full

        # Build request
        puts $sock "$method $path HTTP/1.1"
        puts $sock "Host: $host:$port"
        puts $sock "Connection: close"
        puts $sock "User-Agent: tcl-mcp-agent/1.0"

        # Content headers for POST
        if {$body ne ""} {
            puts $sock "Content-Type: application/json"
            puts $sock "Content-Length: [string length $body]"
        }

        # Extra headers
        dict for {name value} $headers {
            puts $sock "$name: $value"
        }

        # End headers
        puts $sock ""

        # Send body
        if {$body ne ""} {
            fconfigure $sock -translation binary
            puts -nonewline $sock $body
        }

        flush $sock

        # Read response
        fconfigure $sock -translation {auto lf} -buffering line

        # Status line
        set status_line [gets $sock]
        if {![regexp {^HTTP/\d+\.\d+\s+(\d+)\s+(.*)$} $status_line -> status_code status_msg]} {
            close $sock
            error "Invalid HTTP response: $status_line"
        }

        if {$debug} {
            puts stderr "HTTP: Response $status_code $status_msg"
        }

        # Response headers
        set resp_headers [dict create]
        set content_length 0
        while {[gets $sock line] > 0} {
            if {[regexp {^([^:]+):\s*(.*)$} $line -> name value]} {
                set name_lower [string tolower [string trim $name]]
                dict set resp_headers $name_lower [string trim $value]
                if {$name_lower eq "content-length"} {
                    set content_length $value
                }
            }
        }

        # Response body
        fconfigure $sock -translation binary
        if {$content_length > 0} {
            set resp_body [read $sock $content_length]
        } else {
            # Read until EOF for chunked/unknown length
            set resp_body [read $sock]
        }

        close $sock

        return [dict create \
            status $status_code \
            headers $resp_headers \
            body $resp_body \
        ]
    }

    # Convenience: GET request
    proc get {url {headers {}}} {
        return [request GET $url "" $headers]
    }

    # Convenience: POST request
    proc post {url body {headers {}}} {
        return [request POST $url $body $headers]
    }
}

package provide agent::http 1.0
