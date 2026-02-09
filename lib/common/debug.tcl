# debug.tcl - Debug/logging infrastructure
#
# Provides: debug
# Debug levels 0-7 (0=off, 7=maximum verbosity)
#
# Procedures:
#   debug::init {level}     - Initialize debug level
#   debug::log {level msg}  - Log message if level <= current level
#   debug::set_level {n}    - Change debug level at runtime
#   debug::get_level {}     - Get current debug level

namespace eval debug {
    variable level 0

    # Debug level descriptions:
    # 0: Off (no debug output)
    # 1: Errors only
    # 2: Warnings
    # 3: Info (connection events)
    # 4: Verbose (command execution)
    # 5: Debug (expect patterns)
    # 6: Trace (all expect output)
    # 7: Maximum (internal state)

    # Initialize debug level
    proc init {lvl} {
        variable level
        if {$lvl < 0} {
            set lvl 0
        } elseif {$lvl > 7} {
            set lvl 7
        }
        set level $lvl
        if {$level >= 5} {
            log 5 "Debug initialized at level $level"
        }
    }

    # Log message if level <= current level
    proc log {lvl msg} {
        variable level
        if {$lvl <= $level} {
            set prefix ""
            switch $lvl {
                1 { set prefix "ERROR" }
                2 { set prefix "WARN" }
                3 { set prefix "INFO" }
                4 { set prefix "VERBOSE" }
                5 { set prefix "DEBUG" }
                6 { set prefix "TRACE" }
                7 { set prefix "MAX" }
            }
            puts stderr "\[$prefix\] $msg"
        }
    }

    # Change debug level at runtime
    proc set_level {n} {
        variable level
        if {$n < 0} {
            set n 0
        } elseif {$n > 7} {
            set n 7
        }
        set level $n
    }

    # Get current debug level
    proc get_level {} {
        variable level
        return $level
    }
}
