# mcp/agent/loadtest/coordinator.tcl - Load test coordinator
#
# Spawns and manages multiple worker processes for load testing.
# Aggregates results and generates reports.
#
# Dependencies (must be sourced before this file):
#   - config.tcl
#   - metrics/percentiles.tcl
#   - output/jsonl_writer.tcl
#   - agent/http_client.tcl
#   - agent/mcp_client.tcl

package require Tcl 9.0-

namespace eval ::loadtest::coordinator {
    variable workers [dict create]
    variable results_dir ""
    variable test_id ""
    variable start_time 0
    variable end_time 0

    # Initialize coordinator
    proc init {} {
        variable results_dir
        variable test_id

        set results_dir $::loadtest::config::results_dir
        set test_id "loadtest_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"

        # Create results directory
        set run_dir [file join $results_dir $test_id]
        file mkdir $run_dir

        log "Coordinator initialized: $test_id"
        log "Results directory: $run_dir"

        return $run_dir
    }

    # Spawn worker processes
    # @param num_workers  Number of workers to spawn
    # @param pattern      Load pattern name
    # @param duration     Test duration in seconds
    # @param extra_args   Additional arguments dict
    # @return list of worker PIDs
    proc spawn_workers {num_workers pattern duration {extra_args {}}} {
        variable workers
        variable results_dir
        variable test_id

        set run_dir [file join $results_dir $test_id]
        # Use absolute path so worker can be run from any cwd
        set worker_script [file normalize [file join [file dirname [info script]] worker.tcl]]

        set pids [list]

        for {set i 0} {$i < $num_workers} {incr i} {
            set worker_id "w$i"
            set output_file [file join $run_dir "${worker_id}.jsonl"]

            # Build worker command
            set cmd [list tclsh $worker_script \
                --id $worker_id \
                --mcp-url [::loadtest::config::mcp_url] \
                --target-host $::loadtest::config::target_host \
                --target-port $::loadtest::config::target_port \
                --user $::loadtest::config::target_user \
                --password $::loadtest::config::target_pass \
                --output $output_file \
                --pattern $pattern \
                --duration $duration \
            ]

            # Add extra args
            dict for {k v} $extra_args {
                lappend cmd "--$k" $v
            }

            # Spawn worker process
            log "Spawning worker $worker_id: $pattern for ${duration}s"

            set pid [exec {*}$cmd 2>@stderr &]

            dict set workers $worker_id [dict create \
                pid $pid \
                output_file $output_file \
                status "running" \
            ]

            lappend pids $pid
        }

        log "Spawned $num_workers workers"
        return $pids
    }

    # Wait for all workers to complete
    # @param timeout_s  Maximum wait time in seconds
    # @return 1 if all completed, 0 if timeout
    proc wait_for_workers {timeout_s} {
        variable workers

        set deadline [expr {[clock seconds] + $timeout_s}]

        while {[clock seconds] < $deadline} {
            set all_done 1

            dict for {worker_id info} $workers {
                set pid [dict get $info pid]

                # Check if process is still running
                if {[catch {exec kill -0 $pid 2>/dev/null}]} {
                    # Process has exited
                    dict set workers $worker_id status "completed"
                } else {
                    set all_done 0
                }
            }

            if {$all_done} {
                log "All workers completed"
                return 1
            }

            after 500
        }

        log "Timeout waiting for workers"
        return 0
    }

    # Kill all workers
    proc kill_workers {} {
        variable workers

        dict for {worker_id info} $workers {
            set pid [dict get $info pid]
            catch {exec kill $pid}
        }

        log "Sent kill signal to all workers"
    }

    # Collect results from all worker output files
    # @return dict with aggregated results
    proc collect_results {} {
        variable workers
        variable results_dir
        variable test_id

        set all_latencies [list]
        set all_timestamps [list]
        set total_requests 0
        set total_errors 0
        set worker_stats [list]

        dict for {worker_id info} $workers {
            set output_file [dict get $info output_file]

            if {![file exists $output_file]} {
                log "Warning: output file not found for $worker_id"
                continue
            }

            # Read and parse worker results
            set latencies [list]
            set timestamps [list]
            set requests 0
            set errors 0

            set fh [open $output_file r]
            while {[gets $fh line] >= 0} {
                if {[string trim $line] eq ""} continue

                # Parse JSON line manually (simple extraction)
                if {[regexp {"ts":(\d+)} $line -> ts]} {
                    lappend timestamps $ts
                    lappend all_timestamps $ts
                }
                if {[regexp {"latency_ms":([0-9.]+)} $line -> latency]} {
                    lappend latencies $latency
                    lappend all_latencies $latency
                }
                if {[regexp {"status":"success"} $line]} {
                    incr requests
                    incr total_requests
                } elseif {[regexp {"status":"error"} $line]} {
                    incr errors
                    incr total_errors
                }
            }
            close $fh

            # Calculate per-worker stats
            set wstats [::loadtest::stats::calculate $latencies]
            dict set wstats worker_id $worker_id
            dict set wstats errors $errors
            lappend worker_stats $wstats
        }

        # Calculate aggregate stats
        set aggregate [::loadtest::stats::calculate $all_latencies]
        set throughput [::loadtest::stats::throughput $all_timestamps 1000]

        return [dict create \
            total_requests $total_requests \
            total_errors $total_errors \
            success_rate [expr {$total_requests > 0 ? (($total_requests - $total_errors) * 100.0 / $total_requests) : 0}] \
            latency $aggregate \
            throughput $throughput \
            worker_stats $worker_stats \
        ]
    }

    # Scrape metrics from MCP server
    proc scrape_mcp_metrics {} {
        set url "[::loadtest::config::mcp_url]/metrics"

        if {[catch {
            set response [::agent::http::get $url]
            set body [dict get $response body]
        } err]} {
            log "Warning: Failed to scrape MCP metrics: $err"
            return [dict create]
        }

        # Parse Prometheus format
        set metrics [dict create]
        foreach line [split $body "\n"] {
            if {[string match "#*" $line] || [string trim $line] eq ""} continue

            # Parse metric line: name{labels} value or name value
            # Handle metrics with labels: metric_name{label="value"} 123
            if {[string first "\{" $line] >= 0} {
                # Has labels - parse name, labels, value
                set brace_start [string first "\{" $line]
                set brace_end [string first "\}" $line]
                if {$brace_end > $brace_start} {
                    set name [string range $line 0 [expr {$brace_start - 1}]]
                    set labels [string range $line [expr {$brace_start + 1}] [expr {$brace_end - 1}]]
                    set rest [string trimleft [string range $line [expr {$brace_end + 1}] end]]
                    if {[string is double -strict $rest]} {
                        dict set metrics "${name}\{${labels}\}" $rest
                    }
                }
            } else {
                # No labels - simple name value format
                set parts [split [string trim $line]]
                if {[llength $parts] == 2} {
                    set name [lindex $parts 0]
                    set value [lindex $parts 1]
                    if {[string is double -strict $value]} {
                        dict set metrics $name $value
                    }
                }
            }
        }

        return $metrics
    }

    # Run a complete test scenario
    # @param scenario_name  Name of scenario
    # @param overrides      Dict of parameter overrides
    # @return results dict
    proc run_scenario {scenario_name {overrides {}}} {
        variable start_time
        variable end_time

        log "=========================================="
        log "Running scenario: $scenario_name"
        log "=========================================="

        # Get scenario config
        set config [::loadtest::config::get_scenario $scenario_name]
        dict for {k v} $overrides {
            dict set config $k $v
        }

        set duration [dict get $config duration]
        set description [dict get $config description]
        log "Description: $description"
        log "Duration: ${duration}s"

        # Initialize
        set run_dir [init]

        # Scrape initial metrics
        set metrics_before [scrape_mcp_metrics]

        # Record start time
        set start_time [clock milliseconds]

        # Spawn workers based on scenario
        set extra_args [dict create]

        switch $scenario_name {
            "connection_rate" {
                # Run multiple worker counts sequentially
                set worker_counts [dict get $config workers]
                set all_results [list]

                foreach num_workers $worker_counts {
                    log "Testing with $num_workers workers..."

                    spawn_workers $num_workers "connection_rate" $duration
                    wait_for_workers [expr {$duration + 30}]

                    set results [collect_results]
                    dict set results num_workers $num_workers
                    lappend all_results $results

                    # Reset for next iteration
                    set ::loadtest::coordinator::workers [dict create]
                }

                set end_time [clock milliseconds]
                set results [dict create \
                    scenario $scenario_name \
                    iterations $all_results \
                ]
            }
            "command_throughput" {
                set num_workers [dict get $config workers]
                dict set extra_args commands [dict get $config commands]

                spawn_workers $num_workers "command_throughput" $duration $extra_args
                wait_for_workers [expr {$duration + 30}]

                set end_time [clock milliseconds]
                set results [collect_results]
                dict set results scenario $scenario_name
                dict set results num_workers $num_workers
            }
            "sustained_load" {
                set num_workers [dict get $config workers]
                dict set extra_args mix [dict get $config workload_mix]

                spawn_workers $num_workers "sustained_load" $duration $extra_args
                wait_for_workers [expr {$duration + 60}]

                set end_time [clock milliseconds]
                set results [collect_results]
                dict set results scenario $scenario_name
            }
            "latency_test" {
                set num_workers [dict get $config workers]
                set ports [dict get $config ports]
                set target_rate [dict get $config target_rate]
                set all_results [list]

                foreach port $ports {
                    log "Testing latency on port $port..."

                    dict set extra_args rate $target_rate
                    dict set extra_args port $port

                    spawn_workers $num_workers "latency_test" $duration $extra_args
                    wait_for_workers [expr {$duration + 30}]

                    set port_results [collect_results]
                    dict set port_results port $port
                    lappend all_results $port_results

                    # Reset for next port
                    set ::loadtest::coordinator::workers [dict create]
                }

                set end_time [clock milliseconds]
                set results [dict create \
                    scenario $scenario_name \
                    port_results $all_results \
                ]
            }
            "exhaustion_test" {
                set num_workers [dict get $config workers]
                dict set extra_args connections [dict get $config target_connections]

                spawn_workers $num_workers "exhaustion_test" $duration $extra_args
                wait_for_workers [expr {$duration + 60}]

                set end_time [clock milliseconds]
                set results [collect_results]
                dict set results scenario $scenario_name
            }
            default {
                error "Unknown scenario: $scenario_name"
            }
        }

        # Scrape final metrics
        set metrics_after [scrape_mcp_metrics]

        # Add metadata
        dict set results test_id $::loadtest::coordinator::test_id
        dict set results start_time $start_time
        dict set results end_time $end_time
        dict set results duration_ms [expr {$end_time - $start_time}]
        dict set results mcp_metrics_before $metrics_before
        dict set results mcp_metrics_after $metrics_after
        dict set results config $config

        # Save results summary
        set summary_file [file join $run_dir "summary.json"]
        set fh [open $summary_file w]
        puts $fh [::loadtest::output::jsonl::dict_to_json $results]
        close $fh

        log "Results saved to: $summary_file"
        log "=========================================="

        return $results
    }

    # Log message
    proc log {msg} {
        puts stderr "\[coordinator\] $msg"
    }
}

package provide loadtest::coordinator 1.0
