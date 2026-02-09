# test_utils.tcl - Common test utilities
#
# Provides test helper functions for assertions and setup

namespace eval test {
    variable test_count 0
    variable pass_count 0
    variable fail_count 0
    variable current_test ""

    # Initialize test suite
    proc init {name} {
        variable test_count
        variable pass_count
        variable fail_count
        variable current_test

        set test_count 0
        set pass_count 0
        set fail_count 0
        set current_test $name

        puts "=========================================="
        puts "Test Suite: $name"
        puts "=========================================="
    }

    # Start a test case
    proc start {name} {
        variable test_count
        variable current_test

        incr test_count
        set current_test $name
        puts -nonewline "Test $test_count: $name ... "
        flush stdout
    }

    # Mark test as passed
    proc pass {{msg ""}} {
        variable pass_count
        incr pass_count
        if {$msg ne ""} {
            puts "PASS ($msg)"
        } else {
            puts "PASS"
        }
    }

    # Mark test as failed
    proc fail {msg} {
        variable fail_count
        variable current_test
        incr fail_count
        puts "FAIL"
        puts "  Error: $msg"
    }

    # Assert equality
    proc assert_eq {expected actual {msg ""}} {
        if {$expected eq $actual} {
            pass $msg
            return 1
        } else {
            fail "Expected '$expected', got '$actual'"
            return 0
        }
    }

    # Assert not equal
    proc assert_ne {unexpected actual {msg ""}} {
        if {$unexpected ne $actual} {
            pass $msg
            return 1
        } else {
            fail "Expected not '$unexpected', but got that value"
            return 0
        }
    }

    # Assert true (non-zero/non-empty)
    proc assert_true {value {msg ""}} {
        if {$value} {
            pass $msg
            return 1
        } else {
            fail "Expected true, got false"
            return 0
        }
    }

    # Assert false (zero/empty)
    proc assert_false {value {msg ""}} {
        if {!$value} {
            pass $msg
            return 1
        } else {
            fail "Expected false, got true"
            return 0
        }
    }

    # Assert string contains substring
    proc assert_contains {haystack needle {msg ""}} {
        if {[string first $needle $haystack] >= 0} {
            pass $msg
            return 1
        } else {
            fail "String does not contain '$needle'"
            return 0
        }
    }

    # Assert string matches pattern
    proc assert_match {pattern value {msg ""}} {
        if {[regexp $pattern $value]} {
            pass $msg
            return 1
        } else {
            fail "Value '$value' does not match pattern '$pattern'"
            return 0
        }
    }

    # Print test summary and return exit code
    proc summary {} {
        variable test_count
        variable pass_count
        variable fail_count

        puts ""
        puts "=========================================="
        puts "Summary: $pass_count passed, $fail_count failed, $test_count total"
        puts "=========================================="

        return $fail_count
    }

    # Get project root directory
    proc get_project_root {} {
        set script_dir [file dirname [file normalize [info script]]]
        # Go up from tests/helpers to project root
        return [file dirname [file dirname $script_dir]]
    }

    # Get lib directory
    proc get_lib_dir {} {
        return [file join [get_project_root] "lib"]
    }

    # Source a library module
    proc source_lib {path} {
        set lib_dir [get_lib_dir]
        source [file join $lib_dir $path]
    }
}
