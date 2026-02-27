# nix/constants/default.nix
#
# Aggregates all modular constants for convenience.
# Usage: constants = import ./nix/constants;
#
{
  network = import ./network.nix;
  ports = import ./ports.nix;
  timeouts = import ./timeouts.nix;
  users = import ./users.nix;
  sshd = import ./sshd.nix;
  netem = import ./netem.nix;
  loadtest = import ./loadtest.nix;
  resources = import ./resources.nix;
}
