# mcp/lib/async.tcl - Async/Future Primitives
#
# Provides future/promise abstractions for async thread pool operations.
# Integrates with Tcl's event loop for non-blocking waits.
#
# NOTE: With the current synchronous thread::send approach, this module
# is primarily used for timeout handling and future extensibility to
# thread::send -async patterns.

package require Tcl 8.6-

namespace eval ::mcp::async {
    # Active futures: future_id -> {status result callbacks}
    variable futures [dict create]

    # Auto-incrementing future ID
    variable future_counter 0

    # Default timeout for await operations (ms)
    variable default_timeout 30000

    #=========================================================================
    # Future Creation and Management (Lines 25-80)
    #=========================================================================

    # Create a new future for async result tracking
    # @return future_id
    proc create_future {} {
        variable futures
        variable future_counter

        set fid "future_[incr future_counter]"

        dict set futures $fid [dict create \
            status pending \
            result {} \
            callbacks [list] \
            created_at [clock milliseconds] \
        ]

        return $fid
    }

    # Complete a future with a result
    # @param fid Future ID
    # @param result The result value
    proc complete_future {fid result} {
        variable futures

        if {![dict exists $futures $fid]} {
            _log_warn "Attempt to complete non-existent future" [dict create future_id $fid]
            return
        }

        set future [dict get $futures $fid]

        # Update status and result
        dict set futures $fid status completed
        dict set futures $fid result $result
        dict set futures $fid completed_at [clock milliseconds]

        # Invoke callbacks
        set callbacks [dict get $future callbacks]
        foreach cb $callbacks {
            after 0 [list {*}$cb $result]
        }

        _log_debug "Future completed" [dict create \
            future_id $fid \
            duration_ms [expr {[clock milliseconds] - [dict get $future created_at]}] \
        ]
    }

    # Complete a future with an error
    # @param fid Future ID
    # @param error_msg Error message
    proc fail_future {fid error_msg} {
        variable futures

        if {![dict exists $futures $fid]} {
            return
        }

        dict set futures $fid status failed
        dict set futures $fid result [dict create error $error_msg]
        dict set futures $fid completed_at [clock milliseconds]

        # Invoke callbacks with error
        set future [dict get $futures $fid]
        set callbacks [dict get $future callbacks]
        foreach cb $callbacks {
            after 0 [list {*}$cb [dict create error $error_msg]]
        }
    }

    # Add a callback to be invoked when future completes
    # @param fid Future ID
    # @param callback Command prefix to invoke with result
    proc on_complete {fid callback} {
        variable futures

        if {![dict exists $futures $fid]} {
            return
        }

        set future [dict get $futures $fid]
        set status [dict get $future status]

        if {$status eq "pending"} {
            # Future still pending, add callback
            set callbacks [dict get $future callbacks]
            lappend callbacks $callback
            dict set futures $fid callbacks $callbacks
        } else {
            # Future already completed, invoke callback immediately
            set result [dict get $future result]
            after 0 [list {*}$callback $result]
        }
    }

    #=========================================================================
    # Await Operations (Lines 85-150)
    #=========================================================================

    # Wait for a future to complete (blocking with event loop pumping)
    # @param fid Future ID
    # @param timeout_ms Timeout in milliseconds (0 = use default)
    # @return Result value
    # @throws error on timeout
    proc await {fid {timeout_ms 0}} {
        variable futures
        variable default_timeout

        if {![dict exists $futures $fid]} {
            error "ASYNC: Future not found: $fid"
        }

        if {$timeout_ms <= 0} {
            set timeout_ms $default_timeout
        }

        set deadline [expr {[clock milliseconds] + $timeout_ms}]
        set poll_interval 10

        while {1} {
            # Check if completed
            if {![dict exists $futures $fid]} {
                error "ASYNC: Future was deleted: $fid"
            }

            set future [dict get $futures $fid]
            set status [dict get $future status]

            if {$status ne "pending"} {
                # Completed or failed
                set result [dict get $future result]

                # Cleanup
                dict unset futures $fid

                if {$status eq "failed"} {
                    error "ASYNC: Future failed: [dict get $result error]"
                }

                return $result
            }

            # Check timeout
            if {[clock milliseconds] > $deadline} {
                # Timeout - cleanup and throw
                dict unset futures $fid
                error "ASYNC: Future timeout after ${timeout_ms}ms"
            }

            # Pump event loop
            update
            after $poll_interval
        }
    }

    # Wait for multiple futures to complete
    # @param fids List of future IDs
    # @param timeout_ms Timeout in milliseconds
    # @return List of results in same order as fids
    proc await_all {fids {timeout_ms 0}} {
        variable futures
        variable default_timeout

        if {$timeout_ms <= 0} {
            set timeout_ms $default_timeout
        }

        set deadline [expr {[clock milliseconds] + $timeout_ms}]
        set poll_interval 10
        set results [list]

        while {1} {
            set all_done 1

            foreach fid $fids {
                if {![dict exists $futures $fid]} {
                    continue
                }

                set future [dict get $futures $fid]
                set status [dict get $future status]

                if {$status eq "pending"} {
                    set all_done 0
                    break
                }
            }

            if {$all_done} {
                # Collect results
                foreach fid $fids {
                    if {[dict exists $futures $fid]} {
                        set future [dict get $futures $fid]
                        lappend results [dict get $future result]
                        dict unset futures $fid
                    } else {
                        lappend results [dict create error "Future not found"]
                    }
                }
                return $results
            }

            # Check timeout
            if {[clock milliseconds] > $deadline} {
                # Cleanup remaining futures
                foreach fid $fids {
                    catch {dict unset futures $fid}
                }
                error "ASYNC: await_all timeout after ${timeout_ms}ms"
            }

            # Pump event loop
            update
            after $poll_interval
        }
    }

    #=========================================================================
    # Utility Functions (Lines 155-200)
    #=========================================================================

    # Check if a future is pending
    # @param fid Future ID
    # @return 1 if pending, 0 otherwise
    proc is_pending {fid} {
        variable futures

        if {![dict exists $futures $fid]} {
            return 0
        }

        set future [dict get $futures $fid]
        return [expr {[dict get $future status] eq "pending"}]
    }

    # Get future status
    # @param fid Future ID
    # @return Status string: pending, completed, failed, or unknown
    proc get_status {fid} {
        variable futures

        if {![dict exists $futures $fid]} {
            return "unknown"
        }

        set future [dict get $futures $fid]
        return [dict get $future status]
    }

    # Cancel a pending future
    # @param fid Future ID
    proc cancel {fid} {
        variable futures

        if {[dict exists $futures $fid]} {
            dict unset futures $fid
            _log_debug "Future cancelled" [dict create future_id $fid]
        }
    }

    # Cleanup old pending futures (housekeeping)
    # @param max_age_ms Maximum age for pending futures
    # @return Number of cleaned up futures
    proc cleanup {max_age_ms} {
        variable futures

        set now [clock milliseconds]
        set expired [list]

        dict for {fid future} $futures {
            set created [dict get $future created_at]
            set age [expr {$now - $created}]

            if {$age > $max_age_ms} {
                lappend expired $fid
            }
        }

        foreach fid $expired {
            dict unset futures $fid
        }

        if {[llength $expired] > 0} {
            _log_debug "Cleaned up expired futures" [dict create count [llength $expired]]
        }

        return [llength $expired]
    }

    # Get statistics
    proc get_stats {} {
        variable futures
        variable future_counter

        set pending 0
        set completed 0
        set failed 0

        dict for {fid future} $futures {
            switch [dict get $future status] {
                "pending"   { incr pending }
                "completed" { incr completed }
                "failed"    { incr failed }
            }
        }

        return [dict create \
            total_created $future_counter \
            active [dict size $futures] \
            pending $pending \
            completed $completed \
            failed $failed \
        ]
    }

    # Reset state (for testing)
    proc reset {} {
        variable futures
        variable future_counter

        set futures [dict create]
        set future_counter 0
    }

    #=========================================================================
    # Logging Helpers
    #=========================================================================

    proc _log_debug {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::debug $msg $data
        }
    }

    proc _log_warn {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::warn $msg $data
        }
    }
}

package provide mcp::async 1.0
