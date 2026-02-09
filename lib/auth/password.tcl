# password.tcl - User password handling
#
# Provides: auth::password
#
# Procedures:
#   auth::password::get {}   - Returns user password
#                              Reads PASSWORD env var or prompts user
#   auth::password::clear {} - Clears stored password from memory

namespace eval auth::password {
    variable stored_password ""
    variable password_set 0

    # Get user password
    # Checks PASSWORD environment variable first
    # Falls back to secure terminal prompt
    proc get {} {
        variable stored_password
        variable password_set

        # Return cached password if already set
        if {$password_set} {
            return $stored_password
        }

        # Check environment variable first
        if {[info exists ::env(PASSWORD)] && $::env(PASSWORD) ne ""} {
            set stored_password $::env(PASSWORD)
            set password_set 1
            debug::log 5 "Password retrieved from PASSWORD environment variable"
            return $stored_password
        }

        # Prompt user for password
        set stored_password [prompt_for_password "SSH Password: "]
        set password_set 1
        return $stored_password
    }

    # Prompt user for password with hidden input
    proc prompt_for_password {prompt_text} {
        # Save current terminal settings
        if {[catch {set old_stty [exec stty -g]} err]} {
            # Fallback if stty not available
            puts -nonewline stderr $prompt_text
            flush stderr
            gets stdin password
            return $password
        }

        # Disable echo
        catch {exec stty -echo}

        puts -nonewline stderr $prompt_text
        flush stderr
        gets stdin password

        # Restore terminal settings
        catch {exec stty $old_stty}
        puts stderr ""

        return $password
    }

    # Clear stored password from memory
    proc clear {} {
        variable stored_password
        variable password_set

        # Overwrite with empty string
        set stored_password ""
        set password_set 0
        debug::log 5 "Password cleared from memory"
    }

    # Check if password is available (without prompting)
    proc is_available {} {
        variable password_set
        if {$password_set} {
            return 1
        }
        if {[info exists ::env(PASSWORD)] && $::env(PASSWORD) ne ""} {
            return 1
        }
        return 0
    }
}
