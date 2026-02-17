# mcp/lib/tools.tcl - MCP Tool Implementations
#
# All tools that LLMs can invoke. Each tool validates inputs
# through the security layer before execution.

package require Tcl 8.6-

namespace eval ::mcp::tools {
    # Tool registry for tools/list
    variable tool_definitions [list]

    # Snapshot cache for network compare
    # Key: session_id, Value: dict of {scope -> {data timestamp}}
    variable network_snapshots [dict create]

    #=========================================================================
    # Tool Definitions (Lines 15-120)
    #=========================================================================

    proc _def_ssh_connect {} {
        return [dict create \
            name "ssh_connect" \
            description "Connect to a remote host via SSH" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    host [dict create type "string" description "Hostname or IP address"] \
                    user [dict create type "string" description "SSH username (optional, defaults to current user)"] \
                    password [dict create type "string" description "SSH password"] \
                    insecure [dict create type "boolean" description "Skip host key verification (for ephemeral VMs)"] \
                ] \
                required [list host password] \
            ] \
        ]
    }

    proc _def_ssh_disconnect {} {
        return [dict create \
            name "ssh_disconnect" \
            description "Disconnect an SSH session" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID to disconnect"] \
                ] \
                required [list session_id] \
            ] \
        ]
    }

    proc _def_ssh_run_command {} {
        return [dict create \
            name "ssh_run_command" \
            description "Run a command on a connected SSH session (security filtered)" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    command [dict create type "string" description "Command to execute (subject to allowlist)"] \
                ] \
                required [list session_id command] \
            ] \
        ]
    }

    proc _def_ssh_run {} {
        return [dict create \
            name "ssh_run" \
            description "Alias for ssh_run_command" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    command [dict create type "string" description "Command to execute"] \
                ] \
                required [list session_id command] \
            ] \
        ]
    }

    proc _def_ssh_cat_file {} {
        return [dict create \
            name "ssh_cat_file" \
            description "Read contents of a file on remote host (path validated)" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    path [dict create type "string" description "File path to read (subject to path validation)"] \
                    encoding [dict create type "string" description "Encoding: auto, text, or base64 (default: auto)"] \
                    max_size [dict create type "integer" description "Maximum bytes to read (default: 1MB)"] \
                ] \
                required [list session_id path] \
            ] \
        ]
    }

    proc _def_ssh_hostname {} {
        return [dict create \
            name "ssh_hostname" \
            description "Get hostname of remote system" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                ] \
                required [list session_id] \
            ] \
        ]
    }

    proc _def_ssh_list_sessions {} {
        return [dict create \
            name "ssh_list_sessions" \
            description "List all active SSH sessions for this client" \
            inputSchema [dict create \
                type "object" \
                properties [dict create] \
            ] \
        ]
    }

    proc _def_ssh_pool_stats {} {
        return [dict create \
            name "ssh_pool_stats" \
            description "Get connection pool statistics" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    host [dict create type "string" description "Optional host to filter stats"] \
                ] \
            ] \
        ]
    }

    #=========================================================================
    # Network Tool Definitions (Lines 131-250)
    # Reference: DESIGN_NETWORK_COMMANDS.md
    #=========================================================================

    proc _def_ssh_network_interfaces {} {
        return [dict create \
            name "ssh_network_interfaces" \
            description "List network interfaces with addresses, state, and statistics" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    interface [dict create type "string" description "Optional: specific interface"] \
                    include_stats [dict create type "boolean" description "Include RX/TX statistics"] \
                ] \
                required [list session_id] \
            ] \
        ]
    }

    proc _def_ssh_network_routes {} {
        return [dict create \
            name "ssh_network_routes" \
            description "Show routing table" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    table [dict create type "string" description "Routing table (main, local, etc.)"] \
                    family [dict create type "string" description "Address family: inet, inet6, or all"] \
                ] \
                required [list session_id] \
            ] \
        ]
    }

    proc _def_ssh_network_firewall {} {
        return [dict create \
            name "ssh_network_firewall" \
            description "Show firewall rules (nftables or iptables)" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    format [dict create type "string" description "Firewall format: nft, iptables, or auto"] \
                    table [dict create type "string" description "Specific table to show"] \
                    summary [dict create type "boolean" description "Return summary instead of full rules"] \
                ] \
                required [list session_id] \
            ] \
        ]
    }

    proc _def_ssh_network_qdisc {} {
        return [dict create \
            name "ssh_network_qdisc" \
            description "Show traffic control qdiscs and classes" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    interface [dict create type "string" description "Specific interface"] \
                    include_stats [dict create type "boolean" description "Include statistics"] \
                ] \
                required [list session_id] \
            ] \
        ]
    }

    proc _def_ssh_network_connectivity {} {
        return [dict create \
            name "ssh_network_connectivity" \
            description "Test network connectivity from target host (ping, DNS, traceroute)" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    target [dict create type "string" description "Hostname or IP to test"] \
                    tests [dict create type "array" description "Tests to run: ping, dns, traceroute"] \
                    ping_count [dict create type "integer" description "Ping packet count (1-5)"] \
                    traceroute_hops [dict create type "integer" description "Max traceroute hops (1-15)"] \
                ] \
                required [list session_id target] \
            ] \
        ]
    }

    proc _def_ssh_batch_commands {} {
        return [dict create \
            name "ssh_batch_commands" \
            description "Execute multiple commands in sequence (max 5, all validated)" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    commands [dict create type "array" description "Commands to execute (max 5)"] \
                    stop_on_error [dict create type "boolean" description "Stop on first error"] \
                ] \
                required [list session_id commands] \
            ] \
        ]
    }

    proc _def_ssh_network_compare {} {
        return [dict create \
            name "ssh_network_compare" \
            description "Compare current network state against a previous snapshot" \
            inputSchema [dict create \
                type "object" \
                properties [dict create \
                    session_id [dict create type "string" description "Session ID"] \
                    scope [dict create type "string" description "Scope: interfaces, routes, or all"] \
                    save_baseline [dict create type "boolean" description "Save current state as baseline"] \
                ] \
                required [list session_id] \
            ] \
        ]
    }

    #=========================================================================
    # Tool Registration (Lines 125-145)
    #=========================================================================

    proc register_all {} {
        variable tool_definitions

        set tool_definitions [list \
            [_def_ssh_connect] \
            [_def_ssh_disconnect] \
            [_def_ssh_run_command] \
            [_def_ssh_run] \
            [_def_ssh_cat_file] \
            [_def_ssh_hostname] \
            [_def_ssh_list_sessions] \
            [_def_ssh_pool_stats] \
            [_def_ssh_network_interfaces] \
            [_def_ssh_network_routes] \
            [_def_ssh_network_firewall] \
            [_def_ssh_network_qdisc] \
            [_def_ssh_network_connectivity] \
            [_def_ssh_batch_commands] \
            [_def_ssh_network_compare] \
        ]
    }

    proc get_definitions {} {
        variable tool_definitions
        return $tool_definitions
    }

    #=========================================================================
    # Tool Dispatcher (Lines 150-180)
    #=========================================================================

    proc dispatch {tool_name args_dict mcp_session_id} {
        switch $tool_name {
            "ssh_connect"       { return [tool_ssh_connect $args_dict $mcp_session_id] }
            "ssh_disconnect"    { return [tool_ssh_disconnect $args_dict $mcp_session_id] }
            "ssh_run_command"   { return [tool_ssh_run_command $args_dict $mcp_session_id] }
            "ssh_run"           { return [tool_ssh_run_command $args_dict $mcp_session_id] }
            "ssh_cat_file"      { return [tool_ssh_cat_file $args_dict $mcp_session_id] }
            "ssh_hostname"      { return [tool_ssh_hostname $args_dict $mcp_session_id] }
            "ssh_list_sessions" { return [tool_ssh_list_sessions $args_dict $mcp_session_id] }
            "ssh_pool_stats"    { return [tool_ssh_pool_stats $args_dict $mcp_session_id] }
            "ssh_network_interfaces" { return [tool_ssh_network_interfaces $args_dict $mcp_session_id] }
            "ssh_network_routes"     { return [tool_ssh_network_routes $args_dict $mcp_session_id] }
            "ssh_network_firewall"   { return [tool_ssh_network_firewall $args_dict $mcp_session_id] }
            "ssh_network_qdisc"      { return [tool_ssh_network_qdisc $args_dict $mcp_session_id] }
            "ssh_network_connectivity" { return [tool_ssh_network_connectivity $args_dict $mcp_session_id] }
            "ssh_batch_commands"     { return [tool_ssh_batch_commands $args_dict $mcp_session_id] }
            "ssh_network_compare"    { return [tool_ssh_network_compare $args_dict $mcp_session_id] }
            default {
                error [dict create \
                    code $::mcp::jsonrpc::ERROR_METHOD \
                    message "Unknown tool: $tool_name" \
                ]
            }
        }
    }

    #=========================================================================
    # ssh_connect (Lines 185-240)
    #=========================================================================

    proc tool_ssh_connect {args mcp_session_id} {
        # Validate required params
        if {![dict exists $args host]} {
            return [_tool_error "Missing required parameter: host"]
        }
        if {![dict exists $args password]} {
            return [_tool_error "Missing required parameter: password"]
        }

        set host [dict get $args host]
        set password [dict get $args password]
        set user [expr {[dict exists $args user] ? [dict get $args user] : $::env(USER)}]
        set insecure [expr {[dict exists $args insecure] ? [dict get $args insecure] : 0}]
        if {$insecure eq "true"} { set insecure 1 }
        if {$insecure eq "false"} { set insecure 0 }

        # Check session limit
        if {[::mcp::session::at_limit]} {
            return [_tool_error "Session limit reached"]
        }

        # Perform SSH connection (uses existing lib)
        if {[catch {
            set spawn_id [::connection::ssh::connect $host $user $password $insecure]
        } err]} {
            return [_tool_error "SSH connection failed: $err"]
        }

        if {$spawn_id == 0} {
            return [_tool_error "SSH connection failed"]
        }

        # Initialize prompt
        ::prompt::init $spawn_id 0

        # Create session
        set session_id [::mcp::session::create $spawn_id $host $user $mcp_session_id]

        # Associate with MCP session
        ::mcp::mcp_session::add_ssh_session $mcp_session_id $session_id

        # Update metrics
        ::mcp::metrics::gauge_inc "mcp_ssh_sessions_active" 1 [list host $host]
        ::mcp::metrics::counter_inc "mcp_ssh_sessions_total" 1 [list host $host status "success"]

        return [dict create \
            content [list [dict create type "text" text "Connected to $host as $user"]] \
            session_id $session_id \
        ]
    }

    #=========================================================================
    # ssh_disconnect (Lines 245-280)
    #=========================================================================

    proc tool_ssh_disconnect {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }

        set session_id [dict get $args session_id]

        # Get session
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }

        # Verify ownership
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        # Get spawn_id and disconnect
        set spawn_id [dict get $session spawn_id]
        set host [dict get $session host]

        catch {::connection::ssh::disconnect $spawn_id}

        # Remove from MCP session
        ::mcp::mcp_session::remove_ssh_session $mcp_session_id $session_id

        # Delete session
        ::mcp::session::delete $session_id

        # Update metrics
        ::mcp::metrics::gauge_dec "mcp_ssh_sessions_active" 1 [list host $host]

        return [dict create \
            content [list [dict create type "text" text "Disconnected from $host"]] \
        ]
    }

    #=========================================================================
    # ssh_run_command (Lines 285-345)
    #=========================================================================

    proc tool_ssh_run_command {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }
        if {![dict exists $args command]} {
            return [_tool_error "Missing required parameter: command"]
        }

        set session_id [dict get $args session_id]
        set command [dict get $args command]

        # Get session
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }

        # Verify ownership
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        # SECURITY: Validate command through allowlist
        if {[catch {::mcp::security::validate_command $command} err]} {
            ::mcp::metrics::counter_inc "mcp_ssh_commands_blocked" 1
            return [_tool_error "Command not permitted: $err"]
        }

        # Get spawn_id and run command
        set spawn_id [dict get $session spawn_id]
        set host [dict get $session host]
        set start_time [clock milliseconds]

        if {[catch {
            set output [::prompt::run $spawn_id $command]
        } err]} {
            return [_tool_error "Command execution failed: $err"]
        }

        set duration [expr {([clock milliseconds] - $start_time) / 1000.0}]
        ::mcp::metrics::histogram_observe "mcp_ssh_command_duration_seconds" $duration \
            [list host $host]
        ::mcp::metrics::counter_inc "mcp_ssh_commands_total" 1 [list host $host status "success"]

        # Update last_used
        ::mcp::session::update $session_id [dict create last_used_at [clock milliseconds]]

        return [dict create \
            content [list [dict create type "text" text $output]] \
        ]
    }

    #=========================================================================
    # ssh_cat_file (Lines 350-420)
    #=========================================================================

    proc tool_ssh_cat_file {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }
        if {![dict exists $args path]} {
            return [_tool_error "Missing required parameter: path"]
        }

        set session_id [dict get $args session_id]
        set path [dict get $args path]
        set encoding [expr {[dict exists $args encoding] ? [dict get $args encoding] : "auto"}]
        set max_size [expr {[dict exists $args max_size] ? [dict get $args max_size] : 1048576}]

        # Get session
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }

        # Verify ownership
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        # SECURITY: Validate path
        if {[catch {
            set normalized_path [::mcp::security::validate_path $path]
        } err]} {
            return [_tool_error "Path not permitted: $err"]
        }

        # Build cat command with proper quoting
        set escaped_path [string map {' '\\''} $normalized_path]
        set cmd "cat '$escaped_path'"

        # SECURITY: Validate the constructed command too
        if {[catch {::mcp::security::validate_command $cmd} err]} {
            return [_tool_error "Command not permitted: $err"]
        }

        # Execute
        set spawn_id [dict get $session spawn_id]

        if {[catch {
            set output [::prompt::run $spawn_id $cmd]
        } err]} {
            return [_tool_error "Failed to read file: $err"]
        }

        # Detect encoding
        set detected_encoding "text"
        if {$encoding eq "auto" || $encoding eq "base64"} {
            if {[_is_binary $output]} {
                set detected_encoding "base64"
                set output [binary encode base64 $output]
            }
        }

        # Truncate if needed
        if {[string length $output] > $max_size} {
            set output [string range $output 0 [expr {$max_size - 1}]]
        }

        return [dict create \
            content [list [dict create type "text" text $output]] \
            encoding $detected_encoding \
            bytes [string length $output] \
            path $normalized_path \
        ]
    }

    #=========================================================================
    # ssh_hostname (Lines 425-460)
    #=========================================================================

    proc tool_ssh_hostname {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }

        set session_id [dict get $args session_id]

        # Get session
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }

        # Verify ownership
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        set spawn_id [dict get $session spawn_id]

        if {[catch {
            set output [::prompt::run $spawn_id "hostname"]
        } err]} {
            return [_tool_error "Failed to get hostname: $err"]
        }

        set hostname [string trim $output]

        return [dict create \
            content [list [dict create type "text" text $hostname]] \
            hostname $hostname \
        ]
    }

    #=========================================================================
    # ssh_list_sessions (Lines 465-495)
    #=========================================================================

    proc tool_ssh_list_sessions {args mcp_session_id} {
        set session_ids [::mcp::mcp_session::list_ssh_sessions $mcp_session_id]

        set sessions [list]
        foreach session_id $session_ids {
            set session [::mcp::session::get $session_id]
            if {$session ne {}} {
                lappend sessions [dict create \
                    session_id $session_id \
                    host [dict get $session host] \
                    user [dict get $session user] \
                    created_at [dict get $session created_at] \
                    in_use [dict get $session in_use] \
                ]
            }
        }

        set text "Active sessions: [llength $sessions]"
        foreach s $sessions {
            append text "\n- [dict get $s session_id]: [dict get $s user]@[dict get $s host]"
        }

        return [dict create \
            content [list [dict create type "text" text $text]] \
            sessions $sessions \
            count [llength $sessions] \
        ]
    }

    #=========================================================================
    # ssh_pool_stats (Lines 500-520)
    #=========================================================================

    proc tool_ssh_pool_stats {args mcp_session_id} {
        set host [expr {[dict exists $args host] ? [dict get $args host] : ""}]

        set stats [::mcp::pool::get_stats $host]

        set text "Pool Statistics:\n"
        append text "Global: [dict get $stats global]\n"
        if {[dict exists $stats pools]} {
            dict for {pool_key pool_stats} [dict get $stats pools] {
                append text "Pool $pool_key: [dict get $pool_stats total] total, [dict get $pool_stats idle] idle\n"
            }
        }

        return [dict create \
            content [list [dict create type "text" text $text]] \
            stats $stats \
        ]
    }

    #=========================================================================
    # ssh_network_interfaces (Lines 530-600)
    #=========================================================================

    proc tool_ssh_network_interfaces {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }

        set session_id [dict get $args session_id]
        set interface [expr {[dict exists $args interface] ? [dict get $args interface] : ""}]
        set include_stats [expr {[dict exists $args include_stats] ? [dict get $args include_stats] : 0}]
        if {$include_stats eq "true"} { set include_stats 1 }

        # Get session and verify ownership
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        set spawn_id [dict get $session spawn_id]

        # Build command
        if {$include_stats} {
            set cmd "ip -j -s link show"
        } else {
            set cmd "ip -j addr show"
        }
        if {$interface ne ""} {
            # Validate interface name (alphanumeric, @, -, _)
            if {![regexp {^[a-zA-Z0-9@_-]+$} $interface]} {
                return [_tool_error "Invalid interface name"]
            }
            append cmd " dev $interface"
        }

        # Validate and execute
        if {[catch {::mcp::security::validate_command $cmd} err]} {
            return [_tool_error "Command not permitted: $err"]
        }

        if {[catch {set output [::prompt::run $spawn_id $cmd]} err]} {
            return [_tool_error "Failed to get interfaces: $err"]
        }

        return [dict create \
            content [list [dict create type "text" text $output]] \
            format "json" \
        ]
    }

    #=========================================================================
    # ssh_network_routes (Lines 605-660)
    #=========================================================================

    proc tool_ssh_network_routes {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }

        set session_id [dict get $args session_id]
        set table [expr {[dict exists $args table] ? [dict get $args table] : "main"}]
        set family [expr {[dict exists $args family] ? [dict get $args family] : "all"}]

        # Get session and verify ownership
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        set spawn_id [dict get $session spawn_id]

        # Build command based on family
        set results [dict create]

        if {$family eq "all" || $family eq "inet"} {
            set cmd "ip -j -4 route show table $table"
            if {[catch {::mcp::security::validate_command $cmd}]} {
                return [_tool_error "Command not permitted"]
            }
            if {[catch {set ipv4_output [::prompt::run $spawn_id $cmd]} err]} {
                dict set results ipv4 [dict create error $err]
            } else {
                dict set results ipv4 $ipv4_output
            }
        }

        if {$family eq "all" || $family eq "inet6"} {
            set cmd "ip -j -6 route show table $table"
            if {[catch {::mcp::security::validate_command $cmd}]} {
                return [_tool_error "Command not permitted"]
            }
            if {[catch {set ipv6_output [::prompt::run $spawn_id $cmd]} err]} {
                dict set results ipv6 [dict create error $err]
            } else {
                dict set results ipv6 $ipv6_output
            }
        }

        # Format text output
        set text "Routing table: $table\n"
        if {[dict exists $results ipv4]} {
            append text "IPv4:\n[dict get $results ipv4]\n"
        }
        if {[dict exists $results ipv6]} {
            append text "IPv6:\n[dict get $results ipv6]\n"
        }

        return [dict create \
            content [list [dict create type "text" text $text]] \
            routes $results \
            table $table \
            format "json" \
        ]
    }

    #=========================================================================
    # ssh_network_firewall (Lines 665-750)
    #=========================================================================

    proc tool_ssh_network_firewall {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }

        set session_id [dict get $args session_id]
        set format [expr {[dict exists $args format] ? [dict get $args format] : "auto"}]
        set table [expr {[dict exists $args table] ? [dict get $args table] : ""}]
        set summary [expr {[dict exists $args summary] ? [dict get $args summary] : 0}]
        if {$summary eq "true"} { set summary 1 }

        # Get session and verify ownership
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        set spawn_id [dict get $session spawn_id]
        set detected_format ""

        # Auto-detect firewall type
        if {$format eq "auto"} {
            # Try nft first
            set test_cmd "nft list tables"
            if {[catch {::mcp::security::validate_command $test_cmd}]} {
                set format "iptables"
            } else {
                if {[catch {set test_output [::prompt::run $spawn_id $test_cmd]}]} {
                    set format "iptables"
                } elseif {[string match "*table*" $test_output]} {
                    set format "nft"
                } else {
                    set format "iptables"
                }
            }
        }

        set detected_format $format

        # Execute appropriate command
        if {$format eq "nft"} {
            if {$table ne ""} {
                set cmd "nft -j list table $table"
            } else {
                set cmd "nft -j list ruleset"
            }
        } else {
            # iptables
            if {$table ne "" && $table in {filter nat mangle raw security}} {
                set cmd "iptables -t $table -L -n -v"
            } else {
                set cmd "iptables -L -n -v"
            }
        }

        if {[catch {::mcp::security::validate_command $cmd} err]} {
            return [_tool_error "Command not permitted: $err"]
        }

        if {[catch {set output [::prompt::run $spawn_id $cmd]} err]} {
            return [_tool_error "Failed to get firewall rules: $err"]
        }

        # Handle large output
        set output [_truncate_large_output $output 65536]

        return [dict create \
            content [list [dict create type "text" text $output]] \
            format $detected_format \
            table $table \
        ]
    }

    #=========================================================================
    # ssh_network_qdisc (Lines 755-810)
    #=========================================================================

    proc tool_ssh_network_qdisc {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }

        set session_id [dict get $args session_id]
        set interface [expr {[dict exists $args interface] ? [dict get $args interface] : ""}]
        set include_stats [expr {[dict exists $args include_stats] ? [dict get $args include_stats] : 0}]
        if {$include_stats eq "true"} { set include_stats 1 }

        # Get session and verify ownership
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        set spawn_id [dict get $session spawn_id]

        # Build command
        if {$include_stats} {
            set cmd "tc -j -s qdisc show"
        } else {
            set cmd "tc -j qdisc show"
        }
        if {$interface ne ""} {
            if {![regexp {^[a-zA-Z0-9@_-]+$} $interface]} {
                return [_tool_error "Invalid interface name"]
            }
            append cmd " dev $interface"
        }

        if {[catch {::mcp::security::validate_command $cmd} err]} {
            return [_tool_error "Command not permitted: $err"]
        }

        if {[catch {set output [::prompt::run $spawn_id $cmd]} err]} {
            return [_tool_error "Failed to get qdisc info: $err"]
        }

        return [dict create \
            content [list [dict create type "text" text $output]] \
            format "json" \
        ]
    }

    #=========================================================================
    # ssh_network_connectivity (Lines 815-910)
    #=========================================================================

    proc tool_ssh_network_connectivity {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }
        if {![dict exists $args target]} {
            return [_tool_error "Missing required parameter: target"]
        }

        set session_id [dict get $args session_id]
        set target [dict get $args target]
        set tests [expr {[dict exists $args tests] ? [dict get $args tests] : [list ping dns]}]
        set ping_count [expr {[dict exists $args ping_count] ? [dict get $args ping_count] : 3}]
        set traceroute_hops [expr {[dict exists $args traceroute_hops] ? [dict get $args traceroute_hops] : 10}]

        # Validate limits
        if {$ping_count < 1 || $ping_count > 5} {
            return [_tool_error "ping_count must be 1-5"]
        }
        if {$traceroute_hops < 1 || $traceroute_hops > 15} {
            return [_tool_error "traceroute_hops must be 1-15"]
        }

        # Validate target (hostname format)
        if {![regexp {^[a-zA-Z0-9][a-zA-Z0-9._-]+$} $target]} {
            return [_tool_error "Invalid target hostname"]
        }

        # Get session and verify ownership
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        set spawn_id [dict get $session spawn_id]
        set results [dict create]

        # Run requested tests
        if {"dns" in $tests} {
            set cmd "dig +short $target"
            if {[catch {::mcp::security::validate_command $cmd}]} {
                dict set results dns [dict create error "Command not permitted"]
            } elseif {[catch {set dns_output [::prompt::run $spawn_id $cmd]} err]} {
                dict set results dns [dict create error $err]
            } else {
                dict set results dns [dict create output [string trim $dns_output] success 1]
            }
        }

        if {"ping" in $tests} {
            set cmd "ping -c $ping_count $target"
            if {[catch {::mcp::security::validate_command $cmd}]} {
                dict set results ping [dict create error "Command not permitted"]
            } elseif {[catch {set ping_output [::prompt::run $spawn_id $cmd]} err]} {
                dict set results ping [dict create error $err]
            } else {
                dict set results ping [dict create output $ping_output success 1]
            }
        }

        if {"traceroute" in $tests} {
            set cmd "traceroute -m $traceroute_hops $target"
            if {[catch {::mcp::security::validate_command $cmd}]} {
                dict set results traceroute [dict create error "Command not permitted"]
            } elseif {[catch {set tr_output [::prompt::run $spawn_id $cmd]} err]} {
                dict set results traceroute [dict create error $err]
            } else {
                dict set results traceroute [dict create output $tr_output success 1]
            }
        }

        # Format output
        set text "Connectivity test to $target:\n"
        dict for {test_name test_result} $results {
            append text "\n=== $test_name ===\n"
            if {[dict exists $test_result error]} {
                append text "ERROR: [dict get $test_result error]\n"
            } else {
                append text "[dict get $test_result output]\n"
            }
        }

        return [dict create \
            content [list [dict create type "text" text $text]] \
            results $results \
            target $target \
        ]
    }

    #=========================================================================
    # ssh_batch_commands (Lines 915-990)
    #=========================================================================

    proc tool_ssh_batch_commands {args mcp_session_id} {
        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }
        if {![dict exists $args commands]} {
            return [_tool_error "Missing required parameter: commands"]
        }

        set session_id [dict get $args session_id]
        set commands [dict get $args commands]
        set stop_on_error [expr {[dict exists $args stop_on_error] ? [dict get $args stop_on_error] : 0}]
        if {$stop_on_error eq "true"} { set stop_on_error 1 }

        # Validate command count
        if {[llength $commands] == 0} {
            return [_tool_error "commands array cannot be empty"]
        }
        if {[llength $commands] > 5} {
            return [_tool_error "Maximum 5 commands allowed per batch"]
        }

        # Get session and verify ownership
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        # SECURITY: Validate ALL commands first before executing any
        foreach cmd $commands {
            if {[catch {::mcp::security::validate_command $cmd} err]} {
                return [_tool_error "Command not permitted: $cmd - $err"]
            }
        }

        set spawn_id [dict get $session spawn_id]
        set results [list]
        set all_success 1

        # Execute commands sequentially
        foreach cmd $commands {
            set result [dict create command $cmd]
            if {[catch {set output [::prompt::run $spawn_id $cmd]} err]} {
                dict set result error $err
                dict set result success 0
                set all_success 0
                lappend results $result
                if {$stop_on_error} {
                    break
                }
            } else {
                dict set result output $output
                dict set result success 1
                lappend results $result
            }
        }

        # Format output
        set text "Batch execution ([llength $results]/[llength $commands] commands):\n"
        set idx 0
        foreach result $results {
            incr idx
            append text "\n=== Command $idx: [dict get $result command] ===\n"
            if {[dict exists $result error]} {
                append text "ERROR: [dict get $result error]\n"
            } else {
                append text "[dict get $result output]\n"
            }
        }

        return [dict create \
            content [list [dict create type "text" text $text]] \
            results $results \
            total [llength $commands] \
            executed [llength $results] \
            all_success $all_success \
        ]
    }

    #=========================================================================
    # ssh_network_compare (Lines 1000-1080)
    #=========================================================================

    proc tool_ssh_network_compare {args mcp_session_id} {
        variable network_snapshots

        if {![dict exists $args session_id]} {
            return [_tool_error "Missing required parameter: session_id"]
        }

        set session_id [dict get $args session_id]
        set scope [expr {[dict exists $args scope] ? [dict get $args scope] : "all"}]
        set save_baseline [expr {[dict exists $args save_baseline] ? [dict get $args save_baseline] : 0}]
        if {$save_baseline eq "true"} { set save_baseline 1 }

        # Get session and verify ownership
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return [_tool_error "Session not found: $session_id"]
        }
        if {![_verify_session_owner $session_id $mcp_session_id]} {
            return [_tool_error "Session not owned by this client"]
        }

        set spawn_id [dict get $session spawn_id]

        # Collect current state based on scope
        set current_state [dict create timestamp [clock seconds]]

        if {$scope eq "all" || $scope eq "interfaces"} {
            set cmd "ip -j addr show"
            if {[catch {::mcp::security::validate_command $cmd}]} {
                dict set current_state interfaces_error "Command not permitted"
            } elseif {[catch {set output [::prompt::run $spawn_id $cmd]} err]} {
                dict set current_state interfaces_error $err
            } else {
                dict set current_state interfaces $output
            }
        }

        if {$scope eq "all" || $scope eq "routes"} {
            set cmd "ip -j route show"
            if {[catch {::mcp::security::validate_command $cmd}]} {
                dict set current_state routes_error "Command not permitted"
            } elseif {[catch {set output [::prompt::run $spawn_id $cmd]} err]} {
                dict set current_state routes_error $err
            } else {
                dict set current_state routes $output
            }
        }

        # Get previous baseline
        set cache_key "${session_id}:${scope}"
        set has_baseline 0
        set baseline_state [dict create]
        set baseline_timestamp ""

        if {[dict exists $network_snapshots $cache_key]} {
            set baseline_state [dict get $network_snapshots $cache_key]
            set baseline_timestamp [clock format [dict get $baseline_state timestamp] \
                -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1]
            set has_baseline 1
        }

        # Save current state as new baseline
        dict set network_snapshots $cache_key $current_state

        # If no baseline existed, just return current state
        if {!$has_baseline} {
            return [dict create \
                content [list [dict create type "text" text "No baseline found. Current state saved as baseline."]] \
                baseline_saved true \
                changes_detected false \
                current_state $current_state \
            ]
        }

        # Compare states
        set changes [_compare_snapshots $baseline_state $current_state $scope]

        set text "Network comparison (${scope}):\n"
        append text "Baseline: $baseline_timestamp\n"
        append text "Current:  [clock format [dict get $current_state timestamp] -format "%Y-%m-%dT%H:%M:%SZ" -gmt 1]\n"
        if {[dict get $changes changed]} {
            append text "\nChanges detected:\n[dict get $changes summary]"
        } else {
            append text "\nNo changes detected."
        }

        return [dict create \
            content [list [dict create type "text" text $text]] \
            changes_detected [dict get $changes changed] \
            comparison $changes \
            baseline_timestamp $baseline_timestamp \
        ]
    }

    proc _compare_snapshots {baseline current scope} {
        set changed 0
        set summary ""

        # Compare interfaces
        if {$scope eq "all" || $scope eq "interfaces"} {
            if {[dict exists $baseline interfaces] && [dict exists $current interfaces]} {
                set b_iface [dict get $baseline interfaces]
                set c_iface [dict get $current interfaces]
                if {$b_iface ne $c_iface} {
                    set changed 1
                    append summary "- Interfaces changed\n"
                }
            }
        }

        # Compare routes
        if {$scope eq "all" || $scope eq "routes"} {
            if {[dict exists $baseline routes] && [dict exists $current routes]} {
                set b_routes [dict get $baseline routes]
                set c_routes [dict get $current routes]
                if {$b_routes ne $c_routes} {
                    set changed 1
                    append summary "- Routes changed\n"
                }
            }
        }

        return [dict create \
            changed $changed \
            summary [string trim $summary] \
        ]
    }

    #=========================================================================
    # Helper Functions (Lines 525-580)
    #=========================================================================

    proc _tool_error {message} {
        return [dict create \
            content [list [dict create type "text" text $message]] \
            isError true \
        ]
    }

    proc _verify_session_owner {session_id mcp_session_id} {
        set session [::mcp::session::get $session_id]
        if {$session eq {}} {
            return 0
        }

        # Check if this MCP session owns the SSH session
        set owner_mcp [dict get $session mcp_session]
        return [expr {$owner_mcp eq $mcp_session_id}]
    }

    proc _is_binary {data} {
        # Check for null bytes
        if {[string first "\x00" $data] >= 0} {
            return 1
        }

        # Check non-printable ratio
        set len [string length $data]
        if {$len == 0} { return 0 }

        set non_print 0
        set sample_len [expr {min($len, 1024)}]
        for {set i 0} {$i < $sample_len} {incr i} {
            set char [string index $data $i]
            scan $char %c code
            if {$code < 9 || ($code > 13 && $code < 32) || $code > 126} {
                incr non_print
            }
        }
        return [expr {double($non_print) / $sample_len > 0.1}]
    }

    proc _truncate_large_output {output max_bytes} {
        set len [string length $output]
        if {$len <= $max_bytes} {
            return $output
        }
        set truncated [string range $output 0 [expr {$max_bytes - 1}]]
        append truncated "\n\n... (output truncated from $len to $max_bytes bytes)"
        return $truncated
    }

    proc _handle_large_output {output max_bytes} {
        set original_size [string length $output]
        if {$original_size <= $max_bytes} {
            return [dict create \
                content $output \
                truncated false \
                original_size_bytes $original_size \
            ]
        }
        set truncated_content [string range $output 0 [expr {$max_bytes - 1}]]
        return [dict create \
            content $truncated_content \
            truncated true \
            original_size_bytes $original_size \
        ]
    }

    # Initialize tool definitions
    register_all
}

package provide mcp::tools 1.0
