# nix/modules/vm-networking.nix
#
# Networking configuration module for MicroVMs.
# Handles both TAP and user-mode networking with proper conditionals.
#
# Usage in VM file:
#   imports = [ ../modules/vm-networking.nix ];
#   vmNetworking = {
#     useTap = true;
#     tapDevice = "sshtap0";
#     macAddress = "02:00:00:0a:b2:00";
#     ipAddress = "10.178.0.5";
#     gateway = "10.178.0.1";
#     hostPorts = [ { host = 22005; guest = 22; } ];  # Only used for user networking
#   };
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.vmNetworking;
in
{
  options.vmNetworking = {
    useTap = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to use TAP networking (true) or user-mode networking (false)";
    };

    tapDevice = lib.mkOption {
      type = lib.types.str;
      description = "Name of the TAP device to use (when useTap = true)";
    };

    macAddress = lib.mkOption {
      type = lib.types.str;
      description = "MAC address for the network interface";
    };

    ipAddress = lib.mkOption {
      type = lib.types.str;
      description = "IP address for TAP networking";
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      description = "Gateway IP for TAP networking";
    };

    hostPorts = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            host = lib.mkOption { type = lib.types.int; };
            guest = lib.mkOption { type = lib.types.int; };
          };
        }
      );
      default = [ ];
      description = "Port forwards for user-mode networking";
    };
  };

  config = {
    # MicroVM network interface configuration
    microvm.interfaces =
      if cfg.useTap then
        [
          {
            type = "tap";
            id = cfg.tapDevice;
            mac = cfg.macAddress;
          }
        ]
      else
        [
          {
            type = "user";
            id = "eth0";
            mac = cfg.macAddress;
          }
        ];

    # Port forwarding for user-mode networking
    microvm.forwardPorts = lib.optionals (!cfg.useTap) (
      map (p: {
        from = "host";
        host.port = p.host;
        guest.port = p.guest;
      }) cfg.hostPorts
    );

    # Use systemd-networkd for TAP networking
    # The TAP interface appears as enp0s3 (PCI naming) not eth0
    systemd.network = lib.mkIf cfg.useTap {
      enable = true;
      networks."10-lan" = {
        matchConfig.Driver = "virtio_net";
        address = [ "${cfg.ipAddress}/24" ];
        gateway = [ cfg.gateway ];
      };
    };
    networking.useNetworkd = lib.mkIf cfg.useTap true;
  };
}
