# Expect Tcl 9.0 Port Progress Summary

## Objective
Build Expect (version 5.45.4) with Tcl 9.0 support for use in the ssh-tool project's integration tests.

## Current Status: **FULLY WORKING - All Tests Pass**

## Location
```
~/Downloads/expect9/nixpkgs/pkgs/development/tcl-modules/by-name/ex/expect9/
```

## Files

| File | Purpose |
|------|---------|
| `package.nix` | Main Nix build definition |
| `tcl9-channel.patch` | Updates channel driver to TCL_CHANNEL_VERSION_5 |
| `tcl9-size.patch` | Fixes `int objc` → `Tcl_Size objc` in function signatures |

## Build & Test

```bash
# Build
cd ~/Downloads/expect9/nixpkgs
nix-build -E 'with import ./. {}; callPackage ./pkgs/development/tcl-modules/by-name/ex/expect9/package.nix {}'

# Test (use the path from build output)
export TCLLIBPATH="/nix/store/...-expect-5.45.4/lib"
cd /tmp && curl -LO https://downloads.sourceforge.net/expect/expect5.45.4.tar.gz
tar xzf expect5.45.4.tar.gz
cd expect5.45.4/tests
tclsh9.0 all.tcl
# Expected: Total 29 Passed 29 Skipped 0 Failed 0
```

## Tcl 9 Compatibility Approach

### 1. Compatibility Header (`tcl9_compat.h`)
Created via `postPatch` and prepended to all source files. Restores removed macros:
- `_ANSI_ARGS_(x)` → `x`
- `CONST`, `CONST84`, `CONST86` → `const`
- `TCL_VARARGS*` macros for variadic functions
- `Tcl_UniCharNcmp` → `Tcl_UtfNcmp`
- `Tcl_EvalTokens` → wrapper using `Tcl_EvalTokensStandard`

**Key insight**: The `Tcl_EvalTokens` wrapper MUST be outside the include guard (`#endif /* TCL9_COMPAT_H */`) with a `#if defined(_TCL)` check, so it compiles only after `tcl.h` is included.

### 2. Channel Driver Patch (`tcl9-channel.patch`)
Tcl 9 requires `TCL_CHANNEL_VERSION_5` with a `close2Proc` callback:
- Changed `expChannelType` structure layout
- Added `ExpClose2Proc` with signature `(ClientData, Tcl_Interp*, int flags)`
- Handles half-close flags appropriately

### 3. Tcl_Size Migration (`tcl9-size.patch`)
Function signatures changed from `int objc` to `Tcl_Size objc` for Tcl command callbacks.
This is done via patch file because it's selective (only callback functions, not all uses).

### 4. Critical sed Fixes (in `postPatch`)
These fix stack buffer overflow ("stack smashing") bugs:

```bash
# Tcl_GetUnicodeFromObj writes Tcl_Size (8 bytes) to length pointer
# Using int* (4 bytes) causes buffer overflow!
sed -i 's/int strlen;$/Tcl_Size strlen;/' expect.c
sed -i 's/int plen;$/Tcl_Size plen;/' expect.c

# Tcl_RegExpInfo uses Tcl_Size for match indices
sed -i 's/int start, end;/Tcl_Size start, end;/g' expect.c
```

## Key Learnings

### Tcl 9 API Changes
1. **Tcl_Size** - 64-bit type replaces `int` for sizes (enables >2GB data)
2. **Channel API** - Must use `TCL_CHANNEL_VERSION_5` with new structure layout
3. **Removed macros** - `_ANSI_ARGS_`, `CONST*`, `TCL_VARARGS*` all removed
4. **Removed functions** - `Tcl_EvalTokens` → `Tcl_EvalTokensStandard`
5. **Renamed functions** - `Tcl_UniCharNcmp` → `Tcl_UtfNcmp`

### Stack Smashing Bug
The most subtle bug was in `Tcl_GetUnicodeFromObj(&len)` calls:
- Tcl 9 writes `Tcl_Size` (8 bytes) to the length pointer
- Original code passed `int*` (4 bytes)
- This overwrites adjacent stack memory → "stack smashing detected"
- Fixed by changing `int strlen;` to `Tcl_Size strlen;`

### Include Guard Trick
For the `Tcl_EvalTokens` wrapper function:
- It uses Tcl types (`Tcl_Obj*`, `Tcl_Interp*`, etc.)
- These aren't defined until `tcl.h` is included
- Solution: Place wrapper OUTSIDE `#endif /* TCL9_COMPAT_H */` with `#if defined(_TCL)` guard
- This way it's compiled only after `tcl.h` is included

## Patch vs sed Strategy

| Approach | Use Case |
|----------|----------|
| **Patch file** | Structural changes (channel driver), selective changes (specific function signatures) |
| **sed** | Simple global replacements, variable type fixes |

The hybrid approach is more maintainable:
- Patches for complex/selective changes that need precise context
- sed for simple patterns that can be reliably matched globally

## Critical Bug Found: 64-bit Buffer Truncation

### The Problem

While the initial patches allowed `match_max` to accept values >2GB, the actual buffer
allocation would silently truncate to 32-bit. The value chain was:

```
match_max 4000000000     [Tcl_WideInt - 64-bit] ✓ patched
       ↓
exp_default_match_max    [Tcl_WideInt - 64-bit] ✓ patched
       ↓
esPtr->umsize            [Tcl_WideInt - 64-bit] ✓ patched
       ↓
new_msize = umsize*3+1   [int - 32-bit] ✗ TRUNCATED!
       ↓
esPtr->input.max         [int - 32-bit] ✗ TRUNCATED!
       ↓
esPtr->input.use         [int - 32-bit] ✗ TRUNCATED!
```

Tests like "match_max accepts 4GB" passed because they only verified the command
returned the correct value—they didn't verify the buffer was actually allocated
at that size.

### The Fix

Added patches in `default.nix` to fix the ExpUniBuf struct and related variables:

```bash
# Fix ExpUniBuf struct in exp_command.h
sed -i 's/int          max;.../Tcl_Size     max;.../' exp_command.h
sed -i 's/int          use;.../Tcl_Size     use;.../' exp_command.h

# Fix new_msize computation in expect.c
sed -i 's/int new_msize, excess;/Tcl_Size new_msize, excess;/' expect.c

# Fix numchars variables
sed -i 's/int numchars,.../Tcl_Size numchars,.../' expect.c
```

### Tests Added

New tests in `tcl9-extreme.test` that catch truncation:

- `extreme-huge-7.6`: Verifies 4GB match_max survives spawn/close cycle
- `extreme-huge-7.7`: Tests exactly at INT32_MAX+1 boundary (2,147,483,648)
- `extreme-huge-7.8`: Tests exactly at UINT32_MAX+1 boundary (4,294,967,296)

### Lesson Learned

The compiler warnings `-Wno-incompatible-pointer-types -Wno-int-conversion` were
hiding the truncation bugs. The tests only verified API acceptance, not actual
behavior with large values.

## References

- [Tcl 9.0 Porting Guide](https://wiki.tcl-lang.org/page/Porting+extensions+to+Tcl+9)
- [Tcl_CreateChannel Manual](https://www.tcl-lang.org/man/tcl8.5/TclLib/CrtChannel.html)
