# cat_file.tcl - File content retrieval
#
# Provides: commands::cat_file
#
# Procedures:
#   commands::cat_file::read {spawn_id filename} - Cat file, return contents

namespace eval commands::cat_file {
    # Read file contents from remote system
    # Returns file contents on success, empty string on failure
    proc read {spawn_id filename} {
        debug::log 4 "Reading file: $filename"

        # Validate filename for security
        if {![utils::validate_filename $filename]} {
            debug::log 1 "Invalid characters in filename: $filename"
            error "Invalid characters in filename"
        }

        # Escape filename for safe shell usage
        set escaped_filename [utils::escape_for_shell $filename]

        set output [prompt::run $spawn_id "cat $escaped_filename"]

        # Check for common error messages in output
        if {[regexp {No such file or directory} $output]} {
            debug::log 1 "File not found: $filename"
            return ""
        }
        if {[regexp {Permission denied} $output]} {
            debug::log 1 "Permission denied: $filename"
            return ""
        }
        if {[regexp {Is a directory} $output]} {
            debug::log 1 "Is a directory: $filename"
            return ""
        }

        debug::log 4 "Successfully read [string length $output] bytes from $filename"
        return $output
    }

    # Check if file exists on remote system
    proc exists {spawn_id filename} {
        debug::log 5 "Checking if file exists: $filename"

        # Validate filename for security
        if {![utils::validate_filename $filename]} {
            debug::log 1 "Invalid characters in filename: $filename"
            return 0
        }

        set escaped_filename [utils::escape_for_shell $filename]
        set output [prompt::run $spawn_id "test -f $escaped_filename && echo EXISTS || echo NOTFOUND"]
        set result [string trim $output]

        if {$result eq "EXISTS"} {
            return 1
        }
        return 0
    }

    # Check if path is readable
    proc is_readable {spawn_id filename} {
        debug::log 5 "Checking if file is readable: $filename"

        # Validate filename for security
        if {![utils::validate_filename $filename]} {
            debug::log 1 "Invalid characters in filename: $filename"
            return 0
        }

        set escaped_filename [utils::escape_for_shell $filename]
        set output [prompt::run $spawn_id "test -r $escaped_filename && echo READABLE || echo NOTREADABLE"]
        set result [string trim $output]

        if {$result eq "READABLE"} {
            return 1
        }
        return 0
    }
}
