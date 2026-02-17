# nix/constants/network.nix
#
# Network configuration for SSH-Tool MicroVM infrastructure.
# Three VMs connected via a single bridge:
#   - Agent VM:  Runs TCL test client (simulates AI agent)
#   - MCP VM:    Runs MCP server
#   - Target VM: Runs multiple SSHD instances
#
{
  # TAP networking - bridge and TAP device names
  bridge = "sshbr0";
  tapAgent = "sshtap0";
  tapMcp = "sshtap1";
  tapTarget = "sshtap2";

  # Network addressing
  subnet = "10.178.0.0/24";
  gateway = "10.178.0.1";

  # VM IP addresses (TAP mode only)
  agentVmIp = "10.178.0.5";
  mcpVmIp = "10.178.0.10";
  targetVmIp = "10.178.0.20";

  # MAC addresses (consistent for reproducibility)
  agentVmMac = "02:00:00:0a:b2:00";
  mcpVmMac = "02:00:00:0a:b2:01";
  targetVmMac = "02:00:00:0a:b2:02";
}
