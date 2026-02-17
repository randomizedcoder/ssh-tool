# nix/constants/timeouts.nix
#
# Global timeout configuration for SSH-Tool.
# Adjust these when testing with high-latency netem profiles.
#
{
  # Expect script timeouts (seconds)
  expect = {
    default = 30; # Standard operations
    connect = 60; # SSH connection establishment
    command = 30; # Command execution
    netem = 120; # Operations over degraded network
    slowAuth = 10; # Authentication (excluding PAM delay)
  };

  # Test harness timeouts (seconds)
  test = {
    vmBoot = 120; # Wait for VM to boot
    sshReady = 60; # Wait for sshd to accept connections
    mcpReady = 30; # Wait for MCP server health endpoint
  };

  # SSH client options
  ssh = {
    connectTimeout = 10; # -o ConnectTimeout
    serverAliveInterval = 15;
    serverAliveCountMax = 3;
  };
}
