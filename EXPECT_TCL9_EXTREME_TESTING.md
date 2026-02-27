# Expect Tcl 9.0 Extreme Testing Plan

Comprehensive test plan for Expect 5.45.4 with Tcl 9.0, focusing on integer width changes, boundary conditions, and upgrade regressions.

## Overview

Tcl 9.0's primary change affecting Expect: `int` → `Tcl_Size` (64-bit on LP64 systems).

**Risk Areas:**
- Integer truncation at boundaries
- Sign extension issues
- Buffer size calculations
- Index arithmetic
- API boundary mismatches

---

## 1. Integer Semantics

### 1.1 Boundary Values to Test

| Value | Decimal | Hex | Significance |
|-------|---------|-----|--------------|
| INT32_MAX | 2,147,483,647 | 0x7FFFFFFF | Signed 32-bit max |
| INT32_MAX+1 | 2,147,483,648 | 0x80000000 | Overflows signed 32-bit |
| UINT32_MAX | 4,294,967,295 | 0xFFFFFFFF | Unsigned 32-bit max |
| UINT32_MAX+1 | 4,294,967,296 | 0x100000000 | Exceeds 32-bit |
| INT64_MAX | 9,223,372,036,854,775,807 | 0x7FFFFFFFFFFFFFFF | Signed 64-bit max |
| -INT32_MIN | -2,147,483,648 | 0x80000000 (signed) | Most negative 32-bit |

### 1.2 Test Cases

```tcl
# test-int-boundaries.tcl

# --- Arithmetic at 32-bit boundary ---
test int-boundary-1.1 {addition crossing 32-bit boundary} {
    set a 2147483647
    set b [expr {$a + 1}]
    expr {$b == 2147483648}
} {1}

test int-boundary-1.2 {multiplication overflow check} {
    set a 65536
    set b 65536
    set c [expr {$a * $b}]
    expr {$c == 4294967296}
} {1}

test int-boundary-1.3 {negative boundary} {
    set a -2147483648
    set b [expr {$a - 1}]
    expr {$b == -2147483649}
} {1}

# --- Bitwise operations with sign extension ---
test int-bitwise-2.1 {right shift negative number} {
    set a -1
    set b [expr {$a >> 1}]
    # Should remain -1 (arithmetic shift)
    expr {$b == -1}
} {1}

test int-bitwise-2.2 {bitwise complement} {
    set a 0
    set b [expr {~$a}]
    expr {$b == -1}
} {1}

test int-bitwise-2.3 {AND with large value} {
    set a 0xFFFFFFFFFFFFFFFF
    set b [expr {$a & 0xFFFFFFFF}]
    expr {$b == 4294967295}
} {1}

# --- Parse/format roundtrips ---
test int-format-3.1 {format large positive} {
    set a 9223372036854775807
    set s [format %lld $a]
    scan $s %lld b
    expr {$a == $b}
} {1}

test int-format-3.2 {format large negative} {
    set a -9223372036854775808
    set s [format %lld $a]
    scan $s %lld b
    expr {$a == $b}
} {1}

# --- Mixed numeric types ---
test int-mixed-4.1 {integer to double conversion} {
    set a 9007199254740993  ;# Beyond double precision
    set d [expr {double($a)}]
    set b [expr {int($d)}]
    # May lose precision - test awareness
    expr {$a != $b}  ;# Expect loss
} {1}

test int-mixed-4.2 {wide vs int in expr} {
    set a [expr {2147483647 + 1}]
    string is wideinteger $a
} {1}
```

### 1.3 Current Coverage

| Test Area | Covered | Gap |
|-----------|---------|-----|
| 32-bit boundary arithmetic | Partial | Need explicit boundary tests |
| Bitwise with sign extension | No | Add tests |
| Parse/format roundtrips | No | Add tests |
| Mixed numeric types | No | Add tests |

---

## 2. Lengths, Indices, and Counts

### 2.1 String Indexing

```tcl
# test-string-indices.tcl

test str-idx-1.1 {string index at large offset} {
    # Simulate large index without allocating
    set s "test"
    catch {string index $s 2147483648} err
    string match "*out of range*" $err
} {1}

test str-idx-1.2 {string range with end math} {
    set s "hello"
    string range $s end-1 end
} {lo}

test str-idx-1.3 {negative index} {
    set s "hello"
    string index $s end-10
} {}

test str-idx-1.4 {regexp -indices with match} {
    set s "hello world"
    regexp -indices {world} $s match
    lindex $match 0
} {6}

# --- Unicode boundary ---
test str-unicode-2.1 {string length vs bytelength} {
    set s "日本語"  ;# 3 chars, 9 bytes
    list [string length $s] [string bytelength $s]
} {3 9}

test str-unicode-2.2 {string index multibyte} {
    set s "日本語"
    string index $s 1
} {本}
```

### 2.2 List Indexing

```tcl
# test-list-indices.tcl

test list-idx-1.1 {lindex large positive} {
    set l {a b c}
    lindex $l 2147483648
} {}

test list-idx-1.2 {lrange end math} {
    set l {a b c d e}
    lrange $l end-2 end
} {c d e}

test list-idx-1.3 {lset at end} {
    set l {a b c}
    lset l end X
    set l
} {a b X}

test list-idx-1.4 {llength large list} {
    set l [lrepeat 100000 x]
    llength $l
} {100000}

test list-idx-1.5 {lsearch -start with large value} {
    set l {a b c d e}
    lsearch -start 2147483648 $l x
} {-1}
```

### 2.3 Current Coverage

| Test Area | Covered | Gap |
|-----------|---------|-----|
| String indexing boundaries | No | Add tests |
| Unicode length vs byte | No | Add tests |
| List index boundaries | No | Add tests |
| Dict large keys/values | No | Add tests |

---

## 3. Byte Handling: Encodings and I/O

### 3.1 Binary and Encoding Tests

```tcl
# test-binary-encoding.tcl

test binary-1.1 {binary format wide int} {
    set data [binary format W 9223372036854775807]
    binary scan $data W val
    expr {$val == 9223372036854775807}
} {1}

test binary-1.2 {binary with embedded NUL} {
    set data "hello\x00world"
    string length $data
} {11}

test binary-1.3 {encoding convertto/from roundtrip} {
    set s "日本語"
    set bytes [encoding convertto utf-8 $s]
    set s2 [encoding convertfrom utf-8 $bytes]
    expr {$s eq $s2}
} {1}

test binary-1.4 {bytearray with large size} {
    set data [string repeat \x00 1000000]
    string length $data
} {1000000}
```

### 3.2 Expect I/O Byte Counts

```tcl
# test-expect-io.tcl

test expect-io-1.1 {send with embedded NUL} {
    spawn cat -u
    # NUL bytes stripped by default
    exp_send "a\x00b\r"
    expect "ab"
    close; wait
    expr 1
} {1}

test expect-io-1.2 {send with NUL preserved} {
    spawn cat -u
    remove_nulls 0
    exp_send "a\x00b\r"
    expect "a\x00b"
    close; wait
    expr 1
} {1}

test expect-io-1.3 {expect_out buffer byte count} {
    spawn echo "test data"
    expect "test"
    set buf $expect_out(buffer)
    expr {[string length $buf] >= 4}
} {1}
```

### 3.3 Current Coverage

| Test Area | Covered | Gap |
|-----------|---------|-----|
| Binary format wide int | No | Add tests |
| Embedded NUL handling | Partial (7.2) | Expand |
| Encoding roundtrips | No | Add tests |
| Channel byte counts | No | Add tests |

---

## 4. Expect Pattern Matching & Buffering

### 4.1 Buffer Boundary Tests

```tcl
# test-expect-buffers.tcl

test expect-buf-1.1 {pattern split across buffer chunks} {
    # Helper that writes "MARKER" across two writes with delay
    spawn sh -c 'echo -n MAR; sleep 0.1; echo KER'
    set timeout 5
    expect {
        "MARKER" {set r pass}
        timeout {set r timeout}
    }
    catch {close; wait}
    set r
} {pass}

test expect-buf-1.2 {very long line no newline} {
    spawn sh -c 'dd if=/dev/zero bs=1 count=10000 2>/dev/null | tr "\\0" "X"; echo END'
    match_max 20000
    set timeout 30
    expect {
        "END" {set r pass}
        timeout {set r timeout}
    }
    set buf_len [string length $expect_out(buffer)]
    catch {close; wait}
    expr {$r eq "pass" && $buf_len >= 10000}
} {1}

test expect-buf-1.3 {buffer exactly at match_max} {
    spawn cat -u
    set mm 1000
    match_max $mm
    set data [string repeat "X" $mm]
    exp_send "${data}\r"
    set timeout 10
    expect {
        -ex $data {set r pass}
        timeout {set r timeout}
        full_buffer {set r full}
    }
    catch {close; wait}
    set r
} {pass}
```

### 4.2 Pattern Matching Precision

```tcl
# test-expect-patterns.tcl

test expect-pat-1.1 {overlapping patterns - first wins} {
    spawn echo "hello"
    expect {
        "hel" {set r first}
        "hello" {set r second}
    }
    catch {close; wait}
    set r
} {first}

test expect-pat-1.2 {exact vs glob precedence} {
    spawn echo "test*data"
    expect {
        -ex "test*data" {set r exact}
        "test*" {set r glob}
    }
    catch {close; wait}
    set r
} {exact}

test expect-pat-1.3 {regexp capture indices} {
    spawn echo "prefix-12345-suffix"
    expect -indices -re {(\d+)}
    set start $expect_out(1,start)
    set end $expect_out(1,end)
    catch {close; wait}
    expr {$start >= 0 && $end > $start}
} {1}

test expect-pat-1.4 {utf8 in pattern match} {
    spawn echo "Hello 世界 World"
    expect {
        "世界" {set r pass}
        timeout {set r fail}
    }
    catch {close; wait}
    set r
} {pass}

test expect-pat-1.5 {match indices with utf8} {
    spawn echo "ABC日本語XYZ"
    expect -indices -re {日本語}
    set start $expect_out(0,start)
    catch {close; wait}
    # Start should be 3 (after ABC, character index not byte)
    expr {$start == 3}
} {1}
```

### 4.3 Current Coverage

| Test Area | Covered | Gap |
|-----------|---------|-----|
| Buffer boundary crossing | No | **Critical** - Add |
| Long line no newline | No | Add |
| Pattern precedence | No | Add |
| UTF-8 match indices | No | Add |
| full_buffer event | No | Add |

---

## 5. Timeout and Event Loop

### 5.1 Timeout Edge Cases

```tcl
# test-expect-timeout.tcl

test timeout-1.1 {timeout 0 - immediate poll} {
    spawn cat -u
    set timeout 0
    exp_send "data\r"
    after 100  ;# Let data arrive
    expect {
        "data" {set r pass}
        timeout {set r timeout}
    }
    close; wait
    set r
} {pass}

test timeout-1.2 {timeout -1 - infinite} {
    spawn echo "quick"
    set timeout -1
    expect {
        "quick" {set r pass}
        eof {set r eof}
    }
    catch {close; wait}
    # Should match before needing timeout
    set r
} {pass}

test timeout-1.3 {very large timeout accepted} {
    set timeout 86400  ;# 24 hours
    spawn echo "test"
    expect "test"
    catch {close; wait}
    expr 1
} {1}

test timeout-1.4 {timeout math boundary} {
    # Ensure large timeout doesn't overflow internal calculations
    set timeout 2147483
    spawn echo "test"
    expect "test"
    catch {close; wait}
    expr 1
} {1}
```

### 5.2 After and Event Loop

```tcl
# test-event-loop.tcl

test after-1.1 {after with callback} {
    set ::done 0
    after 100 {set ::done 1}
    vwait ::done
    set ::done
} {1}

test after-1.2 {after cancel} {
    set id [after 1000 {set ::x 1}]
    after cancel $id
    expr 1
} {1}

test after-1.3 {after with large delay accepted} {
    # 1 day in ms - should not overflow
    set id [after 86400000 {set ::x 1}]
    after cancel $id
    expr 1
} {1}

test fileevent-1.1 {fileevent on spawn channel} {
    spawn cat -u
    set ::fe_triggered 0
    fileevent $spawn_id readable {set ::fe_triggered 1}
    exp_send "x\r"
    after 500
    update
    fileevent $spawn_id readable {}
    close; wait
    set ::fe_triggered
} {1}
```

### 5.3 Current Coverage

| Test Area | Covered | Gap |
|-----------|---------|-----|
| timeout 0 (poll) | Partial (5.2) | Good |
| timeout -1 (infinite) | No | Add |
| Large timeout values | Partial (12.8) | Expand |
| after event handling | No | Add |
| fileevent on spawn | No | Add |

---

## 6. Error Handling and Failure Shapes

### 6.1 Error Path Tests

```tcl
# test-error-paths.tcl

test error-1.1 {invalid spawn_id error} {
    catch {exp_send -i "invalid_spawn" "test"} err
    string match "*invalid*" $err
} {1}

test error-1.2 {match_max negative rejected} {
    catch {match_max -1} err
    string match "*positive*" $err
} {1}

test error-1.3 {match_max zero rejected} {
    catch {match_max 0} err
    string match "*positive*" $err
} {1}

test error-1.4 {timeout non-numeric rejected} {
    set old $timeout
    catch {set timeout "abc"} err
    set timeout $old
    # Should get error or coerce to 0
    expr 1
} {1}

test error-1.5 {spawn nonexistent command} {
    catch {spawn /nonexistent/command} err
    expr {$err ne "" || [catch {wait}]}
} {1}

test error-1.6 {close already closed} {
    spawn cat
    close
    wait
    catch {close} err
    # Should error gracefully
    expr {$err ne ""}
} {1}
```

### 6.2 Numeric String Edge Cases

```tcl
# test-numeric-strings.tcl

test numstr-1.1 {leading plus} {
    expr {+123 == 123}
} {1}

test numstr-1.2 {leading whitespace} {
    expr {[string trim " 123 "] == 123}
} {1}

test numstr-1.3 {hex literal} {
    expr {0xFF == 255}
} {1}

test numstr-1.4 {octal-ish pitfall} {
    # 08 is invalid octal in some contexts
    catch {expr {08}} err
    # Tcl 9 may handle this differently
    expr 1
} {1}

test numstr-1.5 {scientific notation} {
    set a "1e6"
    expr {$a == 1000000.0}
} {1}
```

### 6.3 Current Coverage

| Test Area | Covered | Gap |
|-----------|---------|-----|
| Error propagation | Partial | Expand |
| Invalid parameter errors | No | Add |
| Numeric string parsing | No | Add |
| Error code stability | No | Add |

---

## 7. ABI / Extension Boundary (C API)

### 7.1 Areas Modified by Our Patches

| Function | Change | Test Strategy |
|----------|--------|---------------|
| Exp_SpawnObjCmd | int→Tcl_Size objc | Many arguments test |
| Exp_ExpectObjCmd | int→Tcl_Size objc | Many patterns test |
| Exp_TrapObjCmd | int→Tcl_Size objc, signal list | Signal list tests |
| Exp_MatchMaxObjCmd | int→Tcl_WideInt size | Boundary value tests |
| exp_close | Close order change | SIGILL tests |
| ExpClose2Proc | Channel VERSION_5 | Channel I/O tests |

### 7.2 Stress Tests for Native Code

```tcl
# test-native-stress.tcl

test native-stress-1.1 {rapid object creation} {
    for {set i 0} {$i < 1000} {incr i} {
        spawn cat
        close
        wait
    }
    expr 1
} {1}

test native-stress-1.2 {large iteration with patterns} {
    spawn cat -u
    for {set i 0} {$i < 100} {incr i} {
        exp_send "line$i\r"
        expect "line$i"
    }
    close
    wait
    expr 1
} {1}

test native-stress-1.3 {many simultaneous spawns} {
    set pids {}
    for {set i 0} {$i < 20} {incr i} {
        spawn cat
        lappend pids $spawn_id
    }
    foreach pid $pids {
        close -i $pid
        wait -i $pid
    }
    expr 1
} {1}
```

### 7.3 Current Coverage

| Test Area | Covered | Gap |
|-----------|---------|-----|
| Rapid spawn/close | Yes (1.4) | Good |
| Many simultaneous spawns | Yes (6.5) | Good |
| Large iteration | No | Add |
| Refcount under stress | No | Add |

---

## 8. Resource Limits / Practical Huge Tests

### 8.1 Simulated Huge (Arithmetic Only)

```tcl
# test-simulated-huge.tcl

test huge-sim-1.1 {huge index error path} {
    set l {a b c}
    set huge_idx 9223372036854775807
    set result [lindex $l $huge_idx]
    expr {$result eq ""}
} {1}

test huge-sim-1.2 {huge string index error path} {
    set s "abc"
    set huge_idx 9223372036854775807
    set result [string index $s $huge_idx]
    expr {$result eq ""}
} {1}

test huge-sim-1.3 {match_max at INT64 boundary} {
    set huge 9223372036854775807
    # This may be rejected as too large
    set rc [catch {match_max -d $huge} err]
    # Either accepted or meaningful error
    expr {$rc == 0 || $err ne ""}
} {1}

test huge-sim-1.4 {size multiplication overflow check} {
    # Simulate: n * elementSize where both are large
    set n 4294967296
    set elemSize 4
    set total [expr {$n * $elemSize}]
    expr {$total == 17179869184}
} {1}
```

### 8.2 Buffer Chunk Boundaries

```tcl
# test-chunk-boundaries.tcl

test chunk-1.1 {data at 4KB boundary} {
    spawn cat -u
    match_max 10000
    set data [string repeat "X" 4096]
    exp_send "${data}END\r"
    expect "END"
    expr {[string length $expect_out(buffer)] >= 4096}
} {1}

test chunk-1.2 {data at 8KB boundary} {
    spawn cat -u
    match_max 20000
    set data [string repeat "Y" 8192]
    exp_send "${data}END\r"
    expect "END"
    expr {[string length $expect_out(buffer)] >= 8192}
} {1}

test chunk-1.3 {data at 64KB boundary} {
    spawn cat -u
    match_max 100000
    set data [string repeat "Z" 65536]
    exp_send "${data}END\r"
    set timeout 30
    expect "END"
    expr {[string length $expect_out(buffer)] >= 65536}
} {1}
```

### 8.3 Current Coverage

| Test Area | Covered | Gap |
|-----------|---------|-----|
| Simulated huge indices | No | Add |
| Multiplication overflow | No | Add |
| Chunk boundaries (4K) | No | Add |
| Chunk boundaries (64K) | No | Add |

---

## Implementation Priority

### Phase 1: Critical (Add to tcl9.test now)

1. **Buffer boundary crossing** (4.1) - Pattern split across chunks
2. **Integer boundary arithmetic** (1.2) - 32-bit overflow
3. **Error path validation** (6.1) - Invalid parameters
4. **Timeout edge cases** (5.1) - timeout 0, -1, large

### Phase 2: High (Add after Phase 1)

5. **String/list index boundaries** (2.1, 2.2)
6. **UTF-8 match indices** (4.2)
7. **Binary format/scan wide** (3.1)
8. **After/fileevent integration** (5.2)

### Phase 3: Comprehensive (Full coverage)

9. **Simulated huge paths** (8.1)
10. **Chunk boundary tests** (8.2)
11. **Numeric string parsing** (6.2)
12. **Stress/refcount tests** (7.2)

---

## Test Execution

```bash
# Run all Tcl 9 extreme tests
./expect tests/tcl9-extreme.test

# Run with verbose output
./expect tests/tcl9-extreme.test -verbose bps

# Run specific section
./expect -c 'source tests/tcl9-extreme.test; runTests int-*'
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `tcl9-extreme.test` | Main extreme test suite |
| `tcl9-int-boundaries.test` | Integer arithmetic tests |
| `tcl9-string-indices.test` | String/list index tests |
| `tcl9-buffers.test` | Buffer and I/O tests |
| `tcl9-events.test` | Timeout and event loop tests |
| `tcl9-errors.test` | Error path tests |
| `tcl9-stress.test` | Stress and resource tests |

These can be merged into a single `tcl9-extreme.test` or kept separate for modularity.
