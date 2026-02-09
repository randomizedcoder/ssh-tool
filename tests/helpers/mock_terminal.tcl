# mock_terminal.tcl - Mock terminal for password prompt tests
#
# Provides utilities for testing password prompting functionality

package require Expect

namespace eval mock_terminal {
    variable spawn_id

    # Spawn a mock terminal that simulates password prompting
    proc spawn_password_prompt {{prompt_text "Password: "}} {
        variable spawn_id

        # Use expect's stty to simulate terminal interaction
        spawn bash -c "echo -n '$prompt_text'; read -s pass; echo ''; echo \"RECEIVED:\$pass\""
        set spawn_id $::spawn_id

        return $spawn_id
    }

    # Spawn a mock terminal that echoes input (for testing non-password input)
    proc spawn_echo_terminal {} {
        variable spawn_id

        spawn bash -c "while read line; do echo \"ECHO:\$line\"; done"
        set spawn_id $::spawn_id

        return $spawn_id
    }

    # Send password to the mock terminal
    proc send_password {password} {
        variable spawn_id
        send -i $spawn_id "$password\r"
    }

    # Wait for and capture the received password
    proc get_received_password {{timeout 5}} {
        variable spawn_id

        expect -i $spawn_id -timeout $timeout {
            -re {RECEIVED:([^\r\n]*)} {
                return $expect_out(1,string)
            }
            timeout {
                return ""
            }
            eof {
                return ""
            }
        }
    }

    # Close the mock terminal
    proc close_terminal {} {
        variable spawn_id

        catch {close -i $spawn_id}
        catch {wait -i $spawn_id}
    }

    # Get current spawn_id
    proc get_spawn_id {} {
        variable spawn_id
        return $spawn_id
    }

    # Test helper: simulate password entry and verify
    proc test_password_entry {password} {
        spawn_password_prompt
        send_password $password
        set received [get_received_password]
        close_terminal
        return [expr {$received eq $password}]
    }
}
