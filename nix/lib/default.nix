# nix/lib/default.nix
#
# Aggregates all library modules for the SSH-Tool Nix infrastructure.
# Usage: nixLib = import ./nix/lib { inherit pkgs lib; };
#
{ pkgs, lib }:
{
  # Test helpers for shell scripts
  testHelpers = import ./test-helpers.nix { inherit lib; };

  # SSH command options
  sshOptions = import ./ssh-options.nix { inherit lib; };

  # SSHD configuration helpers
  sshdConfig = import ./sshd-config.nix { inherit pkgs lib; };

  # VM variant generators
  vmVariants = import ./vm-variants.nix { inherit lib; };

  # App definition helpers
  apps = import ./apps.nix { inherit lib; };
}
