# nix/mcp-vm.nix
#
# MicroVM running the MCP SSH Automation Server.
# Uses `self` to ensure VM runs the exact code from the flake's commit.
#
# This VM:
# - Runs the MCP server on port 3000
# - Has expect-tcl9 (Expect with Tcl 9.0) for SSH automation
# - Has sshd for "SSH to localhost" testing
# - Can SSH to the ssh-target-vm
#
{
  self, # Flake self-reference for reproducible source access
  pkgs,
  lib,
  microvm,
  nixpkgs,
  system,
  networking ? "user",
  debugMode ? false,
}:
let
  # Import modular constants
  network = import ./constants/network.nix;
  ports = import ./constants/ports.nix;
  users = import ./constants/users.nix;
  timeouts = import ./constants/timeouts.nix;

  # Expect with Tcl 9.0 support
  # TODO: Replace with pkgs.tclPackages_9_0.expect after PR #490930 merges
  expect-tcl9 = pkgs.callPackage ./expect-tcl9 { };

  useTap = networking == "tap";

  # Build the NixOS system for the MicroVM
  nixos = nixpkgs.lib.nixosSystem {
    inherit system;

    modules = [
      microvm.nixosModules.microvm

      (
        { config, pkgs, ... }:
        {
          system.stateVersion = "24.05";
          nixpkgs.hostPlatform = system;

          # ─── MicroVM Configuration ─────────────────────────────────────
          microvm = {
            hypervisor = "qemu";
            mem = users.vmResources.mcp.memoryMB;
            vcpu = users.vmResources.mcp.vcpus;

            shares = [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "9p";
              }
            ];

            interfaces =
              if useTap then
                [
                  {
                    type = "tap";
                    id = network.tapMcp;
                    mac = network.mcpVmMac;
                  }
                ]
              else
                [
                  {
                    type = "user";
                    id = "eth0";
                    mac = network.mcpVmMac;
                  }
                ];

            forwardPorts = lib.optionals (!useTap) [
              {
                from = "host";
                host.port = ports.mcpForward;
                guest.port = 3000;
              }
              {
                from = "host";
                host.port = ports.sshForwardMcp;
                guest.port = 22;
              }
            ];

            # Serial console configuration for debugging
            # Connect with: nc localhost 4110 (slow) or nc localhost 4111 (fast)
            qemu = {
              serialConsole = false; # We configure our own
              extraArgs = [
                "-name"
                "mcp-vm,process=mcp-vm"
                # Slow serial console (ttyS0) - works early in boot
                "-serial"
                "tcp:127.0.0.1:${toString ports.console.mcpSerial},server,nowait"
                # Fast virtio console (hvc0)
                "-device"
                "virtio-serial-pci"
                "-chardev"
                "socket,id=virtcon,port=${toString ports.console.mcpVirtio},host=127.0.0.1,server=on,wait=off"
                "-device"
                "virtconsole,chardev=virtcon"
              ];
            };
          };

          # Console output to both ttyS0 (slow/early) and hvc0 (fast/virtio)
          boot.kernelParams = [
            "console=ttyS0,115200"
            "console=hvc0"
          ];

          # ─── Networking ────────────────────────────────────────────────
          networking.hostName = "mcp-vm";
          networking.firewall.allowedTCPPorts = [
            22
            3000
          ];

          # Use systemd-networkd for reliable interface matching
          # The TAP interface appears as enp0s3 (PCI naming) not eth0
          systemd.network = lib.mkIf useTap {
            enable = true;
            networks."10-lan" = {
              matchConfig.Driver = "virtio_net";
              address = [ "${network.mcpVmIp}/24" ];
              gateway = [ network.gateway ];
            };
          };
          networking.useNetworkd = lib.mkIf useTap true;

          # ─── SSH Server ────────────────────────────────────────────────
          services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = debugMode;
              PermitRootLogin = if debugMode then "yes" else "prohibit-password";
            };
          };

          # ─── Packages ──────────────────────────────────────────────────
          environment.systemPackages = with pkgs; [
            expect-tcl9
            tcl-9_0
            curl
            jq
            openssh
          ];

          # ─── Test User ─────────────────────────────────────────────────
          users.users.testuser = {
            isNormalUser = true;
            password = users.testuser.password;
            extraGroups = [ "wheel" ];
          };

          users.users.root.password = lib.mkIf debugMode users.root.password;

          security.sudo.wheelNeedsPassword = false;

          # ─── MCP Server Service ────────────────────────────────────────
          # Uses `self` to run the exact code from the flake's commit.
          # This ensures reproducibility - the VM always runs the committed version.
          systemd.services.mcp-server = {
            description = "MCP SSH Automation Server";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            # Add openssh to PATH so expect can spawn ssh
            path = [ pkgs.openssh ];
            serviceConfig = {
              Type = "simple";
              # Use flake's self-reference for source
              ExecStart = "${expect-tcl9}/bin/expect ${self}/mcp/server.tcl --port 3000 --bind 0.0.0.0";
              Restart = "always";
              WorkingDirectory = "${self}";
            };
          };

          # ─── MOTD ──────────────────────────────────────────────────────
          environment.etc."motd".text =
            if debugMode then
              ''
                ╔═══════════════════════════════════════════════════════════════╗
                ║  MCP-VM: DEBUG MODE - Password authentication enabled         ║
                ║  User: testuser                                               ║
                ║  Password: ${users.testuser.password}                         ║
                ║                                                               ║
                ║  MCP Server: http://localhost:3000                            ║
                ║  Health:     curl http://localhost:3000/health                ║
                ╚═══════════════════════════════════════════════════════════════╝
              ''
            else
              ''
                MCP-VM: MCP SSH Automation Server
                MCP Server: http://localhost:3000
              '';
        }
      )
    ];
  };

in
nixos.config.microvm.declaredRunner
