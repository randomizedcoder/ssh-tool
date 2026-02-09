# mock_ssh.tcl - Mock SSH session simulator
#
# Provides a mock SSH session for testing without real network connections

package require Expect

namespace eval mock_ssh {
    variable sid ""
    variable project_root ""

    # Initialize with project root
    proc init {root} {
        variable project_root
        set project_root $root
    }

    # Get the mock server script path
    proc get_mock_server {} {
        variable project_root
        return [file join $project_root "tests/helpers/mock_ssh_server.sh"]
    }

    # Spawn a mock SSH session
    # Returns spawn_id
    proc spawn_session {{behavior "normal"}} {
        variable sid
        variable project_root

        set mock_server [get_mock_server]

        if {![file exists $mock_server]} {
            error "Mock server not found: $mock_server"
        }

        # Spawn the mock server with behavior argument
        # spawn sets spawn_id as a local variable in this proc
        spawn bash $mock_server $behavior
        # Capture the local spawn_id into our namespace variable
        set sid $spawn_id

        return $sid
    }

    # Close the mock session
    proc close_session {} {
        variable sid

        if {$sid eq ""} {
            return
        }

        catch {
            send -i $sid "exit\r"
            expect -i $sid -timeout 2 eof
        }
        catch {close -i $sid}
        catch {wait -i $sid}
        set sid ""
    }

    # Send command to mock session
    proc send_cmd {cmd} {
        variable sid
        send -i $sid "$cmd\r"
    }

    # Wait for prompt
    proc wait_for_prompt {{timeout_val 5}} {
        variable sid

        set timeout $timeout_val
        expect -i $sid {
            -re {[$#>] $} {
                return 1
            }
            timeout {
                return 0
            }
            eof {
                return 0
            }
        }
    }

    # Get current spawn_id
    proc get_spawn_id {} {
        variable sid
        return $sid
    }
}
