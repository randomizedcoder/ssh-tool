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
source [file join $script_dir "lib/async.tcl"]
source [file join $script_dir "lib/thread_pool.tcl"]
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
        port            3000 \
        bind            "127.0.0.1" \
        debug_level     "INFO" \
        workers         8 \
        session_timeout 1800000 \
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
                "--workers" {
                    incr i
                    set w [lindex $argv $i]
                    if {![string is integer -strict $w] || $w < 1 || $w > 64} {
                        puts stderr "Invalid worker count: $w (must be 1-64)"
                        exit 1
                    }
                    dict set config workers $w
                }
                "--session-timeout" {
                    incr i
                    set t [lindex $argv $i]
                    if {![string is integer -strict $t] || $t < 60} {
                        puts stderr "Invalid session timeout: $t (must be >= 60 seconds)"
                        exit 1
                    }
                    dict set config session_timeout [expr {$t * 1000}]
                }
                "-h" - "--help" {
                    puts "Usage: server.tcl \[OPTIONS\]"
                    puts ""
                    puts "Options:"
                    puts "  --port PORT           Port to listen on (default: 3000)"
                    puts "  --bind ADDR           Address to bind to (default: 127.0.0.1)"
                    puts "  --debug LEVEL         Log level: ERROR, WARN, INFO, DEBUG (default: INFO)"
                    puts "  --workers N           Number of worker threads (default: 8, max: 64)"
                    puts "  --session-timeout S   Session idle timeout in seconds (default: 1800)"
                    puts "  -h, --help            Show this help"
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
        set workers [dict get $config workers]

        # Initialize logging
        ::mcp::log::init $debug_level

        # Initialize debug module for SSH libs (translate DEBUG -> level 5)
        switch [string toupper $debug_level] {
            "DEBUG" { debug::init 5 }
            "INFO"  { debug::init 3 }
            "WARN"  { debug::init 2 }
            "ERROR" { debug::init 1 }
            default { debug::init 3 }
        }

        ::mcp::log::info "Starting MCP SSH Automation Server" [dict create \
            version "2.0.0" \
            port $port \
            bind $bind \
            workers $workers \
        ]

        # Initialize thread pool for concurrent SSH operations
        if {[catch {
            ::mcp::threadpool::init $workers $::project_root
        } err]} {
            ::mcp::log::error "Failed to initialize thread pool" [dict create error $err]
            exit 1
        }

        ::mcp::log::info "Thread pool initialized" [dict create workers $workers]

        # Initialize router with standard handlers
        ::mcp::router::init

        # Start HTTP server
        if {[catch {
            ::mcp::http::start $port $bind
        } err]} {
            ::mcp::log::error "Failed to start HTTP server" [dict create error $err]
            exit 1
        }

        # Start connection pool maintenance (legacy, kept for session timeout)
        ::mcp::pool::start

        # Initialize lifecycle manager (zombie reaper, etc.)
        ::mcp::lifecycle::init

        # Start thread pool session cleanup timer
        _start_session_cleanup

        ::mcp::log::info "Server ready" [dict create \
            endpoints [list "/" "/mcp" "/health" "/metrics"] \
            workers $workers \
        ]

        puts "MCP SSH Server listening on http://${bind}:${port}"
        puts "Configuration:"
        puts "  Workers:         $workers"
        puts "  Session timeout: [expr {[dict get $config session_timeout] / 1000}]s"
        puts ""
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

    # Session cleanup timer for thread pool
    variable session_cleanup_timer ""

    proc _start_session_cleanup {} {
        variable config
        variable session_cleanup_timer

        set timeout [dict get $config session_timeout]
        set interval 60000  ;# Check every minute

        proc _session_cleanup_tick {} {
            variable config
            variable session_cleanup_timer

            set timeout [dict get $config session_timeout]

            # Cleanup expired sessions in thread pool
            catch {
                ::mcp::threadpool::cleanup_expired $timeout
            }

            # Reschedule
            set session_cleanup_timer [after 60000 [namespace code _session_cleanup_tick]]
        }

        set session_cleanup_timer [after $interval [namespace code _session_cleanup_tick]]
    }

    #=========================================================================
    # Signal Handling
    #=========================================================================

    proc shutdown {{reason "signal"}} {
        variable session_cleanup_timer

        # Cancel cleanup timer
        if {$session_cleanup_timer ne ""} {
            after cancel $session_cleanup_timer
        }

        # Shutdown thread pool
        catch {
            ::mcp::threadpool::shutdown
        }

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
