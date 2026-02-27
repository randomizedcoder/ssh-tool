# nix/vm-scripts.nix
#
# Helper scripts for managing SSH-Tool MicroVMs.
# Provides status, start, stop, and restart functionality.
#
{ pkgs }:
let
  constants = import ./constants;
  network = constants.network;
  ports = constants.ports;
  users = constants.users;

  sshOpts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR";

  # VM definitions for management scripts
  vms = {
    agent = {
      name = "agent-vm";
      process = "microvm@agent";
      ip = network.agentVmIp;
      description = "Load test agent";
      buildTarget = "agent-vm-tap-debug";
    };
    mcp = {
      name = "mcp-vm";
      process = "microvm@mcp-vm";
      ip = network.mcpVmIp;
      port = ports.mcpServer;
      description = "MCP SSH server";
      buildTarget = "mcp-vm-tap-debug";
      healthCheck = "http://${network.mcpVmIp}:${toString ports.mcpServer}/health";
    };
    target = {
      name = "ssh-target";
      process = "microvm@ssh-target";
      ip = network.targetVmIp;
      description = "SSH target";
      buildTarget = "ssh-target-vm-tap-debug";
    };
  };
in
{
  #===========================================================================
  # STATUS CHECKS
  #===========================================================================

  # Quick check - just show running VMs
  check = pkgs.writeShellApplication {
    name = "ssh-vm-check";
    runtimeInputs = with pkgs; [
      procps
      gnugrep
      curl
      netcat
    ];
    text = ''
      echo "=== SSH-Tool MicroVMs Status ==="
      echo ""

      # Check each VM
      check_vm() {
        local name="$1"
        local process="$2"
        local ip="$3"

        if pgrep -f "$process" > /dev/null 2>&1; then
          pid=$(pgrep -f "$process" | head -1)
          echo -e "  $name:\t\033[32mRUNNING\033[0m (PID: $pid)"

          # Check network connectivity if IP provided
          if [[ -n "$ip" ]]; then
            if nc -z -w1 "$ip" 22 2>/dev/null; then
              echo -e "    Network:\t\033[32mOK\033[0m ($ip)"
            else
              echo -e "    Network:\t\033[33mNO RESPONSE\033[0m ($ip)"
            fi
          fi
        else
          echo -e "  $name:\t\033[31mSTOPPED\033[0m"
        fi
      }

      check_vm "agent-vm" "microvm@agent" "${network.agentVmIp}"
      check_vm "mcp-vm" "microvm@mcp-vm" "${network.mcpVmIp}"
      check_vm "ssh-target" "microvm@ssh-target" "${network.targetVmIp}"

      echo ""

      # Check MCP health if running
      if pgrep -f "microvm@mcp-vm" > /dev/null 2>&1; then
        echo "=== MCP Server Health ==="
        if health=$(curl -sf "http://${network.mcpVmIp}:${toString ports.mcpServer}/health" 2>/dev/null); then
          echo -e "  Status:\t\033[32mHEALTHY\033[0m"
          echo "  Response: $health"
        else
          echo -e "  Status:\t\033[33mNOT RESPONDING\033[0m"
        fi
        echo ""
      fi

      # Check network bridge
      echo "=== Network Bridge ==="
      if ip link show sshbr0 > /dev/null 2>&1; then
        echo -e "  sshbr0:\t\033[32mUP\033[0m"
        for tap in sshtap0 sshtap1 sshtap2; do
          if ip link show "$tap" > /dev/null 2>&1; then
            echo -e "  $tap:\t\033[32mUP\033[0m"
          else
            echo -e "  $tap:\t\033[31mDOWN\033[0m"
          fi
        done
      else
        echo -e "  sshbr0:\t\033[31mNOT CONFIGURED\033[0m"
        echo "  Run: sudo nix run .#ssh-network-setup"
      fi
      echo ""
    '';
  };

  # Detailed status with metrics
  status = pkgs.writeShellApplication {
    name = "ssh-vm-status";
    runtimeInputs = with pkgs; [
      procps
      gnugrep
      curl
      netcat
      jq
    ];
    text = ''
      echo "=== SSH-Tool MicroVMs Detailed Status ==="
      echo ""

      # Check each VM with resource usage
      check_vm_detailed() {
        local name="$1"
        local process="$2"
        local ip="$3"

        if pgrep -f "$process" > /dev/null 2>&1; then
          pid=$(pgrep -f "$process" | head -1)
          echo "[$name]"
          echo "  Status: RUNNING"
          echo "  PID: $pid"

          # Get memory usage
          mem=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
          echo "  Memory: $mem"

          # Get CPU usage
          cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1}')
          echo "  CPU: $cpu%"

          # Get uptime
          etime=$(ps -p "$pid" -o etime= 2>/dev/null | xargs)
          echo "  Uptime: $etime"

          # Check network
          if [[ -n "$ip" ]] && nc -z -w1 "$ip" 22 2>/dev/null; then
            echo "  Network: OK ($ip reachable)"
          elif [[ -n "$ip" ]]; then
            echo "  Network: UNREACHABLE ($ip)"
          fi
          echo ""
        else
          echo "[$name]"
          echo "  Status: STOPPED"
          echo ""
        fi
      }

      check_vm_detailed "agent-vm" "microvm@agent" "${network.agentVmIp}"
      check_vm_detailed "mcp-vm" "microvm@mcp-vm" "${network.mcpVmIp}"
      check_vm_detailed "ssh-target" "microvm@ssh-target" "${network.targetVmIp}"

      # MCP metrics if available
      if pgrep -f "microvm@mcp-vm" > /dev/null 2>&1; then
        echo "=== MCP Server Metrics ==="
        if health=$(curl -sf "http://${network.mcpVmIp}:${toString ports.mcpServer}/health" 2>/dev/null); then
          echo "$health" | jq -r 'to_entries | .[] | "  \(.key): \(.value)"' 2>/dev/null || echo "  $health"
        else
          echo "  Not available"
        fi
        echo ""
      fi
    '';
  };

  #===========================================================================
  # START VMs
  #===========================================================================

  # Start all VMs
  startAll = pkgs.writeShellApplication {
    name = "ssh-vm-start-all";
    runtimeInputs = with pkgs; [ procps coreutils ];
    text = ''
      echo "=== Starting All SSH-Tool MicroVMs ==="
      echo ""
      echo "This will start 3 VMs in the background."
      echo "Use 'nix run .#ssh-vm-check' to verify status."
      echo ""

      # Check network bridge first
      if ! ip link show sshbr0 > /dev/null 2>&1; then
        echo "ERROR: Network bridge sshbr0 not found!"
        echo "Run: sudo nix run .#ssh-network-setup"
        exit 1
      fi

      start_vm() {
        local name="$1"
        local process="$2"
        local build_target="$3"

        if pgrep -f "$process" > /dev/null 2>&1; then
          echo "  $name: Already running"
        else
          echo -n "  $name: Building..."
          if nix build ".#$build_target" 2>/dev/null; then
            echo -n " Starting..."
            nohup ./result/bin/microvm-run > "/tmp/$name.log" 2>&1 &
            sleep 1
            if pgrep -f "$process" > /dev/null 2>&1; then
              echo " OK"
            else
              echo " FAILED (check /tmp/$name.log)"
            fi
          else
            echo " BUILD FAILED"
          fi
        fi
      }

      # Start in order: target first (SSH server), then MCP, then agent
      start_vm "ssh-target" "microvm@ssh-target" "ssh-target-vm-tap-debug"
      start_vm "mcp-vm" "microvm@mcp-vm" "mcp-vm-tap-debug"
      start_vm "agent-vm" "microvm@agent" "agent-vm-tap-debug"

      echo ""
      echo "Waiting for VMs to boot (30 seconds)..."
      sleep 30

      echo ""
      echo "=== Status ==="
      nix run .#ssh-vm-check 2>/dev/null || true
    '';
  };

  # Start individual VMs
  startTarget = pkgs.writeShellApplication {
    name = "ssh-vm-start-target";
    runtimeInputs = with pkgs; [ procps coreutils ];
    text = ''
      if pgrep -f "microvm@ssh-target" > /dev/null 2>&1; then
        echo "ssh-target VM is already running"
        exit 0
      fi

      echo "Building ssh-target VM..."
      nix build .#ssh-target-vm-tap-debug

      echo "Starting ssh-target VM in background..."
      nohup ./result/bin/microvm-run > /tmp/ssh-target.log 2>&1 &

      echo "VM starting... (logs at /tmp/ssh-target.log)"
      echo "Use 'nix run .#ssh-vm-check' to verify status"
    '';
  };

  startMcp = pkgs.writeShellApplication {
    name = "ssh-vm-start-mcp";
    runtimeInputs = with pkgs; [ procps coreutils ];
    text = ''
      if pgrep -f "microvm@mcp-vm" > /dev/null 2>&1; then
        echo "mcp-vm is already running"
        exit 0
      fi

      echo "Building mcp-vm..."
      nix build .#mcp-vm-tap-debug

      echo "Starting mcp-vm in background..."
      nohup ./result/bin/microvm-run > /tmp/mcp-vm.log 2>&1 &

      echo "VM starting... (logs at /tmp/mcp-vm.log)"
      echo "Use 'nix run .#ssh-vm-check' to verify status"
    '';
  };

  startAgent = pkgs.writeShellApplication {
    name = "ssh-vm-start-agent";
    runtimeInputs = with pkgs; [ procps coreutils ];
    text = ''
      if pgrep -f "microvm@agent" > /dev/null 2>&1; then
        echo "agent-vm is already running"
        exit 0
      fi

      echo "Building agent-vm..."
      nix build .#agent-vm-tap-debug

      echo "Starting agent-vm in background..."
      nohup ./result/bin/microvm-run > /tmp/agent-vm.log 2>&1 &

      echo "VM starting... (logs at /tmp/agent-vm.log)"
      echo "Use 'nix run .#ssh-vm-check' to verify status"
    '';
  };

  #===========================================================================
  # STOP VMs
  #===========================================================================

  # Graceful stop (SIGTERM) - all VMs
  stop = pkgs.writeShellApplication {
    name = "ssh-vm-stop";
    runtimeInputs = with pkgs; [ procps ];
    text = ''
      echo "Stopping all SSH-Tool MicroVMs gracefully (SIGTERM)..."

      stop_vm() {
        local name="$1"
        local process="$2"

        if pgrep -f "$process" > /dev/null 2>&1; then
          echo -n "  $name: Stopping..."
          pkill -TERM -f "$process" 2>/dev/null || true
          # Wait up to 10 seconds for graceful shutdown
          for _ in {1..10}; do
            if ! pgrep -f "$process" > /dev/null 2>&1; then
              echo " OK"
              return 0
            fi
            sleep 1
          done
          echo " TIMEOUT (still running)"
          return 1
        else
          echo "  $name: Not running"
          return 0
        fi
      }

      stop_vm "agent-vm" "microvm@agent"
      stop_vm "mcp-vm" "microvm@mcp-vm"
      stop_vm "ssh-target" "microvm@ssh-target"

      echo ""
      echo "Done. Use 'nix run .#ssh-vm-check' to verify."
    '';
  };

  # Forceful stop (SIGKILL) - all VMs
  stopForce = pkgs.writeShellApplication {
    name = "ssh-vm-stop-force";
    runtimeInputs = with pkgs; [ procps ];
    text = ''
      echo "Force stopping all SSH-Tool MicroVMs (SIGKILL)..."

      for process in "microvm@agent" "microvm@mcp-vm" "microvm@ssh-target"; do
        if pgrep -f "$process" > /dev/null 2>&1; then
          pkill -9 -f "$process" 2>/dev/null || true
          echo "  Killed: $process"
        fi
      done

      # Also kill any orphaned qemu processes
      if pgrep -f "qemu.*ssh" > /dev/null 2>&1; then
        pkill -9 -f "qemu.*ssh" 2>/dev/null || true
        echo "  Killed orphaned QEMU processes"
      fi

      echo ""
      echo "Done."
    '';
  };

  # Stop individual VMs
  stopTarget = pkgs.writeShellApplication {
    name = "ssh-vm-stop-target";
    runtimeInputs = with pkgs; [ procps ];
    text = ''
      if pgrep -f "microvm@ssh-target" > /dev/null 2>&1; then
        echo "Stopping ssh-target VM..."
        pkill -TERM -f "microvm@ssh-target"
        sleep 2
        if pgrep -f "microvm@ssh-target" > /dev/null 2>&1; then
          echo "Graceful stop failed, forcing..."
          pkill -9 -f "microvm@ssh-target"
        fi
        echo "Stopped."
      else
        echo "ssh-target VM is not running"
      fi
    '';
  };

  stopMcp = pkgs.writeShellApplication {
    name = "ssh-vm-stop-mcp";
    runtimeInputs = with pkgs; [ procps ];
    text = ''
      if pgrep -f "microvm@mcp-vm" > /dev/null 2>&1; then
        echo "Stopping mcp-vm..."
        pkill -TERM -f "microvm@mcp-vm"
        sleep 2
        if pgrep -f "microvm@mcp-vm" > /dev/null 2>&1; then
          echo "Graceful stop failed, forcing..."
          pkill -9 -f "microvm@mcp-vm"
        fi
        echo "Stopped."
      else
        echo "mcp-vm is not running"
      fi
    '';
  };

  stopAgent = pkgs.writeShellApplication {
    name = "ssh-vm-stop-agent";
    runtimeInputs = with pkgs; [ procps ];
    text = ''
      if pgrep -f "microvm@agent" > /dev/null 2>&1; then
        echo "Stopping agent-vm..."
        pkill -TERM -f "microvm@agent"
        sleep 2
        if pgrep -f "microvm@agent" > /dev/null 2>&1; then
          echo "Graceful stop failed, forcing..."
          pkill -9 -f "microvm@agent"
        fi
        echo "Stopped."
      else
        echo "agent-vm is not running"
      fi
    '';
  };

  #===========================================================================
  # RESTART VMs
  #===========================================================================

  # Restart all VMs
  restartAll = pkgs.writeShellApplication {
    name = "ssh-vm-restart-all";
    runtimeInputs = with pkgs; [ procps coreutils ];
    text = ''
      echo "=== Restarting All SSH-Tool MicroVMs ==="
      nix run .#ssh-vm-stop
      sleep 2
      nix run .#ssh-vm-start-all
    '';
  };

  # Restart MCP VM (most common use case)
  restartMcp = pkgs.writeShellApplication {
    name = "ssh-vm-restart-mcp";
    runtimeInputs = with pkgs; [ procps coreutils curl ];
    text = ''
      echo "=== Restarting MCP VM ==="

      # Stop if running
      if pgrep -f "microvm@mcp-vm" > /dev/null 2>&1; then
        echo "Stopping current MCP VM..."
        pkill -TERM -f "microvm@mcp-vm"
        sleep 3
        if pgrep -f "microvm@mcp-vm" > /dev/null 2>&1; then
          pkill -9 -f "microvm@mcp-vm"
        fi
      fi

      # Rebuild with latest code
      echo "Rebuilding MCP VM with latest code..."
      nix build .#mcp-vm-tap-debug

      # Start
      echo "Starting MCP VM..."
      nohup ./result/bin/microvm-run > /tmp/mcp-vm.log 2>&1 &

      # Wait for boot
      echo "Waiting for MCP VM to boot..."
      for _ in {1..30}; do
        if curl -sf "http://${network.mcpVmIp}:${toString ports.mcpServer}/health" > /dev/null 2>&1; then
          echo ""
          echo "MCP VM is ready!"
          curl -sf "http://${network.mcpVmIp}:${toString ports.mcpServer}/health"
          echo ""
          exit 0
        fi
        echo -n "."
        sleep 1
      done

      echo ""
      echo "WARNING: MCP server not responding after 30 seconds"
      echo "Check logs: /tmp/mcp-vm.log"
    '';
  };

  #===========================================================================
  # SSH ACCESS
  #===========================================================================

  sshAgent = pkgs.writeShellApplication {
    name = "ssh-vm-ssh-agent";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
    ];
    text = ''
      echo "Connecting to Agent VM..."
      sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString ports.sshForwardAgent} \
        testuser@localhost "$@"
    '';
  };

  sshMcp = pkgs.writeShellApplication {
    name = "ssh-vm-ssh-mcp";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
    ];
    text = ''
      echo "Connecting to MCP VM..."
      sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p ${toString ports.sshForwardMcp} \
        testuser@localhost "$@"
    '';
  };

  sshTarget = pkgs.writeShellApplication {
    name = "ssh-vm-ssh-target";
    runtimeInputs = with pkgs; [
      openssh
      sshpass
    ];
    text = ''
      port="''${1:-2222}"
      user="''${2:-testuser}"
      shift 2 2>/dev/null || true

      echo "Connecting to SSH target VM (port $port, user $user)..."
      sshpass -p "${users.testuser.password}" ssh ${sshOpts} -p "$port" \
        "$user@localhost" "$@"
    '';
  };

  #===========================================================================
  # LOGS
  #===========================================================================

  logs = pkgs.writeShellApplication {
    name = "ssh-vm-logs";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      vm="''${1:-all}"

      case "$vm" in
        agent)
          echo "=== Agent VM Logs ==="
          tail -f /tmp/agent-vm.log 2>/dev/null || echo "No logs found"
          ;;
        mcp)
          echo "=== MCP VM Logs ==="
          tail -f /tmp/mcp-vm.log 2>/dev/null || echo "No logs found"
          ;;
        target)
          echo "=== SSH Target VM Logs ==="
          tail -f /tmp/ssh-target.log 2>/dev/null || echo "No logs found"
          ;;
        all)
          echo "Available log files:"
          for log in /tmp/agent-vm.log /tmp/mcp-vm.log /tmp/ssh-target.log; do
            if [[ -f "$log" ]]; then
              stat --printf='  %n (%s bytes, modified %y)\n' "$log"
            fi
          done
          if ! [[ -f /tmp/agent-vm.log || -f /tmp/mcp-vm.log || -f /tmp/ssh-target.log ]]; then
            echo "  No VM logs found"
          fi
          echo ""
          echo "Usage: nix run .#ssh-vm-logs -- [agent|mcp|target]"
          ;;
        *)
          echo "Unknown VM: $vm"
          echo "Usage: nix run .#ssh-vm-logs -- [agent|mcp|target|all]"
          exit 1
          ;;
      esac
    '';
  };
}
