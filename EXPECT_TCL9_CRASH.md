# DEFECT: expect-tcl9 Crashes with SIGILL During exp_close

**Severity**: CRITICAL
**Status**: OPEN
**Created**: 2026-02-17
**Component**: nix/expect-tcl9/

## Summary

The expect-tcl9 package (Expect compiled against Tcl 9.0) crashes with SIGILL (illegal instruction) when closing SSH connections via `exp_close`. This completely blocks all MCP SSH operations in the NixOS integration tests.

## Reproduction

1. Run the NixOS integration test:
   ```bash
   nix build .#checks.x86_64-linux.integration --print-build-logs
   ```

2. The MCP server starts successfully and handles HTTP requests, but crashes when closing an SSH spawn:
   ```
   spawn ssh -p 22 testuser@target
   ...
   fstat: Bad file descriptor
   traps: .expect-wrapped[811] trap invalid opcode ip:7f187c2c2911 sp:7ffe10277bd0 error:0 in libtcl9.0.so
   ```

## Error Details

### Kernel Trap
```
traps: .expect-wrapped[811] trap invalid opcode ip:7f187c2c2911 sp:7ffe10277bd0 error:0 in libtcl9.0.so[14b911,7f187c1a5000+198000]
```

### Coredump Stack Trace
```
Process 811 (.expect-wrapped) of user 0 dumped core.
Module /dlx00bhv3ghv1r3gcphbbc5ydwgd2mn4-expect-tcl9/bin/.expect-wrapped without build-id.
Module libexpect5.45.4.so without build-id.
#3  0x00007f187c3c2fa1 exp_event_disarm_fg (libexpect5.45.4.so + 0x26fa1)
#4  0x00007f187c3a87a1 exp_close (libexpect5.45.4.so + 0xc7a1)
```

### Preceding Error
```
fstat: Bad file descriptor
```

## Analysis

The crash occurs in `exp_close` → `exp_event_disarm_fg` in libexpect. The SIGILL (illegal instruction) suggests:

1. **Miscompiled code**: The expect library may have been compiled with CPU instructions not available on the target
2. **ABI mismatch**: Incompatibility between Expect 5.45.4 and Tcl 9.0 internal structures
3. **Corrupted state**: The "Bad file descriptor" before the crash suggests the spawn's file descriptor was already invalid when exp_close tried to clean up

## Current expect-tcl9 Build

Location: `nix/expect-tcl9/default.nix`

The build applies two patches:
- `tcl9-channel.patch` - Channel handling for Tcl 9
- `tcl9-size.patch` - Size type changes for Tcl 9

## Potential Causes

1. **Incomplete Tcl 9 porting**: Expect 5.45.4 was written for Tcl 8.x. The patches may be incomplete.

2. **Event loop changes**: Tcl 9 has significant changes to the event loop. `exp_event_disarm_fg` may be using deprecated or changed APIs.

3. **File descriptor handling**: Tcl 9 changed internal channel/fd handling. The "fstat: Bad file descriptor" suggests Expect is trying to access an fd that Tcl 9 already closed.

4. **Thread safety changes**: Tcl 9 has stricter threading. Expect may be violating assumptions.

## Source Code

**Expect 5.45.4 Source Location:**
```
/home/das/Downloads/expect9/expect5.45.4
```

Downloaded from (same as nixpkgs):
```
https://downloads.sourceforge.net/project/expect/Expect/5.45.4/expect5.45.4.tar.gz
```

## Files to Investigate

**Local Build Files:**
1. `nix/expect-tcl9/default.nix` - Build configuration
2. `nix/expect-tcl9/tcl9-channel.patch` - Channel API changes (ExpClose2Proc)
3. `nix/expect-tcl9/tcl9-size.patch` - Size type changes (int -> Tcl_Size)

**Expect Source Files (need patching):**
1. `exp_event.c` - Contains `exp_event_disarm_fg` (crash site)
2. `exp_command.c` - Contains `exp_close` which calls event disarm
3. `exp_chan.c` - Channel handling (already patched)

## Regression Test

```bash
# Run the crash reproduction test
expect nix/expect-tcl9/tests/exp_close_crash.tcl
```

Test file: `nix/expect-tcl9/tests/exp_close_crash.tcl`

## Workarounds Attempted

None successful. The crash happens deep in the Expect library.

## Root Cause Analysis

**Location:** `exp_command.c:exp_close()` (lines 322-398)

**Problem:** Event handlers are disarmed AFTER the raw file descriptor is closed:

```c
// Line 346 - FD closed here
close(esPtr->fdin);
...
// Line 385 - But event disarm happens here, after FD is closed!
exp_state_prep_for_invalidation(interp,esPtr);
  → exp_event_disarm_fg(esPtr)
    → Tcl_DeleteChannelHandler(esPtr->channel, ...)  // Channel's FD is already closed!
```

In Tcl 9, `Tcl_DeleteChannelHandler` accesses the underlying fd, causing:
1. "fstat: Bad file descriptor" error
2. Corrupted internal state
3. SIGILL crash

**Fix:** Move `exp_state_prep_for_invalidation()` BEFORE `close(esPtr->fdin)`.

## Proposed Patch

```c
// In exp_close(), move line 385 to before line 346:

    Tcl_Flush(esPtr->channel);

+   /* Disarm event handlers BEFORE closing file descriptors */
+   exp_state_prep_for_invalidation(interp,esPtr);

    close(esPtr->fdin);
    if (esPtr->fd_slave != EXP_NOFD) close(esPtr->fd_slave);
    if (esPtr->fdin != esPtr->fdout) close(esPtr->fdout);

    ... // rest of cleanup

-   exp_state_prep_for_invalidation(interp,esPtr);
```

## Verification Steps

1. Create patch file: `nix/expect-tcl9/tcl9-close-order.patch`
2. Add to `default.nix` patches list
3. Run test: `expect nix/expect-tcl9/tests/exp_close_crash.tcl`
4. Run full integration test: `nix build .#checks.x86_64-linux.integration`

## Test Case

Minimal reproduction in the VM:
```tcl
package require Expect
spawn ssh -p 2222 testuser@target
# Enter password...
close $spawn_id  ;# CRASH HERE
```

## Impact

- **Integration tests**: Cannot complete - MCP server crashes
- **MCP server**: Cannot reliably establish/close SSH connections
- **All SSH tools**: Blocked (ssh_connect, ssh_run_command, etc.)

## References

- Tcl 9.0 Release Notes: https://www.tcl.tk/software/tcltk/9.0.html
- Expect Source: https://core.tcl-lang.org/expect/
- nixpkgs PR #490930: expect with Tcl 9 support (pending)
- Related file: `EXPECT_TCL9_PROGRESS.md` (porting progress)

## Action Items

- [ ] Add debug symbols to expect-tcl9 build
- [ ] Get full stack trace with line numbers
- [ ] Review Tcl 9 channel API changes
- [ ] Review Tcl 9 event loop changes
- [ ] Check if `exp_event_disarm_fg` uses deprecated Tcl APIs
- [ ] Test with official Tcl 8.6 to confirm regression
- [ ] Contact Expect maintainers about Tcl 9 support
