#!/bin/bash
# mock_ssh_server.sh - Fake SSH server for testing
#
# Simulates SSH connection and shell behavior for testing
# Usage: mock_ssh_server.sh [behavior]
#   behavior: normal, auth_fail, connection_refused, sudo_fail

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
        *)
            # Unknown command - just echo it back as if it ran
            echo "$cmd: command simulated"
            ;;
    esac

    # Print prompt after command
    if [[ "$SUDO_MODE" == "1" ]]; then
        echo "# "
    else
        echo "$ "
    fi
done
