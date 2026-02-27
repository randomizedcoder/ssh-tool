# nix/modules/vm-base.nix
#
# Base NixOS module for MicroVM configuration.
# Provides common console configuration and Nix store sharing.
#
# Usage in VM file:
#   imports = [ ../modules/vm-base.nix ];
#   vmBase = {
#     vmName = "agent-vm";
#     serialPort = 4100;
#     virtioPort = 4101;
#   };
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.vmBase;
in
{
  options.vmBase = {
    vmName = lib.mkOption {
      type = lib.types.str;
      description = "Name of the VM (used for QEMU process naming)";
    };

    serialPort = lib.mkOption {
      type = lib.types.int;
      description = "Port for slow serial console (ttyS0)";
    };

    virtioPort = lib.mkOption {
      type = lib.types.int;
      description = "Port for fast virtio console (hvc0)";
    };

    memoryMB = lib.mkOption {
      type = lib.types.int;
      default = 512;
      description = "Memory allocation in MB";
    };

    vcpus = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Number of virtual CPUs";
    };
  };

  config = {
    system.stateVersion = "24.05";

    # Console output to both ttyS0 (slow/early) and hvc0 (fast/virtio)
    boot.kernelParams = [
      "console=ttyS0,115200"
      "console=hvc0"
    ];

    # MicroVM base configuration
    microvm = {
      hypervisor = "qemu";
      mem = cfg.memoryMB;
      vcpu = cfg.vcpus;

      # Share Nix store from host (required for all VMs)
      shares = [
        {
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          proto = "9p";
        }
      ];

      # Serial console configuration for debugging
      qemu = {
        serialConsole = false; # We configure our own
        extraArgs = [
          "-name"
          "${cfg.vmName},process=${cfg.vmName}"
          # Slow serial console (ttyS0) - works early in boot
          "-serial"
          "tcp:127.0.0.1:${toString cfg.serialPort},server,nowait"
          # Fast virtio console (hvc0)
          "-device"
          "virtio-serial-pci"
          "-chardev"
          "socket,id=virtcon,port=${toString cfg.virtioPort},host=127.0.0.1,server=on,wait=off"
          "-device"
          "virtconsole,chardev=virtcon"
        ];
      };
    };
  };
}
