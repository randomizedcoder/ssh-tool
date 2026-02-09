# Design Document: Modular TCL/Expect SSH Automation Scripts

## Overview

A modular set of TCL/Expect scripts for SSH automation with per-component testing.
Supports Linux, FreeBSD, and Darwin (macOS) targets with robust prompt detection.

## Directory Structure

```
ssh-tool/
├── bin/
│   └── ssh-automation          # Primary executable script
├── lib/
│   ├── common/
│   │   ├── debug.tcl           # Debug/logging infrastructure
│   │   ├── prompt.tcl          # Robust prompt detection & management
│   │   └── utils.tcl           # Common utilities
│   ├── auth/
│   │   ├── password.tcl        # User password handling
│   │   └── sudo.tcl            # Root/sudo password handling
│   ├── connection/
│   │   └── ssh.tcl             # SSH connection management
│   └── commands/
│       ├── sudo_exec.tcl       # Sudo execution wrapper
│       ├── hostname.tcl        # Hostname retrieval
│       └── cat_file.tcl        # File content retrieval
├── tests/
│   ├── run_all_tests.sh        # Master test runner
│   ├── test_debug.sh           # Test debug module
│   ├── test_prompt.sh          # Test prompt module
│   ├── test_password.sh        # Test password module
│   ├── test_sudo.sh            # Test sudo password module
│   ├── test_ssh.sh             # Test SSH connection
│   ├── test_sudo_exec.sh       # Test sudo execution
│   ├── test_hostname.sh        # Test hostname command
│   ├── test_cat_file.sh        # Test file cat
│   └── helpers/
│       ├── test_utils.tcl      # Common test utilities
│       ├── mock_ssh.tcl        # Mock SSH session simulator
│       └── mock_terminal.tcl   # Mock terminal for password prompts
├── DESIGN.md
├── README.md
└── LICENSE
```

## Component Design

### 1. Debug Module (`lib/common/debug.tcl`)

```tcl
# Provides: debug
# Debug levels 0-7 (0=off, 7=maximum verbosity)
#
# Procedures:
#   debug::init {level}     - Initialize debug level
#   debug::log {level msg}  - Log message if level <= current level
#   debug::set_level {n}    - Change debug level at runtime
```

Debug levels:
- 0: Off (no debug output)
- 1: Errors only
- 2: Warnings
- 3: Info (connection events)
- 4: Verbose (command execution)
- 5: Debug (expect patterns)
- 6: Trace (all expect output)
- 7: Maximum (internal state)

### 2. Prompt Module (`lib/common/prompt.tcl`)

**This is the core module for reliable cross-platform prompt handling.**

```tcl
# Provides: prompt
#
# Procedures:
#   prompt::init {spawn_id {is_root 0}}  - Initialize unique prompt after connect
#   prompt::wait {spawn_id}              - Wait for prompt, return when ready
#   prompt::run {spawn_id cmd}           - Run command, return output reliably
#   prompt::marker {}                    - Get current prompt marker string
```

#### Design Rationale

Simple prompt matching (`*$ ` or `*# `) fails because:
- Custom PS1 prompts (colors, git status, paths)
- Command output containing `$` or `#` characters
- Different shells (bash, zsh, sh, csh, tcsh, fish)
- ANSI escape codes in prompts
- Varying prompt styles across Linux/FreeBSD/Darwin

#### Implementation Strategy

**Unique Prompt Injection** - After SSH connect, inject a unique, predictable prompt:

```tcl
namespace eval prompt {
    # Unique marker using PID to avoid collisions
    variable marker "XPCT[pid]>"
    variable root_marker "XPCT[pid]#"

    # Initialize prompt after SSH connection established
    # Sets TERM=dumb to disable colors, clears PROMPT_COMMAND
    proc init {spawn_id {is_root 0}} {
        variable marker
        variable root_marker

        set m [expr {$is_root ? $root_marker : $marker}]

        # Shell-agnostic prompt setting
        # Works on: bash, zsh, sh, dash, ksh (POSIX)
        # Fallback for: csh, tcsh
        send -i $spawn_id "export TERM=dumb PROMPT_COMMAND='' PS1='$m ' 2>/dev/null || set prompt='$m '\r"

        expect -i $spawn_id {
            -re "$m " {
                debug::log 5 "Prompt initialized: $m"
                return 1
            }
            timeout {
                debug::log 1 "Failed to set prompt"
                return 0
            }
        }
    }

    # Wait for prompt to appear
    proc wait {spawn_id} {
        variable marker
        variable root_marker

        expect -i $spawn_id {
            -re "($marker|$root_marker) " {
                return 1
            }
            timeout {
                debug::log 1 "Timeout waiting for prompt"
                return 0
            }
            eof {
                debug::log 1 "Connection closed"
                return 0
            }
        }
    }

    # Run command with bracketed output capture for reliability
    proc run {spawn_id cmd} {
        variable marker
        variable root_marker

        set start_mark "<<<CMD_START_[pid]>>>"
        set end_mark "<<<CMD_END_[pid]>>>"

        # Bracket command output with unique markers
        send -i $spawn_id "echo '$start_mark'; $cmd; __rc=\$?; echo '$end_mark'; echo \"__EXIT=\$__rc\"\r"

        expect -i $spawn_id -re "$start_mark\r\n(.*?)\r\n$end_mark\r\n__EXIT=(\[0-9]+)"

        set output $expect_out(1,string)
        set exit_code $expect_out(2,string)

        # Wait for prompt
        wait $spawn_id

        return [list $exit_code $output]
    }

    # Get marker for external use
    proc marker {{is_root 0}} {
        variable marker
        variable root_marker
        return [expr {$is_root ? $root_marker : $marker}]
    }
}
```

#### Cross-Platform Compatibility

| OS | Default Shell | Prompt Setting |
|----|---------------|----------------|
| Linux | bash/zsh | `PS1='...'` works |
| FreeBSD | sh/csh | `PS1` or `set prompt` |
| Darwin | zsh (10.15+) | `PS1='...'` works |
| Darwin | bash (<10.15) | `PS1='...'` works |

The dual command `export PS1='...' 2>/dev/null || set prompt='...'` handles both POSIX and csh-family shells.

### 3. Password Module (`lib/auth/password.tcl`)

```tcl
# Provides: auth::password
#
# Procedures:
#   auth::password::get {}   - Returns user password
#                              Reads PASSWORD env var or prompts user
#   auth::password::clear {} - Clears stored password from memory
```

- Checks `PASSWORD` environment variable first
- Falls back to secure terminal prompt (stty -echo)
- Stores in namespace variable (memory only)

### 4. Sudo Password Module (`lib/auth/sudo.tcl`)

```tcl
# Provides: auth::sudo
#
# Procedures:
#   auth::sudo::get {}      - Returns sudo/root password
#                             Reads SUDO env var or prompts user
#   auth::sudo::clear {}    - Clears stored password from memory
```

- Checks `SUDO` environment variable first
- Falls back to secure terminal prompt
- Stores in namespace variable (memory only)

### 5. SSH Connection Module (`lib/connection/ssh.tcl`)

```tcl
# Provides: connection::ssh
#
# Procedures:
#   connection::ssh::connect {host user password} - Establish SSH connection
#                                                   Returns spawn_id on success
#   connection::ssh::disconnect {spawn_id}        - Close SSH connection
#   connection::ssh::is_connected {spawn_id}      - Check connection status
```

Connection flow:
1. Spawn `ssh user@host`
2. Handle host key verification (auto-accept with warning at debug level 2)
3. Wait for password prompt, send password
4. Wait for initial shell prompt (any prompt pattern)
5. Call `prompt::init` to set unique prompt
6. Return spawn_id

Expect patterns to handle:
- Password prompt: `-re {[Pp]assword:\s*$}`
- Host key verification: `-re {(yes/no.*)\?}`
- Connection refused: `"Connection refused"`
- Timeout
- Permission denied: `"Permission denied"`

### 6. Sudo Execution Module (`lib/commands/sudo_exec.tcl`)

```tcl
# Provides: commands::sudo
#
# Procedures:
#   commands::sudo::exec {spawn_id password} - Execute sudo -i
#                                              Returns 1 on success, 0 on failure
```

Flow:
1. Send `sudo -i`
2. Wait for password prompt
3. Send password
4. Wait for root shell
5. Call `prompt::init $spawn_id 1` to set root prompt
6. Verify with `whoami` command

### 7. Hostname Module (`lib/commands/hostname.tcl`)

```tcl
# Provides: commands::hostname
#
# Procedures:
#   commands::hostname::get {spawn_id} - Run hostname, return result
```

Uses `prompt::run` for reliable output capture:
```tcl
proc get {spawn_id} {
    lassign [prompt::run $spawn_id "hostname"] rc output
    if {$rc != 0} {
        debug::log 1 "hostname command failed with exit code $rc"
        return ""
    }
    return [string trim $output]
}
```

### 8. Cat File Module (`lib/commands/cat_file.tcl`)

```tcl
# Provides: commands::cat_file
#
# Procedures:
#   commands::cat_file::read {spawn_id filename} - Cat file, return contents
```

Uses `prompt::run` for reliable output capture:
```tcl
proc read {spawn_id filename} {
    # Validate filename (basic security check)
    if {[regexp {[;&|`$]} $filename]} {
        error "Invalid characters in filename"
    }

    lassign [prompt::run $spawn_id "cat '$filename'"] rc output
    if {$rc != 0} {
        debug::log 1 "cat command failed with exit code $rc"
        return ""
    }
    return $output
}
```

## Primary Script (`bin/ssh-automation`)

```tcl
#!/usr/bin/env expect
#
# ssh-automation - SSH automation driver
#
# Usage: ssh-automation --host <hostname> --filename <file> [--user <username>] [--debug <0-7>]
#
# --user defaults to current $USER if not specified

# Parse arguments
# Load modules
# Execute workflow:
#   1. Get user password (from PASSWORD env or prompt)
#   2. Get sudo password (from SUDO env or prompt)
#   3. SSH connect to host
#   4. Initialize prompt
#   5. Sudo to root
#   6. Run hostname (store result)
#   7. Cat specified file (output result)
#   8. Disconnect
```

## Testing Strategy

### Individual Component Tests

Each test script will:
1. Source the component being tested
2. Set up test fixtures (mock environment)
3. Run component procedures
4. Verify expected behavior
5. Report PASS/FAIL

Example test structure:
```bash
#!/bin/bash
# test_password.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test 1: PASSWORD env var is used
export PASSWORD="testpass123"
result=$(expect -f "$PROJECT_ROOT/tests/helpers/test_password_env.tcl")
if [[ "$result" == "testpass123" ]]; then
    echo "PASS: PASSWORD env var read correctly"
else
    echo "FAIL: PASSWORD env var not read correctly"
    exit 1
fi

# Test 2: Prompt when no env var (would require mock)
unset PASSWORD
# ... additional tests
```

### Test Helpers

Tests use mock expect scripts that simulate SSH/sudo interactions without needing a real remote host.

```
tests/helpers/
├── test_utils.tcl      # Common test utilities (assertions, setup)
├── mock_ssh.tcl        # Mock SSH session simulator
└── mock_terminal.tcl   # Mock terminal for password prompt tests
```

Mock approach:
- `mock_ssh.tcl` - Spawns a shell script that echoes expected patterns
- `mock_terminal.tcl` - Tests password prompting without needing real tty
- Tests verify module procedures return expected values given mock inputs

### Mock SSH Design

```tcl
# mock_ssh.tcl - Simulates SSH session for testing
#
# Spawns a local script that:
# 1. Prints "password: "
# 2. Reads input (simulates password entry)
# 3. Prints a shell prompt
# 4. Responds to commands with canned output

proc mock_ssh::spawn {} {
    spawn ./tests/helpers/mock_ssh_server.sh
    return $spawn_id
}
```

```bash
#!/bin/bash
# mock_ssh_server.sh - Fake SSH server for testing

echo -n "password: "
read -s password
echo ""
echo "$ "  # Initial prompt

while read cmd; do
    case "$cmd" in
        "hostname")
            echo "mock-hostname"
            ;;
        "cat "*)
            echo "mock file contents"
            ;;
        "exit")
            exit 0
            ;;
    esac
    echo "$ "
done
```

### Master Test Runner (`tests/run_all_tests.sh`)

```bash
#!/bin/bash
# Runs all component tests in sequence

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TESTS=(
    "test_debug.sh"
    "test_prompt.sh"
    "test_password.sh"
    "test_sudo.sh"
    "test_ssh.sh"
    "test_sudo_exec.sh"
    "test_hostname.sh"
    "test_cat_file.sh"
)

PASS=0
FAIL=0

for test in "${TESTS[@]}"; do
    echo "========================================"
    echo "Running $test..."
    echo "========================================"
    if ./"$test"; then
        echo "PASSED: $test"
        ((PASS++))
    else
        echo "FAILED: $test"
        ((FAIL++))
    fi
    echo ""
done

echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
exit $FAIL
```

## Idiomatic TCL/Expect Patterns

### Namespace Usage
Each module uses its own namespace to avoid variable/procedure collisions:
```tcl
namespace eval auth::password {
    variable stored_password ""

    proc get {} {
        variable stored_password
        # ...
    }
}
```

### Module Loading
Using `source` with relative paths from a lib directory:
```tcl
# In main script
set script_dir [file dirname [info script]]
set lib_dir [file join $script_dir "../lib"]

source [file join $lib_dir "common/debug.tcl"]
source [file join $lib_dir "common/prompt.tcl"]
source [file join $lib_dir "auth/password.tcl"]
# ...
```

### Expect Best Practices

```tcl
# Use -re for regex patterns
# Use exp_continue to keep matching in same expect block
# Always handle timeout and eof

expect {
    -re {[Pp]assword:\s*$} {
        send "$password\r"
        exp_continue
    }
    -re {XPCT[0-9]+[>#] } {
        debug::log 3 "Prompt received"
    }
    timeout {
        debug::log 1 "Connection timeout"
        return 0
    }
    eof {
        debug::log 1 "Connection closed unexpectedly"
        return 0
    }
}
```

### Error Handling
```tcl
if {[catch {connection::ssh::connect $host $user $password} result]} {
    debug::log 1 "SSH connection failed: $result"
    exit 1
}
```

### Timeout Configuration
```tcl
# Set reasonable timeouts
set timeout 30

# Per-command timeout override
expect -timeout 60 {
    # ... long-running command patterns
}
```

## Files to Create

| File | Purpose |
|------|---------|
| `bin/ssh-automation` | Primary executable |
| `lib/common/debug.tcl` | Debug/logging |
| `lib/common/prompt.tcl` | Robust prompt detection |
| `lib/common/utils.tcl` | Common utilities |
| `lib/auth/password.tcl` | User password handling |
| `lib/auth/sudo.tcl` | Sudo password handling |
| `lib/connection/ssh.tcl` | SSH connection |
| `lib/commands/sudo_exec.tcl` | Sudo execution |
| `lib/commands/hostname.tcl` | Hostname command |
| `lib/commands/cat_file.tcl` | Cat file command |
| `tests/run_all_tests.sh` | Master test runner |
| `tests/test_debug.sh` | Debug module tests |
| `tests/test_prompt.sh` | Prompt module tests |
| `tests/test_password.sh` | Password module tests |
| `tests/test_sudo.sh` | Sudo module tests |
| `tests/test_ssh.sh` | SSH connection tests |
| `tests/test_sudo_exec.sh` | Sudo exec tests |
| `tests/test_hostname.sh` | Hostname tests |
| `tests/test_cat_file.sh` | Cat file tests |
| `tests/helpers/test_utils.tcl` | Test utilities |
| `tests/helpers/mock_ssh.tcl` | Mock SSH simulator |
| `tests/helpers/mock_ssh_server.sh` | Mock SSH server script |
| `tests/helpers/mock_terminal.tcl` | Mock terminal for prompts |

## CLI Arguments Summary

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--host` | Yes | - | Hostname or IP address |
| `--filename` | Yes | - | File to cat on remote host |
| `--user` | No | `$USER` | SSH username |
| `--debug` | No | 0 | Debug level 0-7 |

## Verification

After implementation:
1. Run `./tests/run_all_tests.sh` - all mock-based tests should pass
2. Manual test with real SSH target (optional):
   ```bash
   export PASSWORD="mypassword"
   export SUDO="rootpassword"
   ./bin/ssh-automation --host 192.168.122.208 --filename /etc/fedora-release --debug 4

   # Or with explicit user:
   ./bin/ssh-automation --host 192.168.122.208 --user das --filename /etc/fedora-release --debug 4
   ```
3. Verify:
   - Prompt is correctly set (visible at debug level 5+)
   - Hostname is captured and displayed
   - File contents are displayed
   - Clean disconnect

## Future Extensions

The modular design allows easy addition of:
- New command modules in `lib/commands/`
- Additional authentication methods in `lib/auth/`
- Alternative connection types in `lib/connection/` (e.g., telnet, serial)
- Each new module gets a corresponding test in `tests/`
