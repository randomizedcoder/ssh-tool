# nix/vm-scripts.nix
#
# Helper scripts for managing SSH-Tool MicroVMs.
#
{ pkgs }:
let
  constants = import ./constants;
  network = constants.network;
  ports = constants.ports;
  users = constants.users;

  sshOpts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR";
in
{
  check = pkgs.writeShellApplication {
    name = "ssh-vm-check";
    runtimeInputs = with pkgs; [
      procps
      gnugrep
    ];
    text = ''
      echo "=== SSH-Tool MicroVMs ==="
      count=$(pgrep -f "microvm.*ssh" -c 2>/dev/null || echo 0)
      echo "Running VMs: $count"
      if [[ $count -gt 0 ]]; then
        pgrep -af "microvm.*ssh" || true
      fi
    '';
  };

  stop = pkgs.writeShellApplication {
    name = "ssh-vm-stop";
    runtimeInputs = with pkgs; [ procps ];
    text = ''
      echo "Stopping all SSH-Tool MicroVMs..."
      pkill -f "microvm.*ssh" 2>/dev/null || echo "No VMs running"
    '';
  };

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
}
