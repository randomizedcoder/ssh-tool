# mcp/lib/mcp_session.tcl - MCP Protocol Session Management
#
# Tracks MCP client sessions (separate from SSH sessions).

package require Tcl 8.6-

namespace eval ::mcp::mcp_session {
    variable sessions [dict create]
    variable timeout 3600000  ;# 1 hour in ms

    # MCP session data:
    # {
    #   created_at    <epoch ms>
    #   last_used_at  <epoch ms>
    #   ssh_sessions  [list of ssh session_ids]
    #   client_info   {name version}
    # }

    #=========================================================================
    # Session CRUD (Lines 20-65)
    #=========================================================================

    # Create new MCP session
    # @param client_info  Dict with client name and version
    # @return mcp_session_id
    proc create {client_info} {
        variable sessions

        set mcp_session_id [::mcp::util::generate_id "mcp"]
        set now [clock milliseconds]

        set session_data [dict create \
            created_at    $now \
            last_used_at  $now \
            ssh_sessions  [list] \
            client_info   $client_info \
        ]

        dict set sessions $mcp_session_id $session_data

        _log_info "MCP session created" [dict create \
            mcp_session_id $mcp_session_id \
            client_info $client_info \
        ]

        return $mcp_session_id
    }

    # Get MCP session
    # @param mcp_session_id
    # @return session_data dict, or empty dict if not found
    proc get {mcp_session_id} {
        variable sessions

        if {[dict exists $sessions $mcp_session_id]} {
            return [dict get $sessions $mcp_session_id]
        }
        return {}
    }

    # Check if MCP session exists
    # @param mcp_session_id
    # @return 1 if exists, 0 otherwise
    proc exists {mcp_session_id} {
        variable sessions
        return [dict exists $sessions $mcp_session_id]
    }

    # Touch (update last_used)
    # @param mcp_session_id
    proc touch {mcp_session_id} {
        variable sessions

        if {[dict exists $sessions $mcp_session_id]} {
            set data [dict get $sessions $mcp_session_id]
            dict set data last_used_at [clock milliseconds]
            dict set sessions $mcp_session_id $data
        }
    }

    #=========================================================================
    # SSH Session Association (Lines 52-75)
    #=========================================================================

    # Associate SSH session with MCP session
    # @param mcp_session_id
    # @param ssh_session_id
    proc add_ssh_session {mcp_session_id ssh_session_id} {
        variable sessions

        if {![dict exists $sessions $mcp_session_id]} {
            error "MCP_SESSION: Session not found: $mcp_session_id"
        }

        set data [dict get $sessions $mcp_session_id]
        set ssh_list [dict get $data ssh_sessions]

        if {$ssh_session_id ni $ssh_list} {
            lappend ssh_list $ssh_session_id
            dict set data ssh_sessions $ssh_list
            dict set sessions $mcp_session_id $data

            _log_debug "SSH session associated" [dict create \
                mcp_session_id $mcp_session_id \
                ssh_session_id $ssh_session_id \
            ]
        }
    }

    # Remove SSH session from MCP session
    # @param mcp_session_id
    # @param ssh_session_id
    proc remove_ssh_session {mcp_session_id ssh_session_id} {
        variable sessions

        if {![dict exists $sessions $mcp_session_id]} {
            return
        }

        set data [dict get $sessions $mcp_session_id]
        set ssh_list [dict get $data ssh_sessions]

        set idx [lsearch -exact $ssh_list $ssh_session_id]
        if {$idx >= 0} {
            set ssh_list [lreplace $ssh_list $idx $idx]
            dict set data ssh_sessions $ssh_list
            dict set sessions $mcp_session_id $data

            _log_debug "SSH session removed" [dict create \
                mcp_session_id $mcp_session_id \
                ssh_session_id $ssh_session_id \
            ]
        }
    }

    # List SSH sessions for MCP session
    # @param mcp_session_id
    # @return list of ssh_session_ids
    proc list_ssh_sessions {mcp_session_id} {
        variable sessions

        if {[dict exists $sessions $mcp_session_id]} {
            return [dict get [dict get $sessions $mcp_session_id] ssh_sessions]
        }
        return [list]
    }

    #=========================================================================
    # Cleanup (Lines 80-100)
    #=========================================================================

    # Cleanup MCP session (closes all SSH sessions)
    # @param mcp_session_id
    proc cleanup {mcp_session_id} {
        variable sessions

        if {![dict exists $sessions $mcp_session_id]} {
            return
        }

        set data [dict get $sessions $mcp_session_id]
        set ssh_list [dict get $data ssh_sessions]

        # Delete all associated SSH sessions
        foreach ssh_session_id $ssh_list {
            if {[namespace exists ::mcp::session]} {
                ::mcp::session::delete $ssh_session_id
            }
        }

        # Delete MCP session
        dict unset sessions $mcp_session_id

        _log_info "MCP session cleaned up" [dict create \
            mcp_session_id $mcp_session_id \
            ssh_sessions_closed [llength $ssh_list] \
        ]
    }

    # Cleanup expired MCP sessions
    # @return list of expired mcp_session_ids that were removed
    proc cleanup_expired {} {
        variable sessions
        variable timeout

        set now [clock milliseconds]
        set expired [list]

        dict for {mcp_session_id data} $sessions {
            set last_used [dict get $data last_used_at]
            set age [expr {$now - $last_used}]

            if {$age > $timeout} {
                lappend expired $mcp_session_id
            }
        }

        foreach mcp_session_id $expired {
            cleanup $mcp_session_id
        }

        if {[llength $expired] > 0} {
            _log_info "Cleaned up expired MCP sessions" [dict create count [llength $expired]]
        }

        return $expired
    }

    # List all MCP session IDs
    # @return list of mcp_session_ids
    proc list_all {} {
        variable sessions
        return [dict keys $sessions]
    }

    # Count active MCP sessions
    # @return count
    proc count {} {
        variable sessions
        return [dict size $sessions]
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

package provide mcp::mcp_session 1.0
