# nix/constants/ports.nix
#
# Port assignments for SSH-Tool MicroVM infrastructure.
# Centralizes all port configuration to prevent conflicts.
#
{
  # MCP server HTTP port
  mcpServer = 3000;

  # Host port forwarding (user-mode networking)
  sshForwardAgent = 22005; # Host -> Agent VM SSH
  sshForwardMcp = 22010; # Host -> MCP VM SSH
  mcpForward = 3000; # Host -> MCP VM HTTP (same as mcpServer)

  # Base port for multi-sshd (target VM)
  # Daemons run on 2222, 2223, 2224, 2225, 2226, 2227, 2228
  sshBase = 2222;

  # Netem port offset
  # Degraded ports = base port + offset
  # e.g., 2222 + 100 = 2322 (with network emulation)
  netemOffset = 100;

  # Serial console ports for VM debugging
  # Each VM gets two console ports: slow (ttyS0) and fast (hvc0/virtio)
  # Connect with: nc localhost <port> or socat - TCP:localhost:<port>
  console = {
    # Agent VM consoles
    agentSerial = 4100; # ttyS0 (slow, but works early in boot)
    agentVirtio = 4101; # hvc0 (fast virtio console)

    # MCP VM consoles
    mcpSerial = 4110; # ttyS0
    mcpVirtio = 4111; # hvc0

    # Target VM consoles
    targetSerial = 4120; # ttyS0
    targetVirtio = 4121; # hvc0
  };
}
