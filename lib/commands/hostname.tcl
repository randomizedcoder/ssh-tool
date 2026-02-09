# hostname.tcl - Hostname retrieval
#
# Provides: commands::hostname
#
# Procedures:
#   commands::hostname::get {spawn_id} - Run hostname, return result

namespace eval commands::hostname {
    # Get hostname from remote system
    # Returns hostname string on success, empty string on failure
    proc get {spawn_id} {
        debug::log 4 "Getting hostname"

        set output [prompt::run $spawn_id "hostname"]
        set result [string trim $output]

        if {$result eq ""} {
            debug::log 2 "hostname command returned empty output"
            return ""
        }

        debug::log 4 "Hostname: $result"
        return $result
    }

    # Get fully qualified domain name
    proc get_fqdn {spawn_id} {
        debug::log 4 "Getting FQDN"

        set output [prompt::run $spawn_id "hostname -f 2>/dev/null || hostname"]
        set result [string trim $output]

        if {$result eq ""} {
            debug::log 2 "FQDN command returned empty output"
            return ""
        }

        debug::log 4 "FQDN: $result"
        return $result
    }
}
