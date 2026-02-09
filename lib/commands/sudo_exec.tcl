# sudo_exec.tcl - Sudo execution wrapper
#
# Provides: commands::sudo
#
# Procedures:
#   commands::sudo::exec {spawn_id password} - Execute sudo -i
#                                               Returns 1 on success, 0 on failure

package require Expect

namespace eval commands::sudo {
    # Execute sudo -i to get root shell
    # Returns 1 on success, 0 on failure
    proc exec {spawn_id password} {
        debug::log 4 "Executing sudo -i"

        send -i $spawn_id "sudo -i\r"

        set timeout 30
        expect -i $spawn_id {
            # Password prompt - FAST: anchored, specific pattern
            -re {\[sudo\] password for [^:]+:\s*$} {
                debug::log 5 "Sudo password prompt received (sudo format)"
                send -i $spawn_id "$password\r"
                exp_continue
            }
            -re {[Pp]assword:\s*$} {
                debug::log 5 "Sudo password prompt received"
                send -i $spawn_id "$password\r"
                exp_continue
            }
            # Sorry, wrong password
            -re {Sorry, try again} {
                debug::log 1 "Sudo authentication failed - wrong password"
                return 0
            }
            # sudo: 3 incorrect password attempts
            -re {[0-9]+ incorrect password attempt} {
                debug::log 1 "Sudo authentication failed - too many attempts"
                return 0
            }
            # User not in sudoers
            -re {is not in the sudoers file} {
                debug::log 1 "User is not in sudoers file"
                return 0
            }
            # Not allowed to run sudo
            -re {not allowed to execute} {
                debug::log 1 "User not allowed to execute sudo"
                return 0
            }
            # Root shell prompt (any common prompt)
            -re {[#]\s*$} {
                debug::log 4 "Root shell prompt received"
            }
            timeout {
                debug::log 1 "Sudo timeout"
                return 0
            }
            eof {
                debug::log 1 "Connection closed during sudo"
                return 0
            }
        }

        # Initialize root prompt
        if {![prompt::init $spawn_id 1]} {
            debug::log 1 "Failed to initialize root prompt"
            return 0
        }

        # Verify we're root with whoami
        set whoami_output [prompt::run $spawn_id "whoami"]
        set whoami_output [string trim $whoami_output]

        if {$whoami_output eq "root"} {
            debug::log 3 "Successfully elevated to root"
            return 1
        } else {
            debug::log 1 "Failed to verify root access, whoami returned: $whoami_output"
            return 0
        }
    }

    # Exit from sudo shell back to user
    proc exit_sudo {spawn_id} {
        debug::log 4 "Exiting sudo shell"

        send -i $spawn_id "exit\r"

        # Get the exact user prompt pattern
        set user_pattern $::prompt::user_pattern

        set timeout 10
        expect -i $spawn_id \
            -ex $user_pattern {
                debug::log 4 "Returned to user shell"
                return 1
            } \
            timeout {
                debug::log 2 "Timeout waiting for user prompt after sudo exit"
                return 0
            } \
            eof {
                debug::log 1 "Connection closed"
                return 0
            }
    }
}
