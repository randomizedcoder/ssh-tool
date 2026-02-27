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
  constants = import ./constants;
  network = constants.network;
  ports = constants.ports;
  users = constants.users;
  resources = constants.resources.profiles.default;

  # Expect with Tcl 9.0 support
  # TODO: Replace with pkgs.tclPackages_9_0.expect after PR #490930 merges
  expect-tcl9 = pkgs.callPackage ./expect-tcl9 { };

  useTap = networking == "tap";

  # Build the NixOS system for the MicroVM
  nixos = nixpkgs.lib.nixosSystem {
    inherit system;

    modules = [
      microvm.nixosModules.microvm

      # Import shared modules
      ./modules/vm-base.nix
      ./modules/vm-networking.nix
      ./modules/vm-users.nix

      (
        { config, pkgs, ... }:
        {
          nixpkgs.hostPlatform = system;

          # ─── VM Base Configuration ───────────────────────────────────────
          vmBase = {
            vmName = "mcp-vm";
            serialPort = ports.console.mcpSerial;
            virtioPort = ports.console.mcpVirtio;
            memoryMB = resources.mcp.memoryMB;
            vcpus = resources.mcp.vcpus;
          };

          # ─── Networking ──────────────────────────────────────────────────
          vmNetworking = {
            inherit useTap;
            tapDevice = network.tapMcp;
            macAddress = network.mcpVmMac;
            ipAddress = network.mcpVmIp;
            gateway = network.gateway;
            hostPorts = [
              {
                host = ports.mcpForward;
                guest = 3000;
              }
              {
                host = ports.sshForwardMcp;
                guest = 22;
              }
            ];
          };

          networking.hostName = "mcp-vm";
          networking.firewall.allowedTCPPorts = [
            22
            3000
          ];

          # ─── Users ───────────────────────────────────────────────────────
          vmUsers = {
            testUserPassword = users.testuser.password;
            enableDebugRoot = debugMode;
            rootPassword = users.root.password;
            enablePasswordAuth = debugMode;
          };

          # ─── Packages ────────────────────────────────────────────────────
          environment.systemPackages = with pkgs; [
            expect-tcl9
            tcl-9_0
            curl
            jq
            openssh
          ];

          # ─── MCP Server Service ──────────────────────────────────────────
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
              ExecStart = "${expect-tcl9}/bin/expect ${self}/mcp/server.tcl --port 3000 --bind 0.0.0.0 --debug DEBUG";
              Restart = "always";
              WorkingDirectory = "${self}";
            };
          };

          # ─── MOTD ────────────────────────────────────────────────────────
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
