# nix/lib/ssh-options.nix
#
# Centralized SSH command options.
# Single source of truth for SSH client options used across tests.
#
{ lib }:
{
  # Base SSH options for test scripts (disable host key checking, quiet logging)
  base = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR";

  # Extended SSH options with connect timeout
  withTimeout =
    timeout:
    "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=${toString timeout}";

  # Default timeout version (10 seconds)
  withDefaultTimeout = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10";
}
