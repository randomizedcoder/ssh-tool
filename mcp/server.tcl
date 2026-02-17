#!/usr/bin/env expect
# server.tcl - MCP SSH Automation Server
#
# Usage: ./server.tcl [--port PORT] [--bind ADDR] [--debug LEVEL]

package require Tcl 8.6-
package require Expect

# Get script directory
set script_dir [file dirname [info script]]

# Source all library modules
source [file join $script_dir "lib/util.tcl"]
source [file join $script_dir "lib/log.tcl"]
source [file join $script_dir "lib/metrics.tcl"]
source [file join $script_dir "lib/security.tcl"]
source [file join $script_dir "lib/session.tcl"]
source [file join $script_dir "lib/mcp_session.tcl"]
source [file join $script_dir "lib/pool.tcl"]
source [file join $script_dir "lib/jsonrpc.tcl"]
source [file join $script_dir "lib/router.tcl"]
source [file join $script_dir "lib/tools.tcl"]
source [file join $script_dir "lib/http.tcl"]
source [file join $script_dir "lib/lifecycle.tcl"]

# Source existing SSH automation libs
set project_root [file dirname $script_dir]
source [file join $project_root "lib/common/debug.tcl"]
source [file join $project_root "lib/common/prompt.tcl"]
source [file join $project_root "lib/connection/ssh.tcl"]

#=============================================================================
# Configuration
#=============================================================================

namespace eval ::mcp::server {
    variable config [dict create \
        port        3000 \
        bind        "127.0.0.1" \
        debug_level "INFO" \
    ]

    #=========================================================================
    # Argument Parsing
    #=========================================================================

    proc parse_args {argv} {
        variable config

        set i 0
        while {$i < [llength $argv]} {
            set arg [lindex $argv $i]

            switch -glob -- $arg {
                "--port" {
                    incr i
                    dict set config port [lindex $argv $i]
                }
                "--bind" {
                    incr i
                    dict set config bind [lindex $argv $i]
                }
                "--debug" {
                    incr i
                    dict set config debug_level [lindex $argv $i]
                }
                "-h" - "--help" {
                    puts "Usage: server.tcl \[OPTIONS\]"
                    puts ""
                    puts "Options:"
                    puts "  --port PORT    Port to listen on (default: 3000)"
                    puts "  --bind ADDR    Address to bind to (default: 127.0.0.1)"
                    puts "  --debug LEVEL  Log level: ERROR, WARN, INFO, DEBUG (default: INFO)"
                    puts "  -h, --help     Show this help"
                    exit 0
                }
                default {
                    puts stderr "Unknown option: $arg"
                    exit 1
                }
            }

            incr i
        }
    }

    #=========================================================================
    # Server Startup
    #=========================================================================

    proc start {} {
        variable config

        set port [dict get $config port]
        set bind [dict get $config bind]
        set debug_level [dict get $config debug_level]

        # Initialize logging
        ::mcp::log::init $debug_level

        ::mcp::log::info "Starting MCP SSH Automation Server" [dict create \
            version "1.0.0" \
            port $port \
            bind $bind \
        ]

        # Initialize router with standard handlers
        ::mcp::router::init

        # Start HTTP server
        if {[catch {
            ::mcp::http::start $port $bind
        } err]} {
            ::mcp::log::error "Failed to start HTTP server" [dict create error $err]
            exit 1
        }

        # Start connection pool maintenance
        ::mcp::pool::start

        # Initialize lifecycle manager (zombie reaper, etc.)
        ::mcp::lifecycle::init

        ::mcp::log::info "Server ready" [dict create \
            endpoints [list "/" "/mcp" "/health" "/metrics"] \
        ]

        puts "MCP SSH Server listening on http://${bind}:${port}"
        puts "Endpoints:"
        puts "  POST /      - JSON-RPC (MCP protocol)"
        puts "  POST /mcp   - JSON-RPC (MCP protocol)"
        puts "  GET /health - Health check"
        puts "  GET /metrics - Prometheus metrics"
        puts ""
        puts "Press Ctrl+C to stop"

        # Enter event loop
        ::mcp::http::serve_forever
    }

    #=========================================================================
    # Signal Handling
    #=========================================================================

    proc shutdown {{reason "signal"}} {
        # Use lifecycle manager for graceful shutdown
        ::mcp::lifecycle::shutdown $reason
        exit 0
    }
}

#=============================================================================
# Main
#=============================================================================

# Parse command line arguments
::mcp::server::parse_args $argv

# Set up signal handlers
trap {::mcp::server::shutdown "SIGINT"} SIGINT
trap {::mcp::server::shutdown "SIGTERM"} SIGTERM

# Start server
::mcp::server::start
