# mcp/lib/pool.tcl - SSH Connection Pool
#
# Manages reusable SSH connections for efficiency.
# Uses jittered cleanup to prevent thundering herd.

package require Tcl 8.6-

namespace eval ::mcp::pool {
    # Pool configuration
    variable config [dict create \
        min_connections     1     \
        max_connections     20    \
        spare_connections   5     \
        idle_timeout_ms     1800000 \
        health_check_ms     60000   \
        jitter_percent      10      \
    ]

    # Pool storage: pool_key -> [list of session_ids]
    # pool_key = "user@host"
    variable pools [dict create]

    # Health check timer ID
    variable health_check_timer ""

    # Statistics
    variable stats [dict create \
        hits        0 \
        misses      0 \
        creates     0 \
        expires     0 \
        health_fails 0 \
    ]

    #=========================================================================
    # Pool Operations (Lines 30-100)
    #=========================================================================

    # Acquire connection from pool or create new one
    # @param host      Target host
    # @param user      SSH username
    # @param password  SSH password
    # @param insecure  Skip host key verification (optional)
    # @param mcp_session_id  MCP session to associate with
    # @return session_id
    proc acquire {host user password mcp_session_id {insecure 0}} {
        variable pools
        variable stats
        variable config

        set pool_key [_make_key $host $user]

        # Try to get idle connection from pool
        set session_id [_find_idle $pool_key]

        if {$session_id ne ""} {
            # Found idle connection, mark as in use
            ::mcp::session::acquire $session_id
            dict incr stats hits
            _log_debug "Pool hit" [dict create \
                pool_key $pool_key \
                session_id $session_id \
            ]
            # Emit pool hit metric
            if {[namespace exists ::mcp::metrics]} {
                ::mcp::metrics::pool_hit [list host $host]
            }
            return $session_id
        }

        # No idle connection, check if we can create new one
        set current_count [_pool_size $pool_key]
        set max [dict get $config max_connections]

        if {$current_count >= $max} {
            error "POOL: Maximum connections ($max) reached for $pool_key"
        }

        # Create new connection
        dict incr stats misses
        dict incr stats creates

        # Emit pool miss and create metrics
        if {[namespace exists ::mcp::metrics]} {
            ::mcp::metrics::pool_miss [list host $host]
            ::mcp::metrics::pool_create [list host $host]
        }

        # Use existing SSH module from lib/connection
        set spawn_id [::connection::ssh::connect $host $user $password $insecure]
        if {$spawn_id == 0} {
            error "POOL: SSH connection failed to $host"
        }

        # Initialize prompt
        ::prompt::init $spawn_id 0

        # Create session
        set session_id [::mcp::session::create $spawn_id $host $user $mcp_session_id]
        ::mcp::session::acquire $session_id

        # Add to pool
        _add_to_pool $pool_key $session_id

        _log_info "Pool miss - created new connection" [dict create \
            pool_key $pool_key \
            session_id $session_id \
        ]

        return $session_id
    }

    # Release connection back to pool
    # @param session_id
    proc release {session_id} {
        ::mcp::session::release $session_id
        _log_debug "Connection released to pool" [dict create session_id $session_id]
    }

    # Get pool statistics
    # @param host  Optional host to filter by
    # @return dict of statistics
    proc get_stats {{host ""}} {
        variable pools
        variable stats

        set result [dict create]
        dict set result global $stats

        if {$host ne ""} {
            set pool_key [_find_pool_key_by_host $host]
            if {$pool_key ne ""} {
                dict set result pool [dict create \
                    key $pool_key \
                    total [_pool_size $pool_key] \
                    idle [_idle_count $pool_key] \
                ]
            }
        } else {
            set pool_stats [dict create]
            dict for {pool_key session_list} $pools {
                dict set pool_stats $pool_key [dict create \
                    total [llength $session_list] \
                    idle [_idle_count $pool_key] \
                ]
            }
            dict set result pools $pool_stats
        }

        return $result
    }

    #=========================================================================
    # Pool Maintenance (Lines 105-170)
    #=========================================================================

    # Health check all idle connections
    # Sends a simple command to verify connection is alive
    proc health_check {} {
        variable pools
        variable stats

        set failed [list]

        dict for {pool_key session_list} $pools {
            foreach session_id $session_list {
                set session [::mcp::session::get $session_id]
                if {$session eq {}} {
                    continue
                }

                # Only check idle sessions
                if {[dict get $session in_use]} {
                    continue
                }

                set spawn_id [dict get $session spawn_id]

                # Try a simple command
                if {[catch {
                    ::prompt::run $spawn_id "echo healthcheck"
                } err]} {
                    lappend failed $session_id
                    dict incr stats health_fails
                    _log_warn "Health check failed" [dict create \
                        session_id $session_id \
                        pool_key $pool_key \
                        error $err \
                    ]
                    # Emit health fail metric
                    if {[namespace exists ::mcp::metrics]} {
                        ::mcp::metrics::pool_health_fail
                    }
                }
            }
        }

        # Remove failed sessions
        foreach session_id $failed {
            _remove_from_pool $session_id
            ::mcp::session::delete $session_id
        }

        return [llength $failed]
    }

    # Cleanup expired connections with jitter
    # Jitter prevents all connections from expiring at once
    proc cleanup {} {
        variable pools
        variable stats
        variable config

        set idle_timeout [dict get $config idle_timeout_ms]
        set jitter_pct [dict get $config jitter_percent]
        set now [clock milliseconds]
        set expired [list]

        dict for {pool_key session_list} $pools {
            set min_conns [dict get $config min_connections]
            set idle_count [_idle_count $pool_key]

            foreach session_id $session_list {
                # Keep minimum connections
                if {$idle_count <= $min_conns} {
                    break
                }

                set session [::mcp::session::get $session_id]
                if {$session eq {}} {
                    continue
                }

                # Only cleanup idle sessions
                if {[dict get $session in_use]} {
                    continue
                }

                set last_used [dict get $session last_used_at]
                set age [expr {$now - $last_used}]

                # Apply jitter: timeout +/- jitter_pct
                set jitter [expr {int(rand() * $idle_timeout * $jitter_pct / 100.0 * 2) - ($idle_timeout * $jitter_pct / 100)}]
                set adjusted_timeout [expr {$idle_timeout + $jitter}]

                if {$age > $adjusted_timeout} {
                    lappend expired $session_id
                    incr idle_count -1
                    dict incr stats expires
                    # Emit expire metric
                    if {[namespace exists ::mcp::metrics]} {
                        ::mcp::metrics::pool_expire
                    }
                }
            }
        }

        # Remove expired sessions
        foreach session_id $expired {
            _remove_from_pool $session_id
            ::mcp::session::delete $session_id
        }

        if {[llength $expired] > 0} {
            _log_info "Cleaned up expired pool connections" [dict create count [llength $expired]]
        }

        return [llength $expired]
    }

    # Warmup pool with connections
    # @param host      Target host
    # @param user      SSH username
    # @param password  SSH password
    # @param count     Number of connections to create
    # @param mcp_session_id  MCP session to associate with
    proc warmup {host user password count mcp_session_id {insecure 0}} {
        variable config

        set pool_key [_make_key $host $user]
        set max [dict get $config max_connections]
        set current [_pool_size $pool_key]
        set to_create [expr {min($count, $max - $current)}]

        _log_info "Warming up pool" [dict create \
            pool_key $pool_key \
            requested $count \
            creating $to_create \
        ]

        set created 0
        for {set i 0} {$i < $to_create} {incr i} {
            if {[catch {
                set session_id [acquire $host $user $password $mcp_session_id $insecure]
                release $session_id
                incr created
            } err]} {
                _log_warn "Warmup connection failed" [dict create \
                    pool_key $pool_key \
                    error $err \
                ]
            }
        }

        return $created
    }

    #=========================================================================
    # Pool Helpers (Lines 175-220)
    #=========================================================================

    # Make pool key
    proc _make_key {host user} {
        return "${user}@${host}"
    }

    # Find idle session in pool
    # @return session_id or empty string
    proc _find_idle {pool_key} {
        variable pools

        if {![dict exists $pools $pool_key]} {
            return ""
        }

        set session_list [dict get $pools $pool_key]
        foreach session_id $session_list {
            set session [::mcp::session::get $session_id]
            if {$session ne {} && [dict get $session in_use] == 0} {
                return $session_id
            }
        }

        return ""
    }

    # Add session to pool
    proc _add_to_pool {pool_key session_id} {
        variable pools

        if {![dict exists $pools $pool_key]} {
            dict set pools $pool_key [list]
        }

        set session_list [dict get $pools $pool_key]
        if {$session_id ni $session_list} {
            lappend session_list $session_id
            dict set pools $pool_key $session_list
        }
    }

    # Remove session from pool
    proc _remove_from_pool {session_id} {
        variable pools

        dict for {pool_key session_list} $pools {
            set idx [lsearch -exact $session_list $session_id]
            if {$idx >= 0} {
                set session_list [lreplace $session_list $idx $idx]
                dict set pools $pool_key $session_list
                return
            }
        }
    }

    # Get pool size
    proc _pool_size {pool_key} {
        variable pools

        if {![dict exists $pools $pool_key]} {
            return 0
        }
        return [llength [dict get $pools $pool_key]]
    }

    # Count idle connections in pool
    proc _idle_count {pool_key} {
        variable pools

        if {![dict exists $pools $pool_key]} {
            return 0
        }

        set count 0
        foreach session_id [dict get $pools $pool_key] {
            set session [::mcp::session::get $session_id]
            if {$session ne {} && [dict get $session in_use] == 0} {
                incr count
            }
        }
        return $count
    }

    # Find pool key by host
    proc _find_pool_key_by_host {host} {
        variable pools

        dict for {pool_key session_list} $pools {
            if {[string match "*@${host}" $pool_key]} {
                return $pool_key
            }
        }
        return ""
    }

    #=========================================================================
    # Lifecycle (Lines 225-260)
    #=========================================================================

    # Start health check timer
    proc start {} {
        variable health_check_timer
        variable config

        set interval [dict get $config health_check_ms]

        if {$health_check_timer ne ""} {
            after cancel $health_check_timer
        }

        proc _health_check_loop {} {
            variable health_check_timer
            variable config

            catch {health_check}
            catch {cleanup}

            set interval [dict get $config health_check_ms]
            set health_check_timer [after $interval [namespace code _health_check_loop]]
        }

        set health_check_timer [after $interval [namespace code _health_check_loop]]
        _log_info "Pool health check started" [dict create interval_ms $interval]
    }

    # Stop and drain all pools
    proc stop {} {
        variable pools
        variable health_check_timer

        if {$health_check_timer ne ""} {
            after cancel $health_check_timer
            set health_check_timer ""
        }

        # Close all connections
        dict for {pool_key session_list} $pools {
            foreach session_id $session_list {
                set session [::mcp::session::get $session_id]
                if {$session ne {}} {
                    set spawn_id [dict get $session spawn_id]
                    catch {::connection::ssh::disconnect $spawn_id}
                }
                ::mcp::session::delete $session_id
            }
        }

        set pools [dict create]
        _log_info "Pool stopped and drained" {}
    }

    # Reset pool (for testing)
    proc reset {} {
        variable pools
        variable stats
        variable health_check_timer

        if {$health_check_timer ne ""} {
            after cancel $health_check_timer
            set health_check_timer ""
        }

        set pools [dict create]
        set stats [dict create \
            hits        0 \
            misses      0 \
            creates     0 \
            expires     0 \
            health_fails 0 \
        ]
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

    proc _log_warn {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::warn $msg $data
        }
    }
}

package provide mcp::pool 1.0
