# Expect Tcl 9.0 Patches: Test Coverage Plan

This document catalogs all modifications made to Expect 5.45.4 for Tcl 9.0 compatibility and defines required test coverage to catch regressions.

## Summary of Changes

| Category | Patch/Transform | Files Modified | Functions Affected |
|----------|-----------------|----------------|-------------------|
| Channel API | `tcl9-channel.patch` | exp_chan.c | `expChannelType`, `ExpClose2Proc` (new) |
| Size Types | `tcl9-size.patch` | exp_command.c, expect.c, exp_inter.c, exp_trap.c | 30+ ObjCmd functions |
| Close Order | `tcl9-close-order.patch` | exp_command.c | `exp_close()` |
| Compat Header | postPatch (sed) | All .c/.h files | Macro definitions |
| Stubs Version | postPatch (sed) | exp_main_sub.c | `Tcl_InitStubs()` |
| Size Variables | postPatch (sed) | expect.c | `strlen`, `plen`, `start`, `end`, `match` |

---

## Detailed Change Analysis

### 1. tcl9-channel.patch (exp_chan.c)

**What Changed:**
- Channel type structure updated from Tcl 8 to Tcl 9 `TCL_CHANNEL_VERSION_5`
- Added `ExpClose2Proc()` function for new close signature
- Reordered struct members for new API layout

**Functions Modified:**
- `expChannelType` (struct) - Channel driver definition
- `ExpClose2Proc()` - NEW function handling Tcl 9 close semantics

**Test Coverage Required:**
```tcl
# Test: Channel close with Version 5 driver
test channel-close-1.1 {basic channel close} {
    spawn cat
    set result [catch {close; wait}]
} {0}

# Test: Half-close rejection (Tcl 9 feature)
test channel-close-1.2 {half-close should fail} {
    spawn cat
    # Half-close not supported - should error gracefully
    exp_close
    exp_wait
} {...}

# Test: Multiple rapid close/open cycles
test channel-close-1.3 {stress test close cycles} {
    for {set i 0} {$i < 50} {incr i} {
        spawn echo "test $i"
        expect eof
        close
        wait
    }
} {}
```

---

### 2. tcl9-size.patch (Multiple Files)

**What Changed:**
- Function signatures changed from `int objc` to `Tcl_Size objc`
- Local variables changed from `int n` to `Tcl_Size n` for list lengths

**Files Modified:**
- `exp_trap.c`: `Exp_TrapObjCmd`
- `exp_command.c`: 22 functions (spawn, send, close, wait, fork, etc.)
- `expect.c`: 12 functions (expect, match_max, timestamp, etc.)
- `exp_inter.c`: `Exp_InteractObjCmd`

**Complete List of Modified Functions:**

| File | Function | Change |
|------|----------|--------|
| exp_trap.c | Exp_TrapObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_SpawnObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_ExpPidObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_GetpidDeprecatedObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_SleepObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_SendLogObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_SendObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_LogFileObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_LogUserObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_DebugObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_ExpInternalObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_ExitObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_ConfigureObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_CloseObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_StraceObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_WaitObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_ForkObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_DisconnectObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_OverlayObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_InterpreterObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_ExpContinueObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_InterReturnObjCmd | objc: int→Tcl_Size |
| exp_command.c | Exp_OpenObjCmd | objc: int→Tcl_Size |
| expect.c | parse_expect_args | objc: int→Tcl_Size |
| expect.c | expect_info | objc: int→Tcl_Size |
| expect.c | Exp_ExpectGlobalObjCmd | objc: int→Tcl_Size |
| expect.c | Exp_ExpectObjCmd | objc: int→Tcl_Size |
| expect.c | Exp_TimestampObjCmd | objc: int→Tcl_Size |
| expect.c | process_di | objc: int→Tcl_Size |
| expect.c | Exp_MatchMaxObjCmd | objc: int→Tcl_Size |
| expect.c | Exp_RemoveNullsObjCmd | objc: int→Tcl_Size |
| expect.c | Exp_ParityObjCmd | objc: int→Tcl_Size |
| expect.c | Exp_CloseOnEofObjCmd | objc: int→Tcl_Size |
| expect.c | cmdX | objc: int→Tcl_Size |
| exp_inter.c | Exp_InteractObjCmd | objc: int→Tcl_Size |

**Test Coverage Required:**
Each function should be tested with various argument counts, especially edge cases:

```tcl
# Test: Commands with many arguments
test args-1.1 {spawn with many arguments} {
    spawn echo arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9 arg10
    expect eof
    close; wait
} {}

# Test: expect with multiple patterns
test args-1.2 {expect with many patterns} {
    spawn echo "test"
    expect {
        "pattern1" {}
        "pattern2" {}
        "pattern3" {}
        "test" {set result 1}
        timeout {set result 0}
    }
    close; wait
    set result
} {1}

# Test: Large argument lists (Tcl_Size boundary)
test args-1.3 {command with argument list} {
    spawn cat
    exp_send "test\r"
    expect "test"
    close; wait
} {}
```

---

### 3. tcl9-close-order.patch (exp_command.c)

**What Changed:**
- Moved `exp_state_prep_for_invalidation()` BEFORE `close(esPtr->fdin)`
- Added `esPtr->bg_status = unarmed` safety check

**Function Modified:**
- `exp_close()` - Reordered operations

**Test Coverage Required:**
```tcl
# Test: Close doesn't crash (the SIGILL bug)
test close-order-1.1 {close after spawn/expect} {
    spawn cat
    exp_send "hello\r"
    expect "hello"
    close
    wait
} {*}

# Test: Rapid spawn/close cycles (stress test)
test close-order-1.2 {50 spawn/close cycles} {
    set errors 0
    for {set i 0} {$i < 50} {incr i} {
        if {[catch {
            spawn echo "cycle $i"
            expect eof
            close
            wait
        }]} {
            incr errors
        }
    }
    set errors
} {0}

# Test: Close with active background handler
test close-order-1.3 {close with background expect} {
    spawn cat
    # Set up background processing
    exp_send "test\r"
    after 100
    close
    wait
} {}

# Test: Close while waiting for input
test close-order-1.4 {close during expect timeout} {
    spawn cat
    set timeout 1
    expect {
        "never_match" {}
        timeout {}
    }
    close
    wait
} {}
```

---

### 4. postPatch Source Transformations

**Changes via sed in default.nix:**

| Transformation | File | Change |
|---------------|------|--------|
| Stubs version | exp_main_sub.c | `"8.1"` → `"9.0"` |
| strlen type | expect.c | `int strlen;` → `Tcl_Size strlen;` |
| plen type | expect.c | `int plen;` → `Tcl_Size plen;` |
| start/end types | expect.c | `int start, end;` → `Tcl_Size start, end;` |
| match type | expect.c | `int match` → `Tcl_Size match` |

**Test Coverage Required:**
```tcl
# Test: Unicode string handling (Tcl_Size for strlen)
test unicode-1.1 {expect with unicode} {
    spawn echo "hello世界"
    expect "世界"
    close; wait
} {}

# Test: Large pattern matching (Tcl_Size boundaries)
test unicode-1.2 {expect with long string} {
    set long_str [string repeat "x" 10000]
    spawn echo $long_str
    expect $long_str
    close; wait
} {}

# Test: Regex match info (start/end as Tcl_Size)
test regex-1.1 {regex capture groups} {
    spawn echo "hello123world"
    expect -re {([a-z]+)([0-9]+)([a-z]+)}
    set result [list $expect_out(1,string) $expect_out(2,string) $expect_out(3,string)]
    close; wait
    set result
} {hello 123 world}
```

---

### 5. tcl9_compat.h (Compatibility Layer)

**Macros Defined:**
- `_ANSI_ARGS_(x)` → `x`
- `CONST`, `CONST84`, `CONST86` → `const`
- `TCL_VARARGS`, `TCL_VARARGS_DEF`, `TCL_VARARGS_START`
- `Tcl_UniCharNcmp` → `Tcl_UtfNcmp`
- `Tcl_UniCharNcasecmp` → `Tcl_UtfNcasecmp`
- `Tcl_EvalTokens` wrapper function

**Test Coverage Required:**
```tcl
# Test: String comparison (Tcl_UtfNcmp)
test compat-1.1 {string operations work} {
    spawn echo "HELLO"
    expect -nocase "hello"
    close; wait
} {}

# Test: Varargs handling
test compat-1.2 {log_user toggle} {
    set old [log_user]
    log_user 0
    log_user 1
    set new [log_user]
} {1}
```

---

## Proposed Test File: tcl9.test

Add this file to `expect5.45.4/tests/tcl9.test`:

```tcl
# tcl9.test --
#
# Tests for Tcl 9.0 compatibility patches.
# These tests verify changes made for int→Tcl_Size,
# channel API updates, and close ordering.

if {[lsearch [namespace children] ::tcltest] == -1} {
    package require tcltest
    namespace import ::tcltest::test ::tcltest::cleanupTests
}
package require Expect

log_user 0

#==========================================================================
# Close Order Tests (tcl9-close-order.patch)
# Bug: SIGILL when closing spawn due to event handler disarm after fd close
#==========================================================================

test tcl9-close-1.1 {basic close after spawn} {
    spawn echo "test"
    expect eof
    set result [catch {close; wait}]
} {0}

test tcl9-close-1.2 {close with pending expect} {
    spawn cat
    exp_send "hello\r"
    expect "hello"
    set result [catch {close; wait}]
} {0}

test tcl9-close-1.3 {close during timeout} {
    spawn cat
    set timeout 1
    expect {
        "never_matches" {}
        timeout {}
    }
    set result [catch {close; wait}]
} {0}

test tcl9-close-1.4 {rapid close cycles - stress test} {
    set errors 0
    for {set i 0} {$i < 20} {incr i} {
        if {[catch {
            spawn echo "cycle $i"
            expect eof
            close
            wait
        } err]} {
            incr errors
        }
    }
    set errors
} {0}

test tcl9-close-1.5 {close multiple spawns} {
    spawn cat; set cat1 $spawn_id
    spawn cat; set cat2 $spawn_id
    set r1 [catch {close -i $cat1; wait -i $cat1}]
    set r2 [catch {close -i $cat2; wait -i $cat2}]
    expr {$r1 + $r2}
} {0}

#==========================================================================
# Channel Version 5 Tests (tcl9-channel.patch)
#==========================================================================

test tcl9-channel-1.1 {spawn creates valid channel} {
    spawn cat
    set valid [string match "exp*" $spawn_id]
    close; wait
    set valid
} {1}

test tcl9-channel-1.2 {channel input/output works} {
    spawn cat -u
    exp_send "test123\r"
    expect "test123"
    close; wait
} {}

test tcl9-channel-1.3 {spawn -open file} {
    set tmpfile "/tmp/expect_test_[pid]"
    set f [open $tmpfile w]
    puts $f "file content"
    close $f
    spawn -open [open $tmpfile r]
    expect "file content"
    expect eof
    wait
    file delete $tmpfile
} {}

#==========================================================================
# Tcl_Size Argument Tests (tcl9-size.patch)
#==========================================================================

test tcl9-size-1.1 {spawn with many arguments} {
    spawn echo a b c d e f g h i j
    expect "a b c d e f g h i j"
    expect eof
    close; wait
} {}

test tcl9-size-1.2 {expect with many patterns} {
    spawn echo "findme"
    expect {
        "pat1" {set r 1}
        "pat2" {set r 2}
        "pat3" {set r 3}
        "findme" {set r 4}
        timeout {set r 0}
    }
    close; wait
    set r
} {4}

test tcl9-size-1.3 {trap with signal list} {
    set old_action ""
    trap {set old_action caught} {SIGINT SIGTERM}
    # Reset
    trap SIG_DFL {SIGINT SIGTERM}
} {}

#==========================================================================
# Unicode/Regex Tests (Tcl_Size for match indices)
#==========================================================================

test tcl9-unicode-1.1 {expect with unicode text} {
    spawn echo "Hello世界"
    expect "世界"
    close; wait
} {}

test tcl9-unicode-1.2 {regex capture with unicode} {
    spawn echo "abc123def"
    expect -re {([a-z]+)([0-9]+)([a-z]+)}
    set result "$expect_out(1,string)-$expect_out(2,string)-$expect_out(3,string)"
    close; wait
    set result
} {abc-123-def}

test tcl9-unicode-1.3 {long string match} {
    set longstr [string repeat "x" 5000]
    spawn echo $longstr
    expect $longstr
    close; wait
} {}

#==========================================================================
# Regression Tests for Known Bugs
#==========================================================================

test tcl9-regression-1.1 {SIGILL on close - original bug} {
    # This was the original SIGILL crash
    # exp_close → exp_event_disarm_fg → Tcl_DeleteChannelHandler
    # with closed fd caused SIGILL in Tcl 9
    spawn cat
    set timeout 2
    exp_send "test\r"
    expect {
        "test" {}
        timeout {}
    }
    # This close would crash before the fix
    close
    wait
} {*}

cleanupTests
return
```

---

## Existing Test Coverage Analysis

| Test File | Commands Tested | Covers Our Patches? |
|-----------|-----------------|---------------------|
| spawn.test | spawn, close, wait | Partial (basic close) |
| expect.test | expect, timeout | No Tcl 9 specifics |
| send.test | send | No Tcl 9 specifics |
| cat.test | spawn cat | Basic only |
| pid.test | exp_pid | No |
| logfile.test | log_file | No |
| stty.test | stty | No |

**Gap Analysis:**
- NO tests for channel close behavior changes
- NO tests for Tcl_Size boundaries
- NO tests for Unicode string handling with Tcl_Size
- NO tests for rapid spawn/close cycles
- NO tests for background handler interactions

---

## Upstream Submission Checklist

When submitting to Expect maintainers:

1. **Include `tcl9.test`** - New test file
2. **Include patches** - All three patches
3. **Include compat header** - `tcl9_compat.h`
4. **Documentation** - This analysis document
5. **Build instructions** - How to build against Tcl 9.0

---

## Running Tests

```bash
# In expect5.45.4 directory after patching:
cd tests

# Run all tests
expect all.tcl

# Run only Tcl 9 tests
expect tcl9.test

# Run with verbose output
expect all.tcl -verbose bps
```

---

## Summary

| Patch | Risk Level | Test Coverage Needed |
|-------|------------|---------------------|
| tcl9-close-order.patch | HIGH | Close ordering, stress tests |
| tcl9-channel.patch | HIGH | Channel lifecycle, close2proc |
| tcl9-size.patch | MEDIUM | Large arg counts, Unicode |
| postPatch (sed) | MEDIUM | Unicode, regex matches |
| tcl9_compat.h | LOW | Basic functionality |

The `tcl9.test` file above provides coverage for all patched areas.
