# mcp/lib/session.tcl - SSH Session Management
#
# Tracks active SSH sessions and their state.

package require Tcl 8.6-

namespace eval ::mcp::session {
    # Session storage: session_id -> session_data dict
    variable sessions [dict create]

    # Session data structure:
    # {
    #   spawn_id      <expect spawn_id>
    #   host          "192.168.1.100"
    #   user          "admin"
    #   is_root       0|1
    #   created_at    <epoch ms>
    #   last_used_at  <epoch ms>
    #   mcp_session   "mcp_xxx"
    #   in_use        0|1
    #   sudo_at       0|<epoch when sudo'd>
    # }

    variable max_sessions 50
    variable session_timeout 1800000  ;# 30 min in ms

    #=========================================================================
    # Session CRUD (Lines 30-80)
    #=========================================================================

    # Create new session
    # @param spawn_id    The expect spawn_id for this SSH connection
    # @param host        Target host
    # @param user        SSH username
    # @param mcp_session_id  The MCP session this SSH session belongs to
    # @return session_id
    proc create {spawn_id host user mcp_session_id} {
        variable sessions
        variable max_sessions

        # Check limit
        if {[count] >= $max_sessions} {
            error "SESSION: Maximum session limit ($max_sessions) reached"
        }

        set session_id [::mcp::util::generate_id "sess"]
        set now [clock milliseconds]

        set session_data [dict create \
            spawn_id      $spawn_id \
            host          $host \
            user          $user \
            is_root       0 \
            created_at    $now \
            last_used_at  $now \
            mcp_session   $mcp_session_id \
            in_use        0 \
            sudo_at       0 \
        ]

        dict set sessions $session_id $session_data

        _log_info "Session created" [dict create \
            session_id $session_id \
            host $host \
            user $user \
        ]

        return $session_id
    }

    # Get session by ID
    # @param session_id
    # @return session_data dict, or empty dict if not found
    proc get {session_id} {
        variable sessions

        if {[dict exists $sessions $session_id]} {
            return [dict get $sessions $session_id]
        }
        return {}
    }

    # Update session fields
    # @param session_id
    # @param fields  Dict of fields to update
    proc update {session_id fields} {
        variable sessions

        if {![dict exists $sessions $session_id]} {
            error "SESSION: Session not found: $session_id"
        }

        set current [dict get $sessions $session_id]
        dict for {k v} $fields {
            dict set current $k $v
        }
        dict set sessions $session_id $current

        _log_debug "Session updated" [dict create \
            session_id $session_id \
            fields [dict keys $fields] \
        ]
    }

    # Delete session
    # @param session_id
    proc delete {session_id} {
        variable sessions

        if {[dict exists $sessions $session_id]} {
            set data [dict get $sessions $session_id]
            dict unset sessions $session_id

            _log_info "Session deleted" [dict create \
                session_id $session_id \
                host [dict get $data host] \
            ]
        }
    }

    #=========================================================================
    # Session Queries (Lines 85-120)
    #=========================================================================

    # List all session IDs
    # @return list of session_ids
    proc list_all {} {
        variable sessions
        return [dict keys $sessions]
    }

    # List sessions for a specific MCP session
    # @param mcp_session_id
    # @return list of session_ids
    proc list_by_mcp_session {mcp_session_id} {
        variable sessions

        set result [list]
        dict for {session_id data} $sessions {
            if {[dict get $data mcp_session] eq $mcp_session_id} {
                lappend result $session_id
            }
        }
        return $result
    }

    # Find idle sessions for a specific host/user
    # @param host
    # @param user
    # @return list of session_ids that are idle
    proc find_idle {host user} {
        variable sessions

        set result [list]
        dict for {session_id data} $sessions {
            if {[dict get $data host] eq $host && \
                [dict get $data user] eq $user && \
                [dict get $data in_use] == 0} {
                lappend result $session_id
            }
        }
        return $result
    }

    # Count active sessions
    # @return count
    proc count {} {
        variable sessions
        return [dict size $sessions]
    }

    # Count sessions by host
    # @param host
    # @return count
    proc count_by_host {host} {
        variable sessions

        set n 0
        dict for {session_id data} $sessions {
            if {[dict get $data host] eq $host} {
                incr n
            }
        }
        return $n
    }

    #=========================================================================
    # Session Lifecycle (Lines 125-160)
    #=========================================================================

    # Mark session as in-use
    # @param session_id
    proc acquire {session_id} {
        variable sessions

        if {![dict exists $sessions $session_id]} {
            error "SESSION: Session not found: $session_id"
        }

        set data [dict get $sessions $session_id]
        if {[dict get $data in_use]} {
            error "SESSION: Session already in use: $session_id"
        }

        dict set data in_use 1
        dict set data last_used_at [clock milliseconds]
        dict set sessions $session_id $data

        _log_debug "Session acquired" [dict create session_id $session_id]
    }

    # Release session back to pool
    # @param session_id
    proc release {session_id} {
        variable sessions

        if {![dict exists $sessions $session_id]} {
            return
        }

        set data [dict get $sessions $session_id]
        dict set data in_use 0
        dict set data last_used_at [clock milliseconds]
        dict set sessions $session_id $data

        _log_debug "Session released" [dict create session_id $session_id]
    }

    # Check if session limit reached
    # @return 1 if at limit, 0 otherwise
    proc at_limit {} {
        variable max_sessions
        return [expr {[count] >= $max_sessions}]
    }

    #=========================================================================
    # Cleanup (Lines 165-180)
    #=========================================================================

    # Remove expired sessions
    # @return list of expired session_ids that were removed
    proc cleanup_expired {} {
        variable sessions
        variable session_timeout

        set now [clock milliseconds]
        set expired [list]

        dict for {session_id data} $sessions {
            set last_used [dict get $data last_used_at]
            set age [expr {$now - $last_used}]

            if {$age > $session_timeout && [dict get $data in_use] == 0} {
                lappend expired $session_id
            }
        }

        foreach session_id $expired {
            delete $session_id
        }

        if {[llength $expired] > 0} {
            _log_info "Cleaned up expired sessions" [dict create count [llength $expired]]
        }

        return $expired
    }

    # Reset all sessions (for testing)
    proc reset {} {
        variable sessions
        set sessions [dict create]
    }

    #=========================================================================
    # Helper Functions
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
}

package provide mcp::session 1.0
