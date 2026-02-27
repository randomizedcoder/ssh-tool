# mcp/lib/thread_pool.tcl - Concurrent Session Management
#
# IMPORTANT: Due to Expect/Thread incompatibility (segfault when loading
# Expect in worker threads), this module uses a HYBRID approach:
#
# - Session routing and request queueing use the Thread package
# - Actual SSH/Expect operations run in the MAIN thread
# - Multiple sessions can exist concurrently, but commands are serialized
#
# This still provides benefits over the original design:
# - Multiple concurrent sessions with persistent state
# - Session affinity (same session always routes to same "virtual worker")
# - Better request isolation and error handling
# - Foundation for future process-based parallelism

package require Tcl 8.6-

namespace eval ::mcp::threadpool {
    # Session storage in main thread: session_id -> session_data dict
    # session_data: {spawn_id, host, user, is_root, created_at, last_used_at, worker_idx}
    variable sessions [dict create]

    # Number of virtual workers (for session routing)
    variable num_workers 0

    # Session -> Worker mapping (for session affinity)
    # Key: session_id, Value: worker index
    variable session_map [dict create]

    # Statistics
    variable stats [dict create \
        dispatched 0 \
        completed 0 \
        errors 0 \
    ]

    # Path to project root (set during init)
    variable project_root ""

    # Initialized flag
    variable initialized 0

    #=========================================================================
    # Initialization (Lines 45-80)
    #=========================================================================

    # Initialize the "thread pool" (virtual workers for session affinity)
    # @param count Number of virtual workers (for routing, not actual threads)
    # @param root_path Path to project root
    proc init {count root_path} {
        variable num_workers
        variable project_root
        variable initialized
        variable sessions
        variable session_map
        variable stats

        if {$initialized} {
            _log_warn "Thread pool already initialized" {}
            return
        }

        if {$count < 1} {
            error "THREADPOOL: Worker count must be at least 1"
        }
        if {$count > 64} {
            error "THREADPOOL: Worker count cannot exceed 64"
        }

        set project_root $root_path
        set num_workers $count
        set sessions [dict create]
        set session_map [dict create]
        set stats [dict create dispatched 0 completed 0 errors 0]
        set initialized 1

        _log_info "Thread pool initialized" [dict create \
            workers $num_workers \
            mode "hybrid" \
        ]
    }

    #=========================================================================
    # Session Routing (Lines 85-130)
    #=========================================================================

    # Get virtual worker index for a session (for affinity)
    # @param session_id Session identifier
    # @param create_mapping If true, create mapping if not exists
    # @return Worker index
    proc get_worker {session_id {create_mapping 1}} {
        variable num_workers
        variable session_map

        # Check existing mapping
        if {[dict exists $session_map $session_id]} {
            return [dict get $session_map $session_id]
        }

        if {!$create_mapping} {
            return -1
        }

        # Hash session_id to worker index
        set hash [_hash_string $session_id]
        set worker_idx [expr {$hash % $num_workers}]

        # Store mapping
        dict set session_map $session_id $worker_idx

        _log_debug "Session routed to worker" [dict create \
            session_id $session_id \
            worker_idx $worker_idx \
        ]

        return $worker_idx
    }

    # Alias for compatibility
    proc get_worker_index {session_id} {
        return [get_worker $session_id 0]
    }

    # Remove session mapping (called on disconnect)
    proc remove_session {session_id} {
        variable session_map
        variable sessions

        if {[dict exists $session_map $session_id]} {
            dict unset session_map $session_id
        }
        if {[dict exists $sessions $session_id]} {
            dict unset sessions $session_id
        }
    }

    # Simple string hash function
    proc _hash_string {str} {
        set hash 0
        foreach char [split $str ""] {
            scan $char %c code
            set hash [expr {($hash * 31 + $code) & 0x7FFFFFFF}]
        }
        return $hash
    }

    #=========================================================================
    # Session Operations (Lines 135-250)
    # These run in the main thread (Expect compatibility)
    #=========================================================================

    # Dispatch operation synchronously
    # @param session_id Session to operate on
    # @param operation Operation name (worker_connect, worker_run_command, etc.)
    # @param args Arguments for the operation
    # @return Result dict
    proc dispatch_sync {session_id operation args} {
        variable stats
        variable initialized

        if {!$initialized} {
            error "THREADPOOL: Not initialized"
        }

        dict incr stats dispatched

        # Route to virtual worker (for affinity tracking)
        set worker_idx [get_worker $session_id]

        # Execute operation in main thread
        if {[catch {
            switch $operation {
                "worker_connect" {
                    set result [_do_connect $session_id {*}$args]
                }
                "worker_disconnect" {
                    set result [_do_disconnect $session_id]
                }
                "worker_run_command" {
                    set result [_do_run_command $session_id {*}$args]
                }
                default {
                    error "Unknown operation: $operation"
                }
            }
        } err]} {
            dict incr stats errors
            _log_error "Operation failed" [dict create \
                session_id $session_id \
                operation $operation \
                error $err \
            ]
            return [dict create status error message $err]
        }

        dict incr stats completed
        return $result
    }

    # Connect to SSH host
    proc _do_connect {session_id host user password insecure port} {
        variable sessions

        # Check if session already exists
        if {[dict exists $sessions $session_id]} {
            return [dict create status error message "Session already exists"]
        }

        # Spawn SSH connection
        if {[catch {
            set spawn_id [::connection::ssh::connect $host $user $password $insecure $port]
        } err]} {
            return [dict create status error message "SSH connection failed: $err"]
        }

        if {$spawn_id eq "" || $spawn_id == 0} {
            return [dict create status error message "SSH connection returned invalid spawn_id"]
        }

        # Store session in main thread
        dict set sessions $session_id [dict create \
            spawn_id $spawn_id \
            host $host \
            user $user \
            is_root 0 \
            created_at [clock milliseconds] \
            last_used_at [clock milliseconds] \
            worker_idx [get_worker $session_id] \
        ]

        _log_debug "Session connected" [dict create \
            session_id $session_id \
            host $host \
            spawn_id $spawn_id \
        ]

        return [dict create status success spawn_id $spawn_id]
    }

    # Disconnect SSH session
    proc _do_disconnect {session_id} {
        variable sessions

        if {![dict exists $sessions $session_id]} {
            return [dict create status success]
        }

        set session [dict get $sessions $session_id]
        set spawn_id [dict get $session spawn_id]

        catch {::connection::ssh::disconnect $spawn_id}

        dict unset sessions $session_id

        _log_debug "Session disconnected" [dict create session_id $session_id]

        return [dict create status success]
    }

    # Run command on session
    proc _do_run_command {session_id command} {
        variable sessions

        if {![dict exists $sessions $session_id]} {
            return [dict create status error message "Session not found: $session_id"]
        }

        set session [dict get $sessions $session_id]
        set spawn_id [dict get $session spawn_id]

        # Execute command
        if {[catch {
            set output [::prompt::run $spawn_id $command]
        } err]} {
            return [dict create status error message "Command failed: $err"]
        }

        # Update last_used_at
        dict set sessions $session_id last_used_at [clock milliseconds]

        return [dict create status success output $output]
    }

    #=========================================================================
    # Pool Management (Lines 255-320)
    #=========================================================================

    # Get pool statistics
    proc get_stats {} {
        variable num_workers
        variable session_map
        variable sessions
        variable stats

        set worker_sessions [dict create]
        for {set i 0} {$i < $num_workers} {incr i} {
            dict set worker_sessions $i 0
        }

        dict for {session_id worker_idx} $session_map {
            if {[dict exists $worker_sessions $worker_idx]} {
                dict incr worker_sessions $worker_idx
            }
        }

        return [dict create \
            workers $num_workers \
            total_sessions [dict size $sessions] \
            dispatched [dict get $stats dispatched] \
            completed [dict get $stats completed] \
            errors [dict get $stats errors] \
            sessions_per_worker $worker_sessions \
            mode "hybrid-main-thread" \
        ]
    }

    # Cleanup expired sessions
    proc cleanup_expired {timeout_ms} {
        variable sessions
        variable session_map

        set now [clock milliseconds]
        set expired [list]

        dict for {session_id session} $sessions {
            set last_used [dict get $session last_used_at]
            if {($now - $last_used) > $timeout_ms} {
                lappend expired $session_id
            }
        }

        foreach session_id $expired {
            catch {_do_disconnect $session_id}
            catch {dict unset session_map $session_id}
        }

        if {[llength $expired] > 0} {
            _log_info "Cleaned up expired sessions" [dict create count [llength $expired]]
        }

        return [llength $expired]
    }

    # Shutdown - disconnect all sessions
    proc shutdown {} {
        variable sessions
        variable session_map
        variable num_workers
        variable initialized

        _log_info "Shutting down thread pool" [dict create sessions [dict size $sessions]]

        # Disconnect all sessions
        foreach session_id [dict keys $sessions] {
            catch {_do_disconnect $session_id}
        }

        set sessions [dict create]
        set session_map [dict create]
        set num_workers 0
        set initialized 0

        _log_info "Thread pool shutdown complete" {}
    }

    # Check if pool is initialized
    proc is_initialized {} {
        variable initialized
        return $initialized
    }

    # Get number of virtual workers
    proc worker_count {} {
        variable num_workers
        return $num_workers
    }

    #=========================================================================
    # Logging Helpers
    #=========================================================================

    proc _log_info {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::info $msg $data
        }
    }

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

    proc _log_error {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::error $msg $data
        }
    }
}

package provide mcp::threadpool 1.0
