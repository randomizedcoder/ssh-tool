# prompt.tcl - Robust prompt detection & management
#
# Provides: prompt
#
# Procedures:
#   prompt::init {spawn_id {is_root 0}}  - Initialize unique prompt after connect
#   prompt::wait {spawn_id}              - Wait for prompt, return when ready
#   prompt::run {spawn_id cmd}           - Run command, return output reliably
#   prompt::marker {{is_root 0}}         - Get current prompt marker string

package require Expect

namespace eval prompt {
    # Unique marker using PID to avoid collisions
    # These are set at namespace load time
    variable mypid [pid]
    variable marker "XPCT${mypid}>"
    variable root_marker "XPCT${mypid}#"

    # Exact patterns for expect matching (with trailing space)
    variable user_pattern "XPCT${mypid}> "
    variable root_pattern "XPCT${mypid}# "

    # Track which spawn_ids have had first line skipped
    variable first_line_skipped [dict create]

    # Initialize prompt after SSH connection established
    # Sets TERM=dumb to disable colors, clears PROMPT_COMMAND
    proc init {spawn_id {is_root 0}} {
        variable marker
        variable root_marker
        variable first_line_skipped
        variable mypid
        variable user_pattern
        variable root_pattern

        set m [expr {$is_root ? $root_marker : $marker}]

        # Reset first-line tracking for this spawn_id
        dict set first_line_skipped $spawn_id 0

        # Increase match buffer for large outputs
        match_max 100000

        # Disable bracket-paste mode first (prevents \e[?2004h sequences)
        send -i $spawn_id "bind 'set enable-bracketed-paste off' 2>/dev/null; printf '\\e\[?2004l'\r"

        # Wait briefly for that to take effect
        set timeout 2
        expect -i $spawn_id {
            -re {[$#>] } { }
            timeout { }
        }

        # Disable TERM features that cause issues (colors, readline)
        # Also clear PS0, PS2 and any shell integration functions
        send -i $spawn_id "export TERM=dumb PROMPT_COMMAND='' PS0='' PS2='> '\r"
        expect -i $spawn_id -timeout 2 -re {.} { exp_continue } timeout { }

        # Disable systemd shell integration (Fedora uses this for OSC 3008 sequences)
        send -i $spawn_id "unset -f __vte_prompt_command 2>/dev/null; unset -f __osc_133_first_time 2>/dev/null\r"
        expect -i $spawn_id -timeout 2 -re {.} { exp_continue } timeout { }

        # Shell-agnostic prompt setting
        # Works on: bash, zsh, sh, dash, ksh (POSIX)
        # Fallback for: csh, tcsh
        send -i $spawn_id "PS1='$m ' 2>/dev/null || set prompt='$m '\r"

        set timeout 10
        expect -i $spawn_id \
            -ex $user_pattern {
                debug::log 5 "Prompt initialized: $m"
            } \
            -ex $root_pattern {
                debug::log 5 "Prompt initialized: $m"
            } \
            timeout {
                debug::log 1 "Failed to set prompt"
                return 0
            } \
            eof {
                debug::log 1 "Connection closed during prompt init"
                return 0
            }

        # Consume any remaining data in the buffer to clean up
        expect -i $spawn_id -timeout 0 -re {.+} { }

        # Wait for the shell to output the new prompt (it will print prompt after PS1 change)
        expect -i $spawn_id -timeout 2 \
            -ex $user_pattern { } \
            -ex $root_pattern { } \
            timeout { }

        # Clear any final buffer contents
        expect -i $spawn_id -timeout 0 -re {.+} { }

        return 1
    }

    # Wait for prompt to appear
    proc wait {spawn_id} {
        variable user_pattern
        variable root_pattern

        set timeout 30
        expect -i $spawn_id \
            -ex $user_pattern {
                return 1
            } \
            -ex $root_pattern {
                return 1
            } \
            timeout {
                debug::log 1 "Timeout waiting for prompt"
                return 0
            } \
            eof {
                debug::log 1 "Connection closed"
                return 0
            }
    }

    # Strip ANSI escape sequences and OSC sequences from a string
    # Handles: CSI sequences (\033[...), OSC sequences (\033]...\007 or \033]...\033\\)
    proc strip_escapes {str} {
        # Remove OSC sequences: ESC ] ... (BEL or ESC \)
        # Format: \033]....\007 or \033]....\033\\
        regsub -all {\033\][^\007\033]*(?:\007|\033\\)} $str "" str

        # Remove CSI sequences: ESC [ ... (ending in letter)
        regsub -all {\033\[[0-9;?]*[A-Za-z]} $str "" str

        # Remove any remaining bare ESC characters and control chars
        regsub -all {\033} $str "" str

        return $str
    }

    # High-performance line-by-line capture with first-line skip
    # Returns: output string (lines joined with newlines)
    proc run {spawn_id cmd} {
        variable mypid
        variable user_pattern
        variable root_pattern

        set output_lines {}
        set first_line_skipped 0
        set timeout_count 0
        set max_timeouts 3

        # Disable logging during capture for performance
        log_user 0

        send -i $spawn_id "$cmd\r"

        set timeout 30

        # Read output line by line until we see our prompt
        # Pattern order matters: check for lines BEFORE checking for prompt
        while {1} {
            expect -i $spawn_id \
                -re {([^\r\n]*)\r\n} {
                    set line $expect_out(1,string)
                    # Strip ANSI/OSC escape sequences from the line
                    set line [strip_escapes $line]
                    if {!$first_line_skipped} {
                        # Skip echoed command
                        set first_line_skipped 1
                        debug::log 6 "Skipped command echo: $line"
                    } else {
                        # Check if this line contains the prompt marker
                        if {![string match "*XPCT${mypid}*" $line]} {
                            lappend output_lines $line
                            debug::log 6 "Captured line: $line"
                        }
                    }
                    # Continue reading
                } \
                -ex $user_pattern {
                    # Prompt found, done
                    debug::log 5 "Command completed, prompt received"
                    break
                } \
                -ex $root_pattern {
                    # Root prompt found, done
                    debug::log 5 "Command completed, root prompt received"
                    break
                } \
                timeout {
                    incr timeout_count
                    if {$timeout_count < $max_timeouts} {
                        debug::log 4 "Timeout $timeout_count/$max_timeouts, retrying..."
                    } else {
                        debug::log 1 "Command timed out after $max_timeouts attempts"
                        break
                    }
                } \
                eof {
                    debug::log 1 "Connection closed unexpectedly"
                    break
                }
        }

        log_user 1
        return [join $output_lines "\n"]
    }

    # Run command with bracketed output capture for reliability
    # Returns: list of {exit_code output}
    proc run_with_status {spawn_id cmd} {
        variable mypid
        variable user_pattern
        variable root_pattern

        set start_mark "<<<CMD_START_${mypid}>>>"
        set end_mark "<<<CMD_END_${mypid}>>>"

        # Disable logging during capture
        log_user 0

        # Bracket command output with unique markers
        send -i $spawn_id "echo '$start_mark'; $cmd; __rc=\$?; echo '$end_mark'; echo \"__EXIT=\$__rc\"\r"

        set output ""
        set exit_code ""
        set timeout 30

        expect -i $spawn_id \
            -re "$start_mark\r\n(.*?)\r\n$end_mark\r\n__EXIT=(\[0-9\]+)" {
                set output $expect_out(1,string)
                set exit_code $expect_out(2,string)
            } \
            timeout {
                debug::log 1 "Command timed out"
                log_user 1
                return [list 1 ""]
            } \
            eof {
                debug::log 1 "Connection closed unexpectedly"
                log_user 1
                return [list 1 ""]
            }

        # Wait for prompt
        wait $spawn_id

        log_user 1
        return [list $exit_code $output]
    }

    # Get marker for external use
    proc marker {{is_root 0}} {
        variable marker
        variable root_marker
        return [expr {$is_root ? $root_marker : $marker}]
    }
}
