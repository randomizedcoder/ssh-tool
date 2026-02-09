#!/bin/bash
# mock_ssh_server.sh - Fake SSH server for testing
#
# Simulates SSH connection and shell behavior for testing
# Usage: mock_ssh_server.sh [behavior]
#
# Behaviors:
#   normal            - Normal SSH connection
#   auth_fail         - Authentication failure
#   connection_refused - Connection refused
#   sudo_fail         - Sudo authentication failure
#   host_verify       - Host key verification prompt
#   escape_sequences  - Output includes OSC/ANSI escape sequences
#   slow_response     - 2 second delay before responses
#   very_slow         - 10 second delay (should trigger timeout)
#   connection_drop   - Drops connection mid-output
#   large_output      - Returns 1000 lines of output
#   incomplete_line   - Returns output without trailing newline

BEHAVIOR="${1:-normal}"

# Simulate SSH connection based on behavior
case "$BEHAVIOR" in
    "connection_refused")
        echo "ssh: connect to host mockhost port 22: Connection refused"
        exit 1
        ;;
    "auth_fail")
        echo -n "password: "
        read -rs _password
        echo ""
        echo "Permission denied, please try again."
        echo -n "password: "
        read -rs _password
        echo ""
        echo "Permission denied (publickey,password)."
        exit 1
        ;;
    "host_verify")
        echo "The authenticity of host 'mockhost (192.168.1.100)' can't be established."
        echo "ECDSA key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx."
        echo -n "Are you sure you want to continue connecting (yes/no)? "
        read -r answer
        if [[ "$answer" != "yes" ]]; then
            echo "Host key verification failed."
            exit 1
        fi
        echo "Warning: Permanently added 'mockhost' (ECDSA) to the list of known hosts."
        ;&  # Fall through to normal behavior
    "escape_sequences")
        # Simulate systemd shell integration and ANSI codes
        EMIT_ESCAPES=1
        echo -n "password: "
        read -rs password
        echo ""
        # Emit OSC sequences like systemd does
        printf '\033]0;user@mockhost:~\007'
        printf $'\033]3008;start=mock-session-id;user=testuser\033\\\\'
        printf '\033[?2004h'  # Bracket paste mode
        echo "$ "
        ;;
    "slow_response")
        SLOW_MODE=2
        echo -n "password: "
        read -rs password
        echo ""
        echo "$ "
        ;;
    "very_slow")
        SLOW_MODE=10
        echo -n "password: "
        read -rs password
        echo ""
        echo "$ "
        ;;
    "connection_drop")
        echo -n "password: "
        read -rs password
        echo ""
        echo "$ "
        # Will drop on first command
        DROP_ON_COMMAND=1
        ;;
    "large_output")
        echo -n "password: "
        read -rs password
        echo ""
        echo "$ "
        ;;
    "incomplete_line")
        echo -n "password: "
        read -rs password
        echo ""
        echo "$ "
        ;;
    "normal"|*)
        # Normal connection flow
        echo -n "password: "
        read -rs password
        echo ""

        # Check for correct test password (password is used here)
        if [[ "$password" != "testpass123" && -n "$password" ]]; then
            # Accept any password for flexibility in testing
            :
        fi

        # Show initial prompt
        echo "$ "
        ;;
esac

# Main command loop
while IFS= read -r cmd; do
    # Remove carriage return if present
    cmd="${cmd%$'\r'}"

    # Handle empty lines
    if [[ -z "$cmd" ]]; then
        echo "$ "
        continue
    fi

    # Apply slow mode delay if set
    if [[ -n "$SLOW_MODE" ]]; then
        sleep "$SLOW_MODE"
    fi

    # Handle connection drop
    if [[ "$DROP_ON_COMMAND" == "1" ]]; then
        echo "partial output before"
        exit 1  # Simulate sudden disconnect
    fi

    # Check for prompt initialization (PS1 setting)
    if [[ "$cmd" == *"PS1="* ]]; then
        # Extract the prompt marker from PS1='XPCT...> '
        if [[ "$cmd" =~ PS1=\'([^\']+)\' ]]; then
            PROMPT="${BASH_REMATCH[1]}"
            echo "$PROMPT"
        else
            echo "$ "
        fi
        continue
    fi

    # Handle different commands
    case "$cmd" in
        "hostname")
            echo "mock-hostname"
            ;;
        "hostname -f")
            echo "mock-hostname.example.com"
            ;;
        "whoami")
            if [[ "$SUDO_MODE" == "1" ]]; then
                echo "root"
            else
                echo "testuser"
            fi
            ;;
        "cat "*)
            filename="${cmd#cat }"
            # Remove quotes if present
            filename="${filename//\'/}"
            filename="${filename//\"/}"

            case "$filename" in
                "/etc/os-release")
                    echo 'NAME="Mock Linux"'
                    echo 'VERSION="1.0"'
                    ;;
                "/etc/passwd")
                    echo "root:x:0:0:root:/root:/bin/bash"
                    echo "testuser:x:1000:1000:Test User:/home/testuser:/bin/bash"
                    ;;
                "/etc/fedora-release")
                    echo "Fedora release 39 (Thirty Nine)"
                    ;;
                "/nonexistent")
                    echo "cat: /nonexistent: No such file or directory"
                    ;;
                "/root/secret")
                    echo "cat: /root/secret: Permission denied"
                    ;;
                *)
                    echo "mock file contents for $filename"
                    ;;
            esac
            ;;
        "sudo -i")
            if [[ "$BEHAVIOR" == "sudo_fail" ]]; then
                echo "[sudo] password for testuser: "
                read -rs _sudo_pass
                echo ""
                echo "Sorry, try again."
                echo "[sudo] password for testuser: "
                read -rs _sudo_pass
                echo ""
                echo "Sorry, try again."
                echo "sudo: 3 incorrect password attempts"
            else
                echo "[sudo] password for testuser: "
                read -rs _sudo_pass
                echo ""
                export SUDO_MODE=1
                echo "# "
                continue
            fi
            ;;
        "exit")
            if [[ "$SUDO_MODE" == "1" ]]; then
                unset SUDO_MODE
                echo "$ "
                continue
            else
                exit 0
            fi
            ;;
        "test -f "*)
            filename="${cmd#test -f }"
            filename="${filename%% *}"
            filename="${filename//\'/}"
            if [[ "$filename" == "/etc/os-release" || "$filename" == "/etc/passwd" ]]; then
                # These files "exist"
                :
            fi
            # The && echo or || echo will be in the next part of the command
            ;;
        *"&& echo EXISTS"*)
            echo "EXISTS"
            ;;
        *"|| echo NOTFOUND"*)
            echo "NOTFOUND"
            ;;
        "echo_with_escapes")
            # Emit OSC sequences before and after output (like systemd does)
            printf $'\033]3008;start=cmd-id;type=command\033\\\\'
            printf '\033[32m'  # Green color
            echo "output with escapes"
            printf '\033[0m'   # Reset
            printf $'\033]3008;end=cmd-id;exit=success\033\\\\'
            ;;
        "echo_osc_title")
            # Emit window title OSC sequence
            printf '\033]0;window title here\007'
            echo "after title"
            ;;
        "echo_systemd_markers")
            # Emit systemd shell integration markers
            printf $'\033]3008;start=sess-id;user=test;hostname=mock;type=shell\033\\\\'
            echo "between markers"
            printf $'\033]3008;end=sess-id;exit=success\033\\\\'
            ;;
        "echo_ansi_colors")
            # Emit various ANSI color codes
            printf '\033[31mred\033[0m '
            printf '\033[32mgreen\033[0m '
            printf '\033[1;34mbold blue\033[0m'
            echo ""
            echo "plain text"
            ;;
        "seq 1 1000"|"large_seq")
            # Generate large output for buffer testing
            seq 1 1000
            ;;
        "seq 1 100")
            seq 1 100
            ;;
        "incomplete_output")
            # Output without trailing newline
            printf "no newline at end"
            ;;
        "multi_incomplete")
            echo "line one"
            echo "line two"
            printf "incomplete third"
            ;;
        *)
            # Unknown command - just echo it back as if it ran
            echo "$cmd: command simulated"
            ;;
    esac

    # Print prompt after command
    if [[ "$EMIT_ESCAPES" == "1" ]]; then
        # Emit escape sequences before prompt (like systemd shell integration)
        printf $'\033]3008;end=cmd-id;exit=success\033\\\\'
        printf $'\033]3008;start=sess-id;type=shell\033\\\\'
    fi

    if [[ "$SUDO_MODE" == "1" ]]; then
        echo "# "
    else
        if [[ -n "$PROMPT" ]]; then
            echo "$PROMPT"
        else
            echo "$ "
        fi
    fi
done
