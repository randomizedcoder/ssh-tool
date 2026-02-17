# mcp/agent/mcp_client.tcl - MCP Protocol Client
#
# High-level client for MCP (Model Context Protocol) servers.
# Handles JSON-RPC 2.0 over HTTP with session management.
#

package require Tcl 9.0-

# Load sibling modules
set script_dir [file dirname [info script]]
source [file join $script_dir http_client.tcl]
source [file join $script_dir json.tcl]

namespace eval ::agent::mcp {
    variable session_id ""
    variable base_url ""
    variable request_id 0
    variable debug 0

    # Initialize MCP client
    # @param url  Base URL of MCP server (e.g., http://10.178.0.10:3000)
    proc init {url} {
        variable base_url
        variable session_id
        variable request_id

        set base_url $url
        set session_id ""
        set request_id 0
    }

    # Set debug level
    proc set_debug {level} {
        variable debug
        set debug $level
        ::agent::http::set_debug $level
    }

    # Get next request ID
    proc _next_id {} {
        variable request_id
        incr request_id
        return $request_id
    }

    # Make a JSON-RPC request
    # @param method  RPC method name
    # @param params  Parameters dict (optional)
    # @return Result dict or throws error
    proc _rpc {method {params {}}} {
        variable base_url
        variable session_id
        variable debug

        # Build request
        set req [dict create \
            jsonrpc "2.0" \
            id [_next_id] \
            method $method \
        ]
        if {$params ne {}} {
            dict set req params $params
        }

        set json_body [::agent::json::encode $req]

        if {$debug} {
            puts stderr "MCP REQ: $json_body"
        }

        # Headers
        set headers [dict create]
        if {$session_id ne ""} {
            dict set headers "Mcp-Session-Id" $session_id
        }

        # Send request
        set response [::agent::http::post $base_url $json_body $headers]

        set status [dict get $response status]
        set resp_headers [dict get $response headers]
        set body [dict get $response body]

        if {$debug} {
            puts stderr "MCP RSP ($status): $body"
        }

        # Extract session ID from response
        if {[dict exists $resp_headers "mcp-session-id"]} {
            set session_id [dict get $resp_headers "mcp-session-id"]
        }

        # Check HTTP status
        if {$status != 200} {
            error "HTTP error $status: $body"
        }

        # Parse JSON response
        set result [::agent::json::decode $body]

        # Check for JSON-RPC error
        if {[dict exists $result error]} {
            set err [dict get $result error]
            set code [dict get $err code]
            set msg [dict get $err message]
            error "RPC error $code: $msg"
        }

        # Return result
        if {[dict exists $result result]} {
            return [dict get $result result]
        }
        return {}
    }

    #=========================================================================
    # MCP Protocol Methods
    #=========================================================================

    # Initialize MCP session
    # @return Server info dict
    proc initialize {{client_name "tcl-mcp-agent"} {client_version "1.0.0"}} {
        return [_rpc "initialize" [dict create \
            protocolVersion "2024-11-05" \
            clientInfo [dict create \
                name $client_name \
                version $client_version \
            ] \
        ]]
    }

    # List available tools
    # @return List of tool definitions
    proc tools_list {} {
        set result [_rpc "tools/list"]
        if {[dict exists $result tools]} {
            return [dict get $result tools]
        }
        return {}
    }

    # Call a tool
    # @param name       Tool name
    # @param arguments  Tool arguments dict
    # @return Tool result
    proc tools_call {name arguments} {
        return [_rpc "tools/call" [dict create \
            name $name \
            arguments $arguments \
        ]]
    }

    #=========================================================================
    # SSH Tool Wrappers
    #=========================================================================

    # Connect to SSH host
    # @param host      Hostname/IP
    # @param user      Username
    # @param password  Password
    # @param port      Port (optional, default 22)
    # @return Session info with session_id
    proc ssh_connect {host user password {port 22}} {
        return [tools_call "ssh_connect" [dict create \
            host $host \
            user $user \
            password $password \
            port $port \
        ]]
    }

    # Disconnect SSH session
    # @param ssh_session_id  SSH session ID from ssh_connect
    proc ssh_disconnect {ssh_session_id} {
        return [tools_call "ssh_disconnect" [dict create \
            session_id $ssh_session_id \
        ]]
    }

    # Run command on SSH session
    # @param ssh_session_id  SSH session ID
    # @param command         Command to run
    # @return Command output
    proc ssh_run_command {ssh_session_id command} {
        return [tools_call "ssh_run_command" [dict create \
            session_id $ssh_session_id \
            command $command \
        ]]
    }

    # Read file from SSH session
    # @param ssh_session_id  SSH session ID
    # @param path            File path to read
    # @return File content
    proc ssh_cat_file {ssh_session_id path} {
        return [tools_call "ssh_cat_file" [dict create \
            session_id $ssh_session_id \
            path $path \
        ]]
    }

    # Get hostname from SSH session
    # @param ssh_session_id  SSH session ID
    # @return Hostname
    proc ssh_hostname {ssh_session_id} {
        return [tools_call "ssh_hostname" [dict create \
            session_id $ssh_session_id \
        ]]
    }

    # List active SSH sessions
    proc ssh_list_sessions {} {
        return [tools_call "ssh_list_sessions" {}]
    }

    # Get pool stats
    proc ssh_pool_stats {} {
        return [tools_call "ssh_pool_stats" {}]
    }

    # Generic tool call - for any tool by name
    # @param tool_name  Name of the tool to call
    # @param args       Arguments dict for the tool
    # @return Tool result
    proc call_tool {tool_name args} {
        return [tools_call $tool_name $args]
    }

    #=========================================================================
    # Utility
    #=========================================================================

    # Get current session ID
    proc get_session_id {} {
        variable session_id
        return $session_id
    }

    # Extract text content from MCP tool response
    # @param result  Tool result dict
    # @return Text content string
    proc extract_text {result} {
        if {[dict exists $result content]} {
            set content [dict get $result content]
            if {[llength $content] > 0} {
                set first [lindex $content 0]
                if {[dict exists $first text]} {
                    return [dict get $first text]
                }
            }
        }
        return ""
    }

    # Check if result indicates error
    # @param result  Tool result dict
    # @return 1 if error, 0 otherwise
    proc is_error {result} {
        if {[dict exists $result isError]} {
            return [dict get $result isError]
        }
        return 0
    }
}

package provide agent::mcp 1.0
