# mcp/lib/lifecycle.tcl - Process Lifecycle Management
#
# Handles graceful shutdown, zombie reaping, and process cleanup.

package require Tcl 8.6-

namespace eval ::mcp::lifecycle {
    variable shutting_down 0
    variable grace_period_ms 5000
    variable reaper_timer ""
    variable reaper_interval_ms 5000

    #=========================================================================
    # Initialization (Lines 15-35)
    #=========================================================================

    # Initialize lifecycle management
    # Sets up zombie reaper timer
    proc init {} {
        variable reaper_timer
        variable reaper_interval_ms

        # Start zombie reaper
        start_reaper

        _log_info "Lifecycle manager initialized" {}
    }

    #=========================================================================
    # Shutdown (Lines 40-100)
    #=========================================================================

    # Initiate graceful shutdown
    # @param reason  String describing why shutdown was triggered
    proc shutdown {reason} {
        variable shutting_down
        variable grace_period_ms

        if {$shutting_down} {
            _log_warn "Shutdown already in progress" {}
            return
        }

        set shutting_down 1

        _log_info "Initiating graceful shutdown" [dict create \
            reason $reason \
            grace_period_ms $grace_period_ms \
        ]

        # Phase 1: Stop accepting new connections
        catch {::mcp::http::stop}

        # Phase 2: Wait for in-flight requests to complete
        _log_info "Waiting for in-flight requests" [dict create \
            grace_period_ms $grace_period_ms \
        ]

        # Check every 100ms if all sessions are released
        set deadline [expr {[clock milliseconds] + $grace_period_ms}]
        while {[clock milliseconds] < $deadline} {
            set active [_count_active_sessions]
            if {$active == 0} {
                _log_info "All sessions released" {}
                break
            }
            _log_debug "Waiting for sessions to release" [dict create active $active]
            after 100
            update
        }

        # Phase 3: Force close remaining sessions
        set remaining [_count_active_sessions]
        if {$remaining > 0} {
            _log_warn "Force closing remaining sessions" [dict create count $remaining]
        }

        # Close all SSH sessions
        _close_all_sessions

        # Phase 4: Stop connection pool
        catch {::mcp::pool::stop}

        # Phase 5: Stop reaper
        stop_reaper

        # Phase 6: Final cleanup
        reap_zombies

        _log_info "Shutdown complete" [dict create reason $reason]
    }

    # Check if shutdown is in progress
    proc is_shutting_down {} {
        variable shutting_down
        return $shutting_down
    }

    #=========================================================================
    # Session Management (Lines 105-140)
    #=========================================================================

    # Count sessions currently in use
    proc _count_active_sessions {} {
        set count 0
        foreach sid [::mcp::session::list_all] {
            set session [::mcp::session::get $sid]
            if {$session ne "" && [dict get $session in_use]} {
                incr count
            }
        }
        return $count
    }

    # Close all SSH sessions
    proc _close_all_sessions {} {
        foreach sid [::mcp::session::list_all] {
            set session [::mcp::session::get $sid]
            if {$session ne ""} {
                set spawn_id [dict get $session spawn_id]
                _log_debug "Closing session" [dict create session_id $sid]

                # Close the expect channel
                if {[catch {
                    exp_close -i $spawn_id
                    exp_wait -i $spawn_id
                } err]} {
                    _log_debug "Error closing session" [dict create \
                        session_id $sid \
                        error $err \
                    ]
                }

                # Remove from session tracking
                ::mcp::session::delete $sid
            }
        }
    }

    #=========================================================================
    # Zombie Reaper (Lines 145-200)
    #=========================================================================

    # Start the zombie reaper timer
    proc start_reaper {} {
        variable reaper_timer
        variable reaper_interval_ms

        if {$reaper_timer ne ""} {
            return
        }

        set reaper_timer [after $reaper_interval_ms [namespace code _reaper_tick]]
        _log_debug "Zombie reaper started" [dict create interval_ms $reaper_interval_ms]
    }

    # Stop the zombie reaper timer
    proc stop_reaper {} {
        variable reaper_timer

        if {$reaper_timer ne ""} {
            after cancel $reaper_timer
            set reaper_timer ""
            _log_debug "Zombie reaper stopped" {}
        }
    }

    # Reaper timer callback
    proc _reaper_tick {} {
        variable reaper_timer
        variable reaper_interval_ms
        variable shutting_down

        if {$shutting_down} {
            return
        }

        # Reap any zombies
        reap_zombies

        # Schedule next tick
        set reaper_timer [after $reaper_interval_ms [namespace code _reaper_tick]]
    }

    # Reap zombie processes
    # Uses wait with -nowait to collect terminated child processes
    proc reap_zombies {} {
        set reaped 0

        # Try to reap any zombie processes
        # In Expect, we use exp_wait with -nowait
        while {1} {
            if {[catch {
                set result [wait -nowait -i -1]
            } err]} {
                # No more zombies or error
                break
            }

            if {$result eq ""} {
                # No zombies waiting
                break
            }

            # result is: {spawn_id pid status}
            if {[llength $result] >= 3} {
                set spawn_id [lindex $result 0]
                set pid [lindex $result 1]
                set status [lindex $result 2]

                _log_debug "Reaped zombie process" [dict create \
                    spawn_id $spawn_id \
                    pid $pid \
                    status $status \
                ]
                incr reaped
            } else {
                break
            }
        }

        if {$reaped > 0} {
            _log_debug "Reaped zombie processes" [dict create count $reaped]
        }

        return $reaped
    }

    #=========================================================================
    # Configuration (Lines 205-230)
    #=========================================================================

    # Set grace period for shutdown
    # @param ms  Grace period in milliseconds
    proc set_grace_period {ms} {
        variable grace_period_ms

        if {$ms < 0} {
            error "Grace period must be non-negative"
        }

        set grace_period_ms $ms
        _log_debug "Grace period set" [dict create grace_period_ms $ms]
    }

    # Set reaper interval
    # @param ms  Reaper interval in milliseconds
    proc set_reaper_interval {ms} {
        variable reaper_interval_ms

        if {$ms < 1000} {
            error "Reaper interval must be at least 1000ms"
        }

        set reaper_interval_ms $ms
        _log_debug "Reaper interval set" [dict create reaper_interval_ms $ms]
    }

    #=========================================================================
    # Logging Helpers
    #=========================================================================

    proc _log_info {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::info $msg $data
        }
    }

    proc _log_warn {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::warn $msg $data
        }
    }

    proc _log_debug {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::debug $msg $data
        }
    }

    proc _log_error {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::error $msg $data
        }
    }
}

package provide mcp::lifecycle 1.0
