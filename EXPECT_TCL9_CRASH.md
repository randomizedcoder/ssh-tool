# Expect 5.45.4 + Tcl 9.0 SIGILL Crash: Analysis and Fix

**Severity**: CRITICAL
**Status**: FIXED
**Created**: 2026-02-17
**Fixed**: 2026-02-18
**Component**: nix/expect-tcl9/

## Executive Summary

Expect 5.45.4 compiled against Tcl 9.0 crashes with SIGILL (illegal instruction) when closing spawn channels. The root cause is a **use-after-close bug** in `exp_close()` where event handlers are disarmed AFTER the underlying file descriptor is closed. Tcl 9.0's `Tcl_DeleteChannelHandler()` now accesses the fd during cleanup, triggering the crash.

**Fix**: Patch `exp_command.c` to disarm event handlers BEFORE closing file descriptors.

---

## The Problem

### Symptoms

When closing an SSH spawn in Expect (Tcl 9.0), the process crashes:

```
fstat: Bad file descriptor
traps: .expect-wrapped[811] trap invalid opcode ip:7f187c2c2911 sp:7ffe10277bd0 error:0 in libtcl9.0.so
```

### Stack Trace

```
Process 811 (.expect-wrapped) of user 0 dumped core.
#3  0x00007f187c3c2fa1 exp_event_disarm_fg (libexpect5.45.4.so + 0x26fa1)
#4  0x00007f187c3a87a1 exp_close (libexpect5.45.4.so + 0xc7a1)
```

### Reproduction

```tcl
package require Expect
spawn ssh -p 2222 testuser@target
expect "password:"
send "testpass\r"
expect "$ "
close  ;# CRASH: SIGILL
```

---

## Root Cause Analysis

### The Bug Location

File: `exp_command.c`, function `exp_close()` (lines 322-398)

### Original Code Flow (Buggy)

```c
exp_close(Tcl_Interp *interp, ExpState *esPtr)
{
    // Step 1: Flush channel
    Tcl_Flush(esPtr->channel);

    // Step 2: Close file descriptors  <-- FDs CLOSED HERE
    close(esPtr->fdin);
    if (esPtr->fd_slave != EXP_NOFD) close(esPtr->fd_slave);
    if (esPtr->fdin != esPtr->fdout) close(esPtr->fdout);

    // ... other cleanup ...

    // Step 3: Disarm event handlers  <-- TOO LATE! FDs already closed
    exp_state_prep_for_invalidation(interp, esPtr);
      → exp_event_disarm_fg(esPtr)
        → Tcl_DeleteChannelHandler(esPtr->channel, ...)  // CRASH!
}
```

### Why This Worked in Tcl 8.x

In Tcl 8.x, `Tcl_DeleteChannelHandler()` only manipulated internal data structures. It didn't access the underlying file descriptor.

### Why This Crashes in Tcl 9.0

Tcl 9.0 made significant changes to channel handling. `Tcl_DeleteChannelHandler()` now performs validation that accesses the underlying fd:

1. Call `Tcl_DeleteChannelHandler(channel, ...)`
2. Tcl 9 internally calls `fstat(fd, ...)` to validate channel state
3. But `fd` was already closed by `close(esPtr->fdin)`
4. `fstat()` fails with "Bad file descriptor"
5. Tcl's internal state becomes corrupted
6. SIGILL when executing corrupted code path

### The Key Insight

The order of operations matters:
- **Tcl 8.x**: Close fd → Disarm handlers ✓ (handlers don't touch fd)
- **Tcl 9.0**: Close fd → Disarm handlers ✗ (handlers DO touch fd)

---

## The Fix

### Patch: `tcl9-close-order.patch`

```diff
--- a/exp_command.c
+++ b/exp_command.c
@@ -336,6 +336,14 @@ exp_close(
        written now! */
     Tcl_Flush(esPtr->channel);

+    /*
+     * Tcl 9 fix: Disarm event handlers BEFORE closing file descriptors.
+     * In Tcl 9, Tcl_DeleteChannelHandler accesses the underlying fd,
+     * so we must disarm while the fd is still valid.
+     */
+    exp_state_prep_for_invalidation(interp,esPtr);
+    esPtr->bg_status = unarmed;  /* Ensure bg handler won't fire */
+
     /*
      * Ignore close errors from ptys.  Ptys on some systems return errors for
      * no evident reason.  Anyway, receiving an error upon pty-close doesn't
@@ -382,8 +390,6 @@ exp_close(
     }
 #endif

-    exp_state_prep_for_invalidation(interp,esPtr);
-
     if (esPtr->user_waited) {
 	if (esPtr->registered) {
 	    Tcl_UnregisterChannel(interp,esPtr->channel);
```

### Corrected Code Flow

```c
exp_close(Tcl_Interp *interp, ExpState *esPtr)
{
    // Step 1: Flush channel
    Tcl_Flush(esPtr->channel);

    // Step 2: Disarm event handlers FIRST (while fd is still valid!)
    exp_state_prep_for_invalidation(interp, esPtr);
    esPtr->bg_status = unarmed;

    // Step 3: NOW safe to close file descriptors
    close(esPtr->fdin);
    if (esPtr->fd_slave != EXP_NOFD) close(esPtr->fd_slave);
    if (esPtr->fdin != esPtr->fdout) close(esPtr->fdout);

    // ... rest of cleanup ...
}
```

### Why `bg_status = unarmed`?

The additional line `esPtr->bg_status = unarmed` ensures background event handlers won't fire after we've started the close sequence. This prevents a race condition where a background handler might try to access the channel during shutdown.

---

## Files Modified

### Patch Files

| File | Purpose |
|------|---------|
| `nix/expect-tcl9/tcl9-close-order.patch` | Reorders close operations |

### Build Configuration

```nix
# nix/expect-tcl9/default.nix
patches = (pkgs.expect.patches or []) ++ [
  ./tcl9-channel.patch      # Channel driver: TCL_CHANNEL_VERSION_5
  ./tcl9-size.patch         # int → Tcl_Size for 64-bit compatibility
  ./tcl9-close-order.patch  # THIS FIX: disarm handlers before close
];
```

---

## Verification

### Test Script

File: `nix/expect-tcl9/tests/exp_close_crash.tcl`

```tcl
#!/usr/bin/env tclsh
package require Expect

puts "Testing exp_close with Tcl [info patchlevel]"

# Test: Multiple spawn/close cycles
for {set i 0} {$i < 10} {incr i} {
    spawn echo "cycle $i"
    expect eof
    close
    wait
}

puts "All tests passed - no SIGILL crash"
```

### Integration Test

```bash
nix build .#checks.x86_64-linux.integration --print-build-logs
# Exit code 0 = success (no SIGILL crash)
```

---

## Technical Details

### Affected Functions

| Function | File | Role |
|----------|------|------|
| `exp_close()` | exp_command.c | Main close routine |
| `exp_state_prep_for_invalidation()` | exp_command.c | Prepares state for cleanup |
| `exp_event_disarm_fg()` | exp_event.c | Removes foreground handler |
| `exp_event_disarm_bg()` | exp_event.c | Removes background handler |
| `Tcl_DeleteChannelHandler()` | Tcl 9.0 | Crashes if fd invalid |

### Tcl 9.0 API Changes

Tcl 9.0 introduced stricter channel validation. Key changes affecting Expect:

1. **Channel validation**: Operations validate fd before proceeding
2. **Close ordering**: Channel cleanup expects valid fd during handler removal
3. **Error paths**: Invalid fd triggers assertion/trap rather than silent failure

---

## Source References

**Expect 5.45.4 Source:**
- Download: https://downloads.sourceforge.net/project/expect/Expect/5.45.4/expect5.45.4.tar.gz
- Local copy: `/home/das/Downloads/expect9/expect5.45.4`

**Tcl 9.0 Documentation:**
- Release notes: https://www.tcl.tk/software/tcltk/9.0.html
- Channel API: https://www.tcl.tk/man/tcl9.0/TclLib/CrtChannel.html

**Related Work:**
- nixpkgs PR #490930: Expect with Tcl 9 support (pending upstream)

---

## Upstream Submission

This fix should be submitted to:
1. **Expect maintainers**: https://core.tcl-lang.org/expect/
2. **nixpkgs**: As part of PR #490930

The fix is backwards compatible - it also works correctly with Tcl 8.x since disarming handlers before closing fds is the safer ordering regardless of Tcl version.

---

## Summary

| Item | Value |
|------|-------|
| **Bug** | SIGILL crash when closing spawn channels |
| **Cause** | Event handlers disarmed after fd close |
| **Fix** | Reorder: disarm handlers BEFORE closing fd |
| **Patch** | `tcl9-close-order.patch` |
| **Status** | FIXED and verified |
