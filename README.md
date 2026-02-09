# SSH Automation Tool

A modular TCL/Expect framework for SSH automation with robust prompt detection. Designed for automating tasks on remote Linux, FreeBSD, and Darwin (macOS) systems.

## Overview

This tool provides a reliable way to:
- Connect to remote hosts via SSH
- Authenticate with password
- Elevate to root via sudo
- Execute commands and capture output
- Read files from remote systems

The key innovation is **unique prompt injection** - after connecting, the tool sets a predictable prompt (`XPCT<pid>>`) that can be reliably detected regardless of the remote system's shell configuration, custom PS1 prompts, or ANSI escape codes.

## Requirements

- **expect** - TCL/Expect interpreter
- **bash** - For test scripts
- **shellcheck** - For shell script linting (optional, for development)

Install on Fedora:
```bash
sudo dnf install expect shellcheck
```

Install on Debian/Ubuntu:
```bash
sudo apt install expect shellcheck
```

## Quick Start

```bash
# Set passwords via environment variables
export PASSWORD="your-ssh-password"
export SUDO="your-sudo-password"

# Run the tool
./bin/ssh-automation --host 192.168.1.100 --filename /etc/os-release

# With explicit user
./bin/ssh-automation --host 192.168.1.100 --user admin --filename /etc/os-release

# With debug output
./bin/ssh-automation --host 192.168.1.100 --filename /etc/os-release --debug 4

# For ephemeral VMs (skip host key verification)
./bin/ssh-automation --host 192.168.1.100 --filename /etc/os-release --insecure
```

## CLI Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--host` | Yes | - | Hostname or IP address |
| `--filename` | Yes | - | File to cat on remote host |
| `--user` | No | `$USER` | SSH username |
| `--debug` | No | 0 | Debug level 0-7 |
| `--insecure` | No | off | Skip host key verification |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PASSWORD` | SSH password (prompts interactively if not set) |
| `SUDO` | Sudo password (prompts interactively if not set) |
| `INSECURE` | Set to `1` to skip host key verification |

## Debug Levels

| Level | Name | Description |
|-------|------|-------------|
| 0 | Off | No debug output |
| 1 | Error | Errors only |
| 2 | Warn | Warnings (includes insecure mode warning) |
| 3 | Info | Connection events |
| 4 | Verbose | Command execution |
| 5 | Debug | Expect patterns |
| 6 | Trace | Line-by-line output capture |
| 7 | Max | Internal state |

## Insecure Mode

For ephemeral VMs, containers, or NixOS microvms that get recreated frequently, use insecure mode to skip host key verification:

```bash
# Via command line
./bin/ssh-automation --host 192.168.1.100 --filename /etc/os-release --insecure

# Via environment variable
export INSECURE=1
./bin/ssh-automation --host 192.168.1.100 --filename /etc/os-release
```

This uses:
- `-o StrictHostKeyChecking=no` - Don't verify host key
- `-o UserKnownHostsFile=/dev/null` - Don't save to known_hosts
- `-o LogLevel=ERROR` - Suppress warning messages

## Project Structure

```
ssh-tool/
├── bin/
│   └── ssh-automation          # Primary executable
├── lib/
│   ├── common/
│   │   ├── debug.tcl           # Debug/logging (levels 0-7)
│   │   ├── prompt.tcl          # Robust prompt detection
│   │   └── utils.tcl           # Utilities (filename validation, escaping)
│   ├── auth/
│   │   ├── password.tcl        # SSH password handling
│   │   └── sudo.tcl            # Sudo password handling
│   ├── connection/
│   │   └── ssh.tcl             # SSH connection management
│   └── commands/
│       ├── sudo_exec.tcl       # Sudo elevation
│       ├── hostname.tcl        # Hostname retrieval
│       └── cat_file.tcl        # File reading
├── tests/
│   ├── run_all_tests.sh        # Master test runner
│   ├── run_shellcheck.sh       # Shell script linter
│   ├── test_*.sh               # Component tests (8 files)
│   └── helpers/
│       ├── test_utils.tcl      # Test assertions
│       ├── mock_ssh.tcl        # Mock SSH session
│       ├── mock_ssh_server.sh  # Fake SSH server
│       └── mock_terminal.tcl   # Mock terminal
├── DESIGN.md                   # Detailed design document
└── README.md                   # This file
```

## How It Works

### Unique Prompt Injection

The core reliability feature. After SSH connection:

1. Disable terminal features that interfere (bracket-paste mode, colors)
2. Set a unique prompt: `XPCT<pid>>` (e.g., `XPCT12345>`)
3. All subsequent command output is captured between command echo and prompt

This works regardless of:
- Custom PS1 prompts (colors, git status, paths)
- Different shells (bash, zsh, sh, csh)
- ANSI escape codes
- Varying prompt styles across Linux/FreeBSD/Darwin

### Command Output Capture

When running a command:

1. Send command + carriage return
2. Skip first line (command echo)
3. Capture all lines until prompt appears
4. Return captured lines joined with newlines

### Line-by-Line Processing

Output is captured line-by-line to:
- Keep expect buffer small (prevents overflow on large outputs)
- Skip the echoed command reliably
- Filter out any lines containing the prompt marker

## Running Tests

### All Tests

```bash
./tests/run_all_tests.sh
```

### Individual Tests

```bash
./tests/test_debug.sh      # Debug module
./tests/test_prompt.sh     # Prompt detection
./tests/test_password.sh   # Password handling
./tests/test_sudo.sh       # Sudo password handling
./tests/test_ssh.sh        # SSH connection
./tests/test_sudo_exec.sh  # Sudo execution
./tests/test_hostname.sh   # Hostname command
./tests/test_cat_file.sh   # File reading
```

### Shell Script Linting

```bash
./tests/run_shellcheck.sh
```

All 11 shell scripts pass shellcheck.

## Test Architecture

### Mock-Based Testing

Tests use mock components instead of real SSH connections:

- **mock_ssh_server.sh** - A bash script that simulates SSH server behavior:
  - Password prompts
  - Shell prompts
  - Command responses (hostname, cat, whoami, etc.)
  - Error scenarios (auth failure, connection refused, sudo failure)

- **mock_ssh.tcl** - TCL wrapper to spawn and manage mock sessions

- **test_utils.tcl** - Test framework with assertions:
  - `test::assert_eq` - Equality check
  - `test::assert_true` / `test::assert_false` - Boolean checks
  - `test::assert_contains` - Substring check
  - `test::assert_match` - Regex match

### Test Coverage

| Component | Tests | Status |
|-----------|-------|--------|
| debug.tcl | 6 | Pass |
| prompt.tcl | 6 | Pass |
| password.tcl | 6 | Pass |
| sudo.tcl | 6 | Pass |
| ssh.tcl | 5 | Pass |
| sudo_exec.tcl | 3 | Pass |
| hostname.tcl | 3 | Pass |
| cat_file.tcl | 6 | Pass |
| **Total** | **41** | **All Pass** |

### What Is Tested

**Fully tested with mocks:**
- Debug level initialization and clamping
- Prompt marker generation (user and root variants)
- Prompt initialization on shell
- Command output capture
- Password retrieval from environment
- Password caching and clearing
- Sudo password handling
- SSH password prompt detection
- SSH error handling (auth failure, connection refused)
- Sudo password prompt detection
- Sudo failure detection
- Hostname retrieval
- File reading with security validation
- Filename escaping for shell safety

**Tested with local bash (no SSH):**
- prompt::init, prompt::run, prompt::wait against real bash
- commands::hostname::get against real hostname command
- commands::cat_file::read against real files

### What Is NOT Tested

**Requires real SSH target:**
- Actual SSH connection to remote host
- Real sudo elevation
- Cross-platform behavior (FreeBSD, Darwin)
- Network timeout handling
- SSH key authentication
- Multi-hop SSH connections

**Not implemented:**
- SSH key-based authentication (only password auth)
- Interactive command execution
- File upload/download (only cat for reading)
- Multiple command batching in single session
- Session persistence/reuse

## Known Limitations

1. **Password-only authentication** - No SSH key support
2. **Single command focus** - Tool runs one command (cat file) and exits
3. **No session reuse** - Each invocation creates a new SSH connection
4. **Bash-centric testing** - Tests run against bash; other shells tested via mock only
5. **No Windows support** - Requires POSIX environment

## Extending the Framework

### Adding a New Command Module

1. Create `lib/commands/your_command.tcl`:
```tcl
namespace eval commands::your_command {
    proc run {spawn_id args} {
        debug::log 4 "Running your_command"
        set output [prompt::run $spawn_id "your-shell-command"]
        return [string trim $output]
    }
}
```

2. Source it in `bin/ssh-automation`
3. Add test in `tests/test_your_command.sh`

### Adding Mock Behaviors

Edit `tests/helpers/mock_ssh_server.sh` and add case handlers:
```bash
"your-command")
    echo "mock output"
    ;;
```

## License

See LICENSE file.

## Contributing

1. Ensure all tests pass: `./tests/run_all_tests.sh`
2. Ensure shellcheck passes: `./tests/run_shellcheck.sh`
3. Add tests for new functionality
4. Update DESIGN.md for architectural changes
