# mcp/lib/tools.tcl - MCP Tool Implementations
#
# All tools that LLMs can invoke. Each tool validates inputs
# through the security layer before execution.

package require Tcl 8.6

namespace eval ::mcp::tools {
    # Tool registry for tools/list
    variable tool_definitions [list]

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
        ]
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

    # Initialize tool definitions
    register_all
}

package provide mcp::tools 1.0
