# nix/network-setup.nix
#
# TAP/bridge network setup for multi-VM testing.
# Creates a bridge with two TAP devices for MCP VM and target VM.
#
{ pkgs }:
let
  network = import ./constants/network.nix;
in
{
  setup = pkgs.writeShellApplication {
    name = "ssh-network-setup";
    runtimeInputs = with pkgs; [
      iproute2
      kmod
      nftables
    ];
    text = ''
      set -euo pipefail

      echo "=== SSH-Tool MicroVM Network Setup ==="

      # Load kernel modules
      sudo modprobe tun
      sudo modprobe bridge

      # Create bridge
      if ! ip link show ${network.bridge} &>/dev/null; then
        echo "Creating bridge ${network.bridge}..."
        sudo ip link add ${network.bridge} type bridge
        sudo ip addr add ${network.gateway}/24 dev ${network.bridge}
        sudo ip link set ${network.bridge} up
      else
        echo "Bridge ${network.bridge} already exists"
      fi

      # Create TAP for Agent VM
      if ! ip link show ${network.tapAgent} &>/dev/null; then
        echo "Creating TAP ${network.tapAgent} for Agent VM..."
        sudo ip tuntap add dev ${network.tapAgent} mode tap multi_queue user "''${SUDO_USER:-$USER}"
        sudo ip link set ${network.tapAgent} master ${network.bridge}
        sudo ip link set ${network.tapAgent} up
      else
        echo "TAP ${network.tapAgent} already exists"
      fi

      # Create TAP for MCP VM
      if ! ip link show ${network.tapMcp} &>/dev/null; then
        echo "Creating TAP ${network.tapMcp} for MCP VM..."
        sudo ip tuntap add dev ${network.tapMcp} mode tap multi_queue user "''${SUDO_USER:-$USER}"
        sudo ip link set ${network.tapMcp} master ${network.bridge}
        sudo ip link set ${network.tapMcp} up
      else
        echo "TAP ${network.tapMcp} already exists"
      fi

      # Create TAP for target VM
      if ! ip link show ${network.tapTarget} &>/dev/null; then
        echo "Creating TAP ${network.tapTarget} for target VM..."
        sudo ip tuntap add dev ${network.tapTarget} mode tap multi_queue user "''${SUDO_USER:-$USER}"
        sudo ip link set ${network.tapTarget} master ${network.bridge}
        sudo ip link set ${network.tapTarget} up
      else
        echo "TAP ${network.tapTarget} already exists"
      fi

      # NAT for VM internet access
      echo "Configuring NAT..."
      sudo nft add table inet ssh-nat 2>/dev/null || true
      sudo nft flush table inet ssh-nat 2>/dev/null || true
      sudo nft -f - <<EOF
      table inet ssh-nat {
        chain postrouting {
          type nat hook postrouting priority 100;
          ip saddr ${network.subnet} masquerade
        }
        chain forward {
          type filter hook forward priority 0;
          iifname "${network.bridge}" accept
          oifname "${network.bridge}" ct state related,established accept
        }
      }
      EOF

      sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

      echo ""
      echo "Network ready:"
      echo "  Agent VM:  ${network.agentVmIp} (TCL test agent)"
      echo "  MCP VM:    ${network.mcpVmIp}:3000 (MCP), :22 (SSH)"
      echo "  Target VM: ${network.targetVmIp}:2222-2228 (SSH), :2322-2328 (netem)"
    '';
  };

  teardown = pkgs.writeShellApplication {
    name = "ssh-network-teardown";
    runtimeInputs = with pkgs; [
      iproute2
      nftables
    ];
    text = ''
      set -euo pipefail

      echo "=== SSH-Tool MicroVM Network Teardown ==="

      # Remove TAP devices
      for tap in ${network.tapAgent} ${network.tapMcp} ${network.tapTarget}; do
        if ip link show "$tap" &>/dev/null; then
          sudo ip link del "$tap"
          echo "Removed TAP $tap"
        fi
      done

      # Remove bridge
      if ip link show ${network.bridge} &>/dev/null; then
        sudo ip link set ${network.bridge} down
        sudo ip link del ${network.bridge}
        echo "Removed bridge ${network.bridge}"
      fi

      # Remove NAT rules
      sudo nft delete table inet ssh-nat 2>/dev/null && echo "Removed NAT rules" || true

      echo "Network teardown complete"
    '';
  };
}
