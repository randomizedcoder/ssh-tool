# mcp/lib/security.tcl - Security validation layer
#
# CRITICAL: All commands and paths MUST pass through this module.
# There is NO bypass. Security is mandatory, not optional.
#
# This module implements:
# - Command allowlist validation
# - Dangerous pattern blocking
# - Path access control
# - Rate limiting

package require Tcl 8.6-

namespace eval ::mcp::security {
    #=========================================================================
    # COMMAND ALLOWLIST (Lines 15-45)
    # Commands not matching ANY pattern are REJECTED.
    # NOTE: find, awk, sed, xargs are deliberately EXCLUDED due to exec capabilities
    #=========================================================================

    variable allowed_commands [list \
        {^ls(\s|$)}               \
        {^cat\s+}                 \
        {^head(\s|$)}             \
        {^tail(\s|$)}             \
        {^grep\s+}                \
        {^df(\s|$)}               \
        {^du(\s|$)}               \
        {^ps(\s|$)}               \
        {^top\s+-bn1}             \
        {^hostname(\s|$)}         \
        {^uname(\s|$)}            \
        {^whoami$}                \
        {^id$}                    \
        {^date$}                  \
        {^uptime$}                \
        {^pwd$}                   \
        {^stat\s+}                \
        {^file\s+}                \
        {^wc(\s|$)}               \
        {^sort(\s|$)}             \
        {^uniq(\s|$)}             \
        {^cut(\s|$)}              \
        {^printenv(\s|$)}         \
        {^free(\s|$)}             \
        {^vmstat(\s|$)}           \
        {^netstat\s+-[tlnpa]+}    \
        {^ss\s+-[tlnpa]+}         \
        {^lsof(\s|$)}             \
        {^mount$}                 \
        {^lsblk(\s|$)}            \
        {^blkid(\s|$)}            \
        \
        \
        {^ip\s+(-[46])?\s*(-j(son)?)?\s*(-d(etails)?)?\s*(-s(tat(istics)?)?)?\s*(link|addr|address|route|rule|neigh|neighbor|tunnel|maddr|vrf)\s+(show|list)(\s|$)} \
        {^ip\s+(-j)?\s*netns\s+(list|identify)(\s|$)} \
        {^ip\s+(-j)?\s*-n\s+[a-zA-Z0-9_-]+\s+(link|addr|route)\s+show(\s|$)} \
        \
        {^ethtool\s+(-[Sikgacmn]|-T)?\s*[a-zA-Z0-9@_-]+$} \
        \
        {^tc\s+(-[js])?\s*(qdisc|class|filter|action)\s+show(\s|$)} \
        \
        {^nft\s+(-j)?\s*list\s+(ruleset|tables|table|chain|set|map)(\s|$)} \
        \
        {^ip6?tables\s+(-t\s+(filter|nat|mangle|raw|security)\s+)?-[LnvS]+(\s|$)} \
        \
        {^bridge\s+(-j)?\s*(link|fdb|vlan|mdb)\s+show(\s|$)} \
        \
        {^conntrack\s+-L(\s|$)} \
        \
        {^sysctl\s+(-a\s+)?net\.} \
        \
        {^dig\s+(\+short\s+)?[a-zA-Z0-9_][a-zA-Z0-9._-]+$} \
        {^nslookup\s+[a-zA-Z0-9][a-zA-Z0-9._-]+$} \
        {^host\s+[a-zA-Z0-9][a-zA-Z0-9._-]+$} \
        \
        {^ping6?\s+-c\s+[1-5]\s+[a-zA-Z0-9][a-zA-Z0-9._-]+$} \
        \
        {^traceroute6?\s+-m\s+([1-9]|1[0-5])\s+[a-zA-Z0-9][a-zA-Z0-9._-]+$} \
        \
        {^mtr\s+--report\s+-c\s+[1-5]\s+[a-zA-Z0-9][a-zA-Z0-9._-]+$} \
        {^mtr\s+-c\s+[1-5]\s+--report\s+[a-zA-Z0-9][a-zA-Z0-9._-]+$} \
    ]

    #=========================================================================
    # BLOCKED PATTERNS (Lines 47-95)
    # These are ALWAYS blocked, defense in depth.
    # Even if command is in allowlist, these patterns block it.
    #=========================================================================

    variable blocked_patterns [list \
        {[/\\]}                              \
        {\|}                                 \
        {;}                                  \
        {&&}                                 \
        {\|\|}                               \
        {\$\(}                               \
        {`}                                  \
        {>}                                  \
        {<}                                  \
        {\bfind\b}                           \
        {\bawk\b}                            \
        {\bgawk\b}                           \
        {\bsed\b}                            \
        {\bxargs\b}                          \
        {\benv\b}                            \
        {\bexec\b}                           \
        {\beval\b}                           \
        {\bsource\b}                         \
        {\brm\b}                             \
        {\bmkdir\b}                          \
        {\brmdir\b}                          \
        {\bmv\b}                             \
        {\bcp\b}                             \
        {\bln\b}                             \
        {\bchmod\b}                          \
        {\bchown\b}                          \
        {\bchgrp\b}                          \
        {\bdd\b}                             \
        {\bmkfs\b}                           \
        {\bsudo\b}                           \
        {\bsu\b}                             \
        {\bpython\b}                         \
        {\bpython[0-9]\b}                    \
        {\bperl\b}                           \
        {\bruby\b}                           \
        {\bphp\b}                            \
        {\bnode\b}                           \
        {\bnodejs\b}                         \
        {\blua\b}                            \
        {\btclsh\b}                          \
        {\bwish\b}                           \
        {\bexpect\b}                         \
        {\bsh\b}                             \
        {\bbash\b}                           \
        {\bzsh\b}                            \
        {\bcsh\b}                            \
        {\bksh\b}                            \
        {\bfish\b}                           \
        {\bnc\b}                             \
        {\bnetcat\b}                         \
        {\bncat\b}                           \
        {\bsocat\b}                          \
        {\bcurl\b}                           \
        {\bwget\b}                           \
        {\bssh\b}                            \
        {\bscp\b}                            \
        {\bsftp\b}                           \
        {\brsync\b}                          \
        {\bftp\b}                            \
        {\btelnet\b}                         \
        {\bkill\b}                           \
        {\bpkill\b}                          \
        {\bkillall\b}                        \
        {\bfirewall-cmd\b}                   \
        {\bufw\b}                            \
        {\bpasswd\b}                         \
        {\buseradd\b}                        \
        {\buserdel\b}                        \
        {\busermod\b}                        \
        {\bgroupadd\b}                       \
        {\bgroupdel\b}                       \
        {\bvisudo\b}                         \
        {\bsystemctl\b}                      \
        {\bservice\b}                        \
        {\binit\b}                           \
        {\bshutdown\b}                       \
        {\breboot\b}                         \
        {\bhalt\b}                           \
        {\bpoweroff\b}                       \
        {\bcrontab\b}                        \
        {\bat\b}                             \
        {\bbatch\b}                          \
        {[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]}   \
        \
        \
        {\bip\s+.*\s+(add|del|delete|change|replace|set|flush|append)\b} \
        \
        {\btc\s+.*\s+(add|del|delete|change|replace)\b} \
        \
        {\bnft\s+.*\s+(add|delete|insert|replace|flush|destroy|create)\b} \
        \
        {\bip6?tables\s+.*(-[ADIRF]|--append|--delete|--insert|--replace|--flush)\b} \
        \
        {\bethtool\s+.*-[EefWKACGLspPuU]} \
        {\bethtool\s+.*--flash}              \
        {\bethtool\s+.*--change}             \
        {\bethtool\s+.*--set}                \
        {\bethtool\s+.*--reset}              \
        \
        {\bping\s+.*-[fiaAQrRs]}             \
        {\bping\s+-c\s*([6-9]|[1-9][0-9]+)}  \
        {\bping\s+.*-[iw]\s*0}               \
        {\btraceroute\s+.*-[gis]}            \
        \
        {\bmtr\s+(?!.*--report)}             \
        {\bmtr\s+.*-c\s*([6-9]|[1-9][0-9]+)} \
        \
        {\bdig\s+.*AXFR}                     \
        {\bdig\s+.*-x\s}                     \
        {\bdig\s+.*\+trace}                  \
        \
        {^host\s+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+} \
        {^nslookup\s+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+} \
    ]

    # Maximum command length
    variable max_command_length 1024

    #=========================================================================
    # PATH ALLOWLIST (Lines 100-120)
    #=========================================================================

    variable allowed_paths [list \
        "/etc"       \
        "/var/log"   \
        "/home"      \
        "/tmp"       \
        "/opt"       \
        "/usr/share" \
        "/proc"      \
        "/sys"       \
    ]

    variable forbidden_paths [list \
        "/etc/shadow"         \
        "/etc/shadow-"        \
        "/etc/passwd-"        \
        "/etc/gshadow"        \
        "/etc/gshadow-"       \
        "/etc/sudoers"        \
        "/etc/sudoers.d"      \
        "/etc/ssh/ssh_host_*" \
        "/root"               \
        "/home/*/.ssh/id_*"   \
        "/home/*/.ssh/authorized_keys" \
        "/home/*/.gnupg"      \
        "/home/*/.netrc"      \
        "/home/*/.bash_history" \
        "/proc/*/mem"         \
        "/proc/kcore"         \
        "/sys/kernel/security" \
    ]

    # Maximum path length
    variable max_path_length 512

    #=========================================================================
    # RATE LIMITING (Lines 125-145)
    #=========================================================================

    variable rate_limits    ;# dict: client_id -> {count reset_time}
    variable rate_limit 100 ;# requests per minute
    variable rate_window 60 ;# seconds

    #=========================================================================
    # COMMAND VALIDATION (Lines 150-210)
    #=========================================================================

    # @param cmd The command string to validate
    # @return 1 if allowed, throws error if blocked
    proc validate_command {cmd} {
        variable allowed_commands
        variable blocked_patterns
        variable max_command_length

        # Normalize whitespace
        set cmd [string trim $cmd]

        # Empty command is rejected
        if {$cmd eq ""} {
            _log_security "Empty command rejected" {}
            error "SECURITY: Empty command not permitted"
        }

        # Length check
        if {[string length $cmd] > $max_command_length} {
            _log_security "Command too long" [dict create length [string length $cmd]]
            error "SECURITY: Command exceeds maximum length of $max_command_length characters"
        }

        # STEP 1: Check blocked patterns (defense in depth)
        foreach pattern $blocked_patterns {
            if {[regexp -- $pattern $cmd]} {
                _log_security "Blocked dangerous command" \
                    [dict create command [_truncate $cmd 50] pattern $pattern]
                error "SECURITY: Command matches blocked pattern"
            }
        }

        # STEP 2: Command MUST match an allowed pattern
        set matched 0
        set matched_pattern ""
        foreach pattern $allowed_commands {
            if {[regexp -- $pattern $cmd]} {
                set matched 1
                set matched_pattern $pattern
                break
            }
        }

        if {!$matched} {
            _log_security "Command not in allowlist" \
                [dict create command [_truncate $cmd 50]]
            error "SECURITY: Command not in allowlist"
        }

        _log_debug "Command permitted" \
            [dict create command [_truncate $cmd 50] pattern $matched_pattern]

        return 1
    }

    #=========================================================================
    # PATH VALIDATION (Lines 215-280)
    #=========================================================================

    # @param path The file path to validate
    # @return Normalized path if allowed, throws error if blocked
    proc validate_path {path} {
        variable allowed_paths
        variable forbidden_paths
        variable max_path_length

        # Check for null bytes (injection attempt)
        if {[string first "\x00" $path] >= 0} {
            _log_security "Null byte in path" [dict create path $path]
            error "SECURITY: Invalid path - null byte detected"
        }

        # Check for control characters
        if {[regexp {[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]} $path]} {
            _log_security "Control character in path" [dict create path $path]
            error "SECURITY: Invalid path - control character detected"
        }

        # Check for newlines (command injection via path)
        if {[string first "\n" $path] >= 0 || [string first "\r" $path] >= 0} {
            _log_security "Newline in path" [dict create path $path]
            error "SECURITY: Invalid path - newline detected"
        }

        # Length check
        if {[string length $path] > $max_path_length} {
            _log_security "Path too long" [dict create length [string length $path]]
            error "SECURITY: Path exceeds maximum length of $max_path_length characters"
        }

        # Normalize path (resolves .. and .)
        set normalized [file normalize $path]

        # Check forbidden paths first
        foreach pattern $forbidden_paths {
            if {[string match $pattern $normalized]} {
                _log_security "Forbidden path accessed" \
                    [dict create path $normalized pattern $pattern]
                error "SECURITY: Access to path forbidden"
            }
        }

        # Check if under allowed directory
        set allowed 0
        foreach base $allowed_paths {
            if {$normalized eq $base || [string match "${base}/*" $normalized]} {
                set allowed 1
                break
            }
        }

        if {!$allowed} {
            _log_security "Path not in allowed directories" \
                [dict create path $normalized]
            error "SECURITY: Path not in allowed directories"
        }

        _log_debug "Path permitted" [dict create path $normalized]

        return $normalized
    }

    #=========================================================================
    # RATE LIMITING (Lines 285-330)
    #=========================================================================

    proc check_rate_limit {client_id} {
        variable rate_limits
        variable rate_limit
        variable rate_window

        set now [clock seconds]

        if {![info exists rate_limits]} {
            set rate_limits [dict create]
        }

        if {[dict exists $rate_limits $client_id]} {
            set data [dict get $rate_limits $client_id]
            set reset_time [dict get $data reset_time]
            set count [dict get $data count]

            if {$now >= $reset_time} {
                # Window expired, reset
                dict set rate_limits $client_id \
                    [dict create count 1 reset_time [expr {$now + $rate_window}]]
                return 1
            }

            if {$count >= $rate_limit} {
                set retry_after [expr {$reset_time - $now}]
                _log_security "Rate limit exceeded" \
                    [dict create client_id $client_id retry_after $retry_after]
                error "SECURITY: Rate limit exceeded, retry after $retry_after seconds"
            }

            dict set rate_limits $client_id \
                [dict create count [incr count] reset_time $reset_time]
        } else {
            dict set rate_limits $client_id \
                [dict create count 1 reset_time [expr {$now + $rate_window}]]
        }

        return 1
    }

    # Reset rate limits (for testing)
    proc reset_rate_limits {} {
        variable rate_limits
        set rate_limits [dict create]
    }

    #=========================================================================
    # HELPER FUNCTIONS (Lines 335-360)
    #=========================================================================

    proc _truncate {str maxlen} {
        if {[string length $str] <= $maxlen} {
            return $str
        }
        return "[string range $str 0 [expr {$maxlen - 4}]]..."
    }

    proc _log_security {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::warn $msg $data
        }
    }

    proc _log_debug {msg data} {
        if {[namespace exists ::mcp::log]} {
            ::mcp::log::debug $msg $data
        }
    }

    #=========================================================================
    # PRIVACY FILTER (Lines 400-450)
    # Reference: DESIGN_NETWORK_COMMANDS.md Section "Privacy Mode"
    #=========================================================================

    proc apply_privacy_filter {output privacy_level} {
        switch $privacy_level {
            "none" {
                return $output
            }
            "standard" {
                # Mask RFC1918 internal addresses (keep prefix for context)
                # 10.x.x.x -> 10.x.x
                set output [regsub -all {(10\.)[0-9]+\.[0-9]+\.[0-9]+} $output {\1x.x.x}]
                # 172.16-31.x.x -> 172.16.x.x
                set output [regsub -all {(172\.(1[6-9]|2[0-9]|3[01])\.)[0-9]+\.[0-9]+} $output {\1x.x}]
                # 192.168.x.x -> 192.168.x.x
                set output [regsub -all {(192\.168\.)[0-9]+\.[0-9]+} $output {\1x.x}]

                # Mask ephemeral ports (>32767)
                set output [regsub -all {:([3-6][0-9]{4})([^0-9]|$)} $output {:xxxxx\2}]

                # Mask MAC addresses (keep OUI - first 3 octets)
                set output [regsub -all {([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:)[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}} $output {\1xx:xx:xx}]

                return $output
            }
            "strict" {
                # First, mask all MAC addresses to protect them from port masking
                set output [regsub -all {[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}} $output {xx:xx:xx:xx:xx:xx}]

                # Mask all IPs except loopback (127.x.x.x)
                # First, protect loopback by marking it
                set output [regsub -all {127\.0\.0\.[0-9]+} $output {__LOOPBACK__}]
                # Mask all other IPs
                set output [regsub -all {[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+} $output {x.x.x.x}]
                # Restore loopback
                set output [regsub -all {__LOOPBACK__} $output {127.0.0.1}]

                # Mask all ports (IP:port format)
                set output [regsub -all {:([0-9]+)([^0-9:]|$)} $output {:xxxxx\2}]

                return $output
            }
            default {
                return $output
            }
        }
    }
}

package provide mcp::security 1.0
