# utils.tcl - Common utilities
#
# Provides: utils
#
# Procedures:
#   utils::trim {str}                - Trim whitespace from string
#   utils::validate_filename {name}  - Check filename for dangerous chars
#   utils::escape_for_shell {str}    - Escape string for shell usage
#   utils::get_script_dir {}         - Get directory of current script

namespace eval utils {
    # Trim whitespace from both ends of string
    proc trim {str} {
        return [string trim $str]
    }

    # Validate filename for dangerous characters
    # Returns 1 if valid, 0 if contains dangerous chars
    proc validate_filename {name} {
        # Check for shell metacharacters that could allow injection
        if {[regexp {[;&|`$(){}[\]<>!\\]} $name]} {
            return 0
        }
        # Check for null bytes
        if {[string first "\x00" $name] >= 0} {
            return 0
        }
        return 1
    }

    # Escape string for safe shell usage (single-quote escaping)
    proc escape_for_shell {str} {
        # Replace single quotes with '\'' (end quote, escaped quote, start quote)
        regsub -all {'} $str {'\''} escaped
        return "'$escaped'"
    }

    # Get directory of current script
    proc get_script_dir {} {
        return [file dirname [file normalize [info script]]]
    }

    # Get library directory (parent of common/)
    proc get_lib_dir {} {
        set script_dir [get_script_dir]
        return [file dirname $script_dir]
    }

    # Get project root directory
    proc get_project_root {} {
        set lib_dir [get_lib_dir]
        return [file dirname $lib_dir]
    }

    # Check if a command exists on the system
    proc command_exists {cmd} {
        if {[catch {exec which $cmd} result]} {
            return 0
        }
        return 1
    }
}
