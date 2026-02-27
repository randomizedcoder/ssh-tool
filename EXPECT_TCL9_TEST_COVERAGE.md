# Expect Tcl 9 Test Coverage Analysis

Based on "Exploring Expect" book table of contents.

## Test Summary

**Total Tests: 61** (all passing)
**Full Suite: 90** (including standard Expect tests)

## Coverage by Book Chapter

| Chapter | Topic | Tests | Coverage |
|---------|-------|-------|----------|
| 4 | Glob Patterns | 4.1-4.3 | Exact, glob wildcards, character classes |
| 5 | Regular Expressions | 4.4-4.7 | Capture groups, -indices, anchors, long patterns |
| 6 | Patterns, Actions, Limits | 5.1-5.6 | timeout, timeout=0, match_max, -d, notransfer, exp_continue |
| 10-11 | Multiple Processes | 6.1-6.5 | -i flag, spawn_id list, switch, close ordering, stress test |
| 12 | Send | 7.1-7.5 | Basic, null chars, explicit -i, send_log, multiple lines |
| 13 | Spawn | 8.1-8.5 | -noecho, return pid, slave name, -open pipe, exp_pid |
| 14 | Signals | 9.1-9.4 | trap syntax, multiple signals, SIG_IGN, code blocks |
| 23 | Miscellaneous | 10.1-10.6 | close_on_eof, remove_nulls, parity, log_user |

## Tcl 9 Specific Coverage

### Close Order (tcl9-close-order.patch)
| Test | Description | Risk Addressed |
|------|-------------|----------------|
| 1.1-1.6 | Close sequences | SIGILL crash on close |
| 11.2 | Close immediately after spawn | Channel setup race |
| 11.3 | Expect eof then close | Auto-close handling |
| 11.5 | Multiple close attempts | Error handling |
| 12.1-12.2 | Regression tests | Original bug reproduction |

### Channel API (tcl9-channel.patch)
| Test | Description | Risk Addressed |
|------|-------------|----------------|
| 2.1-2.4 | Channel creation and I/O | TCL_CHANNEL_VERSION_5 |
| 8.4 | spawn -open with pipe | Channel wrapping |

### Tcl_Size Changes (tcl9-size.patch)
| Test | Description | Risk Addressed |
|------|-------------|----------------|
| 3.1 | spawn with many arguments | objc overflow |
| 3.2 | expect with many patterns | Pattern list handling |
| 3.3 | Long string handling | String length overflow |
| 4.7 | Long pattern match | Tcl_Size boundaries |
| 9.1-9.4 | Trap signal lists | Signal list parsing |

## Race Condition Tests

| Test | Scenario |
|------|----------|
| 11.1 | Rapid send without expect |
| 11.2 | Close immediately after spawn |
| 11.4 | Timeout during rapid input |
| 11.5 | Multiple close attempts |
| 11.6 | Wait without close on short-lived process |

## Patched Functions Coverage

### From tcl9-size.patch (Tcl_Size objc changes)

| Function | File | Test Coverage |
|----------|------|---------------|
| Exp_SpawnObjCmd | exp_command.c | 3.1, 8.1-8.5 |
| Exp_SendObjCmd | exp_command.c | 7.1-7.5 |
| Exp_ExpectObjCmd | expect.c | 3.2, 4.1-4.7, 5.1-5.6 |
| Exp_TrapObjCmd | exp_trap.c | 9.1-9.4 |
| Exp_CloseObjCmd | exp_command.c | 1.1-1.6, 11.2-11.5 |
| Exp_WaitObjCmd | exp_command.c | 1.1-1.6, 11.6 |
| Exp_InteractObjCmd | exp_inter.c | (not interactive) |
| Exp_LogFileObjCmd | exp_command.c | 7.4 |
| Exp_LogUserObjCmd | exp_command.c | 10.6 |
| Exp_MatchMaxObjCmd | expect.c | 5.3-5.4 |
| Exp_RemoveNullsObjCmd | expect.c | 10.3-10.4 |
| Exp_ParityObjCmd | expect.c | 10.5 |
| Exp_CloseOnEofObjCmd | expect.c | 10.1-10.2 |
| Exp_ExpPidObjCmd | exp_command.c | 8.5 |
| Exp_TimestampObjCmd | expect.c | (implicit) |

### From tcl9-close-order.patch

| Function | File | Test Coverage |
|----------|------|---------------|
| exp_close | exp_command.c | 1.1-1.6, 6.4, 11.2-11.5, 12.1-12.2 |

### From tcl9-channel.patch

| Function | File | Test Coverage |
|----------|------|---------------|
| ExpClose2Proc | exp_chan.c | 2.1-2.4, all close tests |
| ExpCloseProc | exp_chan.c | (deprecated, forwarded to Close2) |

## Gaps and Limitations

### Not Testable in Automated Build
- **Interact commands** (Ch 15-16): Requires interactive terminal
- **expect_user/expect_tty**: Requires real tty
- **send_tty**: Requires real tty
- **Expectk** (Ch 19): Requires Tk

### Lower Priority (Medium Risk)
- send_slow / send_human: Timing dependent
- Full stty coverage: Platform dependent
- exp_internal debugging: Output verification

## Running Tests

```bash
# Build with tests
nix-build nix/expect-tcl9 --no-out-link

# View test output
nix log $(nix-build nix/expect-tcl9 --no-out-link 2>&1 | tail -1)
```

## Test Design Principles

1. **Follow Expect conventions**: Tests mirror patterns from spawn.test
2. **Focus on Tcl 9 changes**: Every patched function has coverage
3. **Race conditions**: Tests for timing-sensitive operations
4. **Regression tests**: Specific tests for bugs found during porting
5. **No SIGILL**: All close paths tested for crash prevention
