# mcp/lib/router.tcl - MCP Method Router
#
# Routes MCP methods to handlers.

package require Tcl 8.6

namespace eval ::mcp::router {
    # Method registry: method_name -> handler_proc
    variable handlers [dict create]

    # Server capabilities and info
    variable server_info [dict create \
        name "ssh-mcp-server" \
        version "1.0.0" \
    ]

    variable server_capabilities [dict create \
        tools [dict create] \
    ]

    #=========================================================================
    # Registration (Lines 20-40)
    #=========================================================================

    # Register method handler
    # @param method   Method name (e.g., "tools/list")
    # @param handler  Proc to call (takes params, mcp_session_id)
    proc register {method handler} {
        variable handlers
        dict set handlers $method $handler

        if {[namespace exists ::mcp::log]} {
            ::mcp::log::debug "Method registered" [dict create method $method]
        }
    }

    # Unregister method
    # @param method  Method name
    proc unregister {method} {
        variable handlers
        if {[dict exists $handlers $method]} {
            dict unset handlers $method
        }
    }

    # Check if method is registered
    # @param method  Method name
    # @return 1 if registered, 0 otherwise
    proc has_method {method} {
        variable handlers
        return [dict exists $handlers $method]
    }

    # List registered methods
    # @return list of method names
    proc list_methods {} {
        variable handlers
        return [dict keys $handlers]
    }

    #=========================================================================
    # Dispatch (Lines 45-100)
    #=========================================================================

    # Dispatch request to handler
    # @param request        Parsed JSON-RPC request dict
    # @param mcp_session_id MCP session ID
    # @return JSON-RPC response string
    proc dispatch {request mcp_session_id} {
        variable handlers

        set id [::mcp::jsonrpc::get_id $request]
        set method [dict get $request method]
        set params [::mcp::jsonrpc::get_params $request]

        # Log request
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::debug "Dispatching request" [dict create \
                method $method \
                mcp_session_id $mcp_session_id \
            ]
        }

        # Check if method exists
        if {![dict exists $handlers $method]} {
            return [::mcp::jsonrpc::error_response $id \
                $::mcp::jsonrpc::ERROR_METHOD \
                "Method not found: $method"]
        }

        # Dispatch to handler
        return [_safe_dispatch $id $method $params $mcp_session_id]
    }

    # Safe dispatch with error handling
    proc _safe_dispatch {id method params mcp_session_id} {
        variable handlers

        set handler [dict get $handlers $method]

        if {[catch {
            set result [$handler $params $mcp_session_id]
        } err]} {
            # Check if error is a structured error dict
            if {[catch {dict get $err code}] == 0} {
                set code [dict get $err code]
                set message [dict get $err message]
                set data [expr {[dict exists $err data] ? [dict get $err data] : {}}]
                return [::mcp::jsonrpc::error_response $id $code $message $data]
            }

            # Generic error
            if {[namespace exists ::mcp::log]} {
                ::mcp::log::error "Handler error" [dict create \
                    method $method \
                    error $err \
                ]
            }

            return [::mcp::jsonrpc::error_response $id \
                $::mcp::jsonrpc::ERROR_INTERNAL \
                "Internal error: $err"]
        }

        return [::mcp::jsonrpc::success $id $result]
    }

    #=========================================================================
    # Standard Handlers (Lines 105-180)
    #=========================================================================

    # Initialize handler
    # Called when client connects
    proc _handle_initialize {params mcp_session_id} {
        variable server_info
        variable server_capabilities

        # Create MCP session if not exists
        if {![::mcp::mcp_session::exists $mcp_session_id]} {
            set client_info [expr {[dict exists $params clientInfo] ? [dict get $params clientInfo] : {}}]
            # Session already exists, just touch it
        }

        ::mcp::mcp_session::touch $mcp_session_id

        return [dict create \
            protocolVersion "2024-11-05" \
            serverInfo $server_info \
            capabilities $server_capabilities \
        ]
    }

    # tools/list handler
    # Returns list of available tools
    proc _handle_tools_list {params mcp_session_id} {
        # Get tool definitions from tools module
        if {[namespace exists ::mcp::tools]} {
            set tools $::mcp::tools::tool_definitions
        } else {
            set tools [list]
        }

        return [dict create tools $tools]
    }

    # tools/call dispatcher
    # Routes to specific tool handler
    proc _handle_tools_call {params mcp_session_id} {
        if {![dict exists $params name]} {
            error [dict create \
                code $::mcp::jsonrpc::ERROR_PARAMS \
                message "Missing required parameter: name" \
            ]
        }

        set tool_name [dict get $params name]
        set tool_args [expr {[dict exists $params arguments] ? [dict get $params arguments] : {}}]

        # Rate limit check
        ::mcp::security::check_rate_limit $mcp_session_id

        # Dispatch to tools module
        if {[namespace exists ::mcp::tools]} {
            return [::mcp::tools::dispatch $tool_name $tool_args $mcp_session_id]
        }

        error [dict create \
            code $::mcp::jsonrpc::ERROR_METHOD \
            message "Tool not found: $tool_name" \
        ]
    }

    # Register standard handlers
    proc init {} {
        register "initialize" ::mcp::router::_handle_initialize
        register "tools/list" ::mcp::router::_handle_tools_list
        register "tools/call" ::mcp::router::_handle_tools_call

        if {[namespace exists ::mcp::log]} {
            ::mcp::log::info "Router initialized" [dict create \
                methods [list_methods] \
            ]
        }
    }
}

package provide mcp::router 1.0
