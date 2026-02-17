# ssh.tcl - SSH connection management
#
# Provides: connection::ssh
#
# Procedures:
#   connection::ssh::connect {host user password {insecure 0}} - Establish SSH connection
#                                                                 Returns spawn_id on success
#   connection::ssh::disconnect {spawn_id}                     - Close SSH connection
#   connection::ssh::is_connected {spawn_id}                   - Check connection status

package require Expect

namespace eval connection::ssh {
    # Track active connections
    variable connections [dict create]

    # Establish SSH connection
    # Returns spawn_id on success, empty string on failure
    proc connect {host user password {insecure 0} {port 22}} {
        variable connections

        debug::log 3 "Connecting to $user@$host:$port"

        # Check for insecure mode from environment if not specified
        if {!$insecure && [info exists ::env(INSECURE)] && $::env(INSECURE) eq "1"} {
            set insecure 1
        }

        # Spawn SSH with appropriate options
        if {$insecure} {
            debug::log 2 "WARNING: Insecure mode enabled - skipping host key verification"
            spawn ssh -o StrictHostKeyChecking=no \
                      -o UserKnownHostsFile=/dev/null \
                      -o LogLevel=ERROR \
                      -p $port \
                      $user@$host
        } else {
            spawn ssh -p $port $user@$host
        }

        set sid $spawn_id

        set timeout 30
        expect {
            # Host key verification prompt
            -re {\(yes/no(/\[fingerprint\])?\)\?\s*$} {
                debug::log 2 "Host key verification prompt - accepting"
                send "yes\r"
                exp_continue
            }
            # Continue connecting prompt (ECDSA key fingerprint)
            -re {Are you sure you want to continue connecting} {
                debug::log 2 "Host key verification prompt - accepting"
                send "yes\r"
                exp_continue
            }
            # Password prompt - FAST: anchored, specific pattern
            -re {[Pp]assword:\s*$} {
                debug::log 4 "Password prompt received"
                send "$password\r"
                exp_continue
            }
            # Permission denied
            -re {Permission denied} {
                debug::log 1 "Permission denied - authentication failed"
                catch {close -i $sid}
                catch {wait -i $sid}
                return ""
            }
            # Connection refused
            -re {Connection refused} {
                debug::log 1 "Connection refused by host"
                catch {close -i $sid}
                catch {wait -i $sid}
                return ""
            }
            # No route to host
            -re {No route to host} {
                debug::log 1 "No route to host"
                catch {close -i $sid}
                catch {wait -i $sid}
                return ""
            }
            # Host not found
            -re {Could not resolve hostname} {
                debug::log 1 "Could not resolve hostname"
                catch {close -i $sid}
                catch {wait -i $sid}
                return ""
            }
            # Any shell prompt (initial connection) - common patterns
            -re {[$#%>]\s*$} {
                debug::log 3 "Initial shell prompt received"
            }
            timeout {
                debug::log 1 "Connection timeout"
                catch {close -i $sid}
                catch {wait -i $sid}
                return ""
            }
            eof {
                debug::log 1 "Connection closed unexpectedly"
                catch {wait -i $sid}
                return ""
            }
        }

        # Initialize unique prompt
        if {![prompt::init $sid 0]} {
            debug::log 1 "Failed to initialize prompt"
            catch {close -i $sid}
            catch {wait -i $sid}
            return ""
        }

        # Track connection
        dict set connections $sid [dict create host $host user $user connected 1]

        debug::log 3 "Successfully connected to $user@$host"
        return $sid
    }

    # Close SSH connection
    proc disconnect {spawn_id} {
        variable connections

        debug::log 3 "Disconnecting spawn_id $spawn_id"

        # Send exit command
        catch {
            send -i $spawn_id "exit\r"
            expect -i $spawn_id -timeout 5 {
                eof { }
                timeout { }
            }
        }

        # Close the connection
        catch {close -i $spawn_id}
        catch {wait -i $spawn_id}

        # Update tracking
        if {[dict exists $connections $spawn_id]} {
            dict set connections $spawn_id connected 0
        }

        debug::log 3 "Disconnected"
    }

    # Check if connection is still active
    proc is_connected {spawn_id} {
        variable connections

        if {![dict exists $connections $spawn_id]} {
            return 0
        }

        if {![dict get $connections $spawn_id connected]} {
            return 0
        }

        # Get prompt marker for regex match
        set mypid $::prompt::mypid
        set result 0

        # Try to check if process is still running
        if {[catch {
            # Send an empty line and wait for prompt
            send -i $spawn_id "\r"
            # Use regex match that can find prompt marker anywhere in output
            expect -i $spawn_id -timeout 5 \
                -re "XPCT${mypid}> " {
                    set result 1
                } \
                -re "XPCT${mypid}# " {
                    set result 1
                } \
                timeout {
                    set result 0
                } \
                eof {
                    dict set connections $spawn_id connected 0
                    set result 0
                }
        } err]} {
            dict set connections $spawn_id connected 0
            return 0
        }

        return $result
    }
}
