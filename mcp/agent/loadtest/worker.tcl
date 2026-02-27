#!/usr/bin/env tclsh
# mcp/agent/loadtest/worker.tcl - Load test worker process
#
# Individual worker process that generates load against the MCP server.
# Spawned by coordinator.tcl, writes results to output file.

package require Tcl 9.0-

# Find and source dependencies - use absolute paths to work from any cwd
# Use unique variable names to avoid collision with sourced files (mcp_client.tcl
# overwrites the global script_dir variable)
set _worker_dir [file normalize [file dirname [info script]]]
set _agent_dir [file dirname $_worker_dir]

# Source agent libraries first (they may overwrite globals)
source [file join $_agent_dir http_client.tcl]
source [file join $_agent_dir json.tcl]
source [file join $_agent_dir mcp_client.tcl]
# Source worker-specific files last
source [file join $_worker_dir output jsonl_writer.tcl]

namespace eval ::loadtest::worker {
    variable worker_id ""
    variable output_file ""
    variable mcp_url ""
    variable target_host ""
    variable target_port 2222
    variable target_user ""
    variable target_pass ""
    variable ssh_session_id ""
    variable stop_flag 0
    variable stats [dict create \
        requests 0 \
        successes 0 \
        errors 0 \
        latencies [list] \
    ]

    # Initialize worker
    proc init {id url host port user pass output} {
        variable worker_id
        variable output_file
        variable mcp_url
        variable target_host
        variable target_port
        variable target_user
        variable target_pass

        set worker_id $id
        set output_file $output
        set mcp_url $url
        set target_host $host
        set target_port $port
        set target_user $user
        set target_pass $pass

        # Initialize MCP client
        ::agent::mcp::init $mcp_url

        # Open output file
        ::loadtest::output::jsonl::open_file $output_file

        log "Worker initialized"
    }

    # Cleanup worker
    proc cleanup {} {
        variable ssh_session_id

        # Disconnect SSH if connected
        if {$ssh_session_id ne ""} {
            catch {::agent::mcp::ssh_disconnect $ssh_session_id}
            set ssh_session_id ""
        }

        # Close output file
        catch {::loadtest::output::jsonl::close_file}

        log "Worker cleanup complete"
    }

    # Connect to SSH target via MCP
    proc connect {} {
        variable target_host
        variable target_port
        variable target_user
        variable target_pass
        variable ssh_session_id
        variable stats

        set start_ms [clock milliseconds]

        if {[catch {
            set result [::agent::mcp::ssh_connect $target_host $target_user $target_pass $target_port]
            set ssh_session_id [dict get $result session_id]
        } err]} {
            set latency [expr {[clock milliseconds] - $start_ms}]
            record_result "ssh_connect" $latency "error" $err
            return 0
        }

        set latency [expr {[clock milliseconds] - $start_ms}]
        record_result "ssh_connect" $latency "success"
        return 1
    }

    # Disconnect from SSH target
    proc disconnect {} {
        variable ssh_session_id
        variable stats

        if {$ssh_session_id eq ""} {
            return 1
        }

        set start_ms [clock milliseconds]

        if {[catch {
            ::agent::mcp::ssh_disconnect $ssh_session_id
            set ssh_session_id ""
        } err]} {
            set latency [expr {[clock milliseconds] - $start_ms}]
            record_result "ssh_disconnect" $latency "error" $err
            return 0
        }

        set latency [expr {[clock milliseconds] - $start_ms}]
        record_result "ssh_disconnect" $latency "success"
        return 1
    }

    # Run command on SSH target
    proc run_command {cmd} {
        variable ssh_session_id
        variable stats

        if {$ssh_session_id eq ""} {
            record_result "ssh_run_command" 0 "error" "Not connected"
            return ""
        }

        set start_ms [clock milliseconds]

        if {[catch {
            set result [::agent::mcp::ssh_run_command $ssh_session_id $cmd]
            set output [::agent::mcp::extract_text $result]
        } err]} {
            set latency [expr {[clock milliseconds] - $start_ms}]
            record_result "ssh_run_command" $latency "error" $err
            return ""
        }

        set latency [expr {[clock milliseconds] - $start_ms}]
        record_result "ssh_run_command" $latency "success"
        return $output
    }

    # Record a result
    proc record_result {operation latency_ms status {error_msg ""}} {
        variable worker_id
        variable stats

        dict incr stats requests
        if {$status eq "success"} {
            dict incr stats successes
        } else {
            dict incr stats errors
        }
        dict lappend stats latencies $latency_ms

        ::loadtest::output::jsonl::write_request $worker_id $operation $latency_ms $status $error_msg
    }

    # Get current stats
    proc get_stats {} {
        variable stats
        return $stats
    }

    # Reset stats
    proc reset_stats {} {
        variable stats
        set stats [dict create \
            requests 0 \
            successes 0 \
            errors 0 \
            latencies [list] \
        ]
    }

    # Stop the worker
    proc stop {} {
        variable stop_flag
        set stop_flag 1
    }

    # Check if stopped
    proc is_stopped {} {
        variable stop_flag
        return $stop_flag
    }

    # Log message
    proc log {msg} {
        variable worker_id
        puts stderr "\[worker-$worker_id\] $msg"
    }

    #=========================================================================
    # Workload patterns
    #=========================================================================

    # Run connection rate test pattern
    # Connect -> Disconnect cycle
    proc pattern_connection_rate {duration_s} {
        variable stop_flag

        set end_time [expr {[clock seconds] + $duration_s}]
        set cycles 0

        while {[clock seconds] < $end_time && !$stop_flag} {
            # Initialize MCP session for this cycle
            if {[catch {::agent::mcp::initialize "loadtest-worker" "1.0"} err]} {
                log "MCP init failed: $err"
                after 100
                continue
            }

            if {[connect]} {
                disconnect
                incr cycles
            }

            # Small delay between cycles
            after 10
        }

        log "Connection rate test complete: $cycles cycles"
        return $cycles
    }

    # Run command throughput test pattern
    # Uses established connection, runs commands rapidly
    proc pattern_command_throughput {duration_s commands} {
        variable stop_flag
        variable ssh_session_id

        # Initialize and connect
        if {[catch {::agent::mcp::initialize "loadtest-worker" "1.0"} err]} {
            log "MCP init failed: $err"
            return 0
        }

        if {![connect]} {
            log "Initial connect failed"
            return 0
        }

        set end_time [expr {[clock seconds] + $duration_s}]
        set cmd_count 0
        set cmd_idx 0

        while {[clock seconds] < $end_time && !$stop_flag} {
            set cmd [lindex $commands $cmd_idx]
            set cmd_idx [expr {($cmd_idx + 1) % [llength $commands]}]

            run_command $cmd
            incr cmd_count
        }

        disconnect
        log "Command throughput test complete: $cmd_count commands"
        return $cmd_count
    }

    # Run sustained load test pattern
    # Mixed workload: commands + occasional connect/disconnect
    proc pattern_sustained_load {duration_s mix} {
        variable stop_flag
        variable ssh_session_id

        set cmd_pct [dict get $mix commands]
        set connect_pct [dict get $mix connect]
        # disconnect_pct is the remainder

        # Initialize and connect
        if {[catch {::agent::mcp::initialize "loadtest-worker" "1.0"} err]} {
            log "MCP init failed: $err"
            return 0
        }

        if {![connect]} {
            log "Initial connect failed"
            return 0
        }

        set end_time [expr {[clock seconds] + $duration_s}]
        set ops 0

        while {[clock seconds] < $end_time && !$stop_flag} {
            set roll [expr {int(rand() * 100)}]

            if {$roll < $cmd_pct} {
                # Run a command
                if {$ssh_session_id ne ""} {
                    run_command "hostname"
                } else {
                    # Need to reconnect first
                    connect
                }
            } elseif {$roll < ($cmd_pct + $connect_pct)} {
                # Connect (if not already)
                if {$ssh_session_id eq ""} {
                    connect
                }
            } else {
                # Disconnect (if connected)
                if {$ssh_session_id ne ""} {
                    disconnect
                }
            }

            incr ops

            # Rate limit to ~50 ops/sec
            after 20
        }

        # Cleanup
        if {$ssh_session_id ne ""} {
            disconnect
        }

        log "Sustained load test complete: $ops operations"
        return $ops
    }

    # Run latency test pattern
    # Fixed rate against specified port
    proc pattern_latency_test {duration_s target_rate port} {
        variable stop_flag
        variable target_port

        # Override port for this test
        set original_port $target_port
        set target_port $port

        # Initialize and connect
        if {[catch {::agent::mcp::initialize "loadtest-worker" "1.0"} err]} {
            log "MCP init failed: $err"
            set target_port $original_port
            return 0
        }

        if {![connect]} {
            log "Connect failed to port $port"
            set target_port $original_port
            return 0
        }

        set end_time [expr {[clock seconds] + $duration_s}]
        set interval_ms [expr {int(1000.0 / $target_rate)}]
        set cmd_count 0

        while {[clock seconds] < $end_time && !$stop_flag} {
            set start [clock milliseconds]

            run_command "hostname"
            incr cmd_count

            # Maintain target rate
            set elapsed [expr {[clock milliseconds] - $start}]
            set sleep_ms [expr {max(0, $interval_ms - $elapsed)}]
            if {$sleep_ms > 0} {
                after $sleep_ms
            }
        }

        disconnect
        set target_port $original_port

        log "Latency test (port $port) complete: $cmd_count commands"
        return $cmd_count
    }

    # Run exhaustion test pattern
    # Try to exceed limits
    proc pattern_exhaustion_test {duration_s target_connections} {
        variable stop_flag

        set sessions [list]

        # Try to create many connections
        for {set i 0} {$i < $target_connections && !$stop_flag} {incr i} {
            if {[catch {::agent::mcp::initialize "loadtest-worker-$i" "1.0"} err]} {
                log "MCP init $i failed: $err"
                continue
            }

            if {[catch {
                set result [::agent::mcp::ssh_connect \
                    $::loadtest::worker::target_host \
                    $::loadtest::worker::target_user \
                    $::loadtest::worker::target_pass \
                    $::loadtest::worker::target_port]
                lappend sessions [dict get $result session_id]
                log "Created session $i"
            } err]} {
                log "Connect $i failed: $err"
                record_result "ssh_connect" 0 "error" $err
            }
        }

        log "Created [llength $sessions] sessions (target: $target_connections)"

        # Hold connections for duration, running commands
        set end_time [expr {[clock seconds] + $duration_s}]

        while {[clock seconds] < $end_time && !$stop_flag} {
            foreach sid $sessions {
                if {[catch {
                    ::agent::mcp::ssh_run_command $sid "hostname"
                } err]} {
                    log "Command on $sid failed: $err"
                }
            }
            after 1000
        }

        # Cleanup all sessions
        foreach sid $sessions {
            catch {::agent::mcp::ssh_disconnect $sid}
        }

        return [llength $sessions]
    }
}

#=============================================================================
# Main - when run as standalone script
#=============================================================================

proc main {argv} {
    # Parse arguments
    set worker_id "0"
    set mcp_url "http://10.178.0.10:3000"
    set target_host "10.178.0.20"
    set target_port 2222
    set target_user "testuser"
    set target_pass "testpass"
    set output_file "/tmp/loadtest_results/worker_0.jsonl"
    set pattern "command_throughput"
    set duration 60
    set extra_args [dict create]

    for {set i 0} {$i < [llength $argv]} {incr i} {
        set arg [lindex $argv $i]
        switch -glob -- $arg {
            "--id"          { incr i; set worker_id [lindex $argv $i] }
            "--mcp-url"     { incr i; set mcp_url [lindex $argv $i] }
            "--target-host" { incr i; set target_host [lindex $argv $i] }
            "--target-port" { incr i; set target_port [lindex $argv $i] }
            "--user"        { incr i; set target_user [lindex $argv $i] }
            "--password"    { incr i; set target_pass [lindex $argv $i] }
            "--output"      { incr i; set output_file [lindex $argv $i] }
            "--pattern"     { incr i; set pattern [lindex $argv $i] }
            "--duration"    { incr i; set duration [lindex $argv $i] }
            "--commands"    { incr i; dict set extra_args commands [lindex $argv $i] }
            "--mix"         { incr i; dict set extra_args mix [lindex $argv $i] }
            "--rate"        { incr i; dict set extra_args rate [lindex $argv $i] }
            "--port"        { incr i; dict set extra_args port [lindex $argv $i] }
            "--connections" { incr i; dict set extra_args connections [lindex $argv $i] }
        }
    }

    # Initialize
    ::loadtest::worker::init $worker_id $mcp_url $target_host $target_port $target_user $target_pass $output_file

    # Run pattern
    switch $pattern {
        "connection_rate" {
            ::loadtest::worker::pattern_connection_rate $duration
        }
        "command_throughput" {
            set commands [dict get $extra_args commands]
            if {$commands eq ""} {
                set commands {hostname whoami "cat /etc/hostname"}
            }
            ::loadtest::worker::pattern_command_throughput $duration $commands
        }
        "sustained_load" {
            set mix [dict get $extra_args mix]
            if {$mix eq ""} {
                set mix [dict create commands 70 connect 20 disconnect 10]
            }
            ::loadtest::worker::pattern_sustained_load $duration $mix
        }
        "latency_test" {
            set rate [dict get $extra_args rate]
            if {$rate eq ""} { set rate 10 }
            set port [dict get $extra_args port]
            if {$port eq ""} { set port 2222 }
            ::loadtest::worker::pattern_latency_test $duration $rate $port
        }
        "exhaustion_test" {
            set connections [dict get $extra_args connections]
            if {$connections eq ""} { set connections 15 }
            ::loadtest::worker::pattern_exhaustion_test $duration $connections
        }
        default {
            puts stderr "Unknown pattern: $pattern"
            exit 1
        }
    }

    # Cleanup
    ::loadtest::worker::cleanup

    # Output final stats
    set stats [::loadtest::worker::get_stats]
    puts stderr "\[worker-$worker_id\] Final stats: [dict get $stats requests] requests, [dict get $stats errors] errors"
}

# Run if executed directly
if {[info script] eq $::argv0} {
    main $::argv
}
