# nix/agent-vm.nix
#
# MicroVM running the TCL test agent.
# Simulates an AI agent talking to the MCP server via HTTP/JSON-RPC.
#
# This VM:
# - Has TCL 9 for running the agent client
# - Has network access to MCP VM and Target VM
# - Runs E2E tests on boot (debug mode) or via manual invocation
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
            vmName = "agent-vm";
            serialPort = ports.console.agentSerial;
            virtioPort = ports.console.agentVirtio;
            memoryMB = resources.agent.memoryMB;
            vcpus = resources.agent.vcpus;
          };

          # ─── Networking ──────────────────────────────────────────────────
          vmNetworking = {
            inherit useTap;
            tapDevice = network.tapAgent;
            macAddress = network.agentVmMac;
            ipAddress = network.agentVmIp;
            gateway = network.gateway;
            hostPorts = [
              {
                host = ports.sshForwardAgent;
                guest = 22;
              }
            ];
          };

          networking.hostName = "agent-vm";
          networking.firewall.allowedTCPPorts = [ 22 ];

          # ─── Users ───────────────────────────────────────────────────────
          vmUsers = {
            testUserPassword = users.testuser.password;
            enableDebugRoot = debugMode;
            rootPassword = users.root.password;
            enablePasswordAuth = debugMode;
          };

          # ─── Packages ────────────────────────────────────────────────────
          environment.systemPackages = with pkgs; [
            tcl-9_0
            curl
            jq
            netcat-gnu
          ];

          # ─── Agent Source ────────────────────────────────────────────────
          # Copy agent scripts to /opt/agent
          environment.etc."agent/http_client.tcl".source = "${self}/mcp/agent/http_client.tcl";
          environment.etc."agent/json.tcl".source = "${self}/mcp/agent/json.tcl";
          environment.etc."agent/mcp_client.tcl".source = "${self}/mcp/agent/mcp_client.tcl";
          environment.etc."agent/e2e_test.tcl".source = "${self}/mcp/agent/e2e_test.tcl";

          # ─── Test Runner Script ──────────────────────────────────────────
          environment.etc."agent/run-tests.sh" = {
            mode = "0755";
            text = ''
              #!/bin/sh
              cd /etc/agent
              exec ${pkgs.tcl-9_0}/bin/tclsh9.0 e2e_test.tcl "$@"
            '';
          };

          # ─── Debug Mode: Auto-run Tests ──────────────────────────────────
          systemd.services.agent-test = lib.mkIf debugMode {
            description = "MCP Agent E2E Tests";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];

            # Wait for MCP server to be ready before running tests
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do ${pkgs.curl}/bin/curl -sf http://${network.mcpVmIp}:3000/health && exit 0; sleep 2; done; exit 1'";
              ExecStart = "/etc/agent/run-tests.sh --mcp-host ${network.mcpVmIp} --target-host ${network.targetVmIp}";
              StandardOutput = "journal+console";
              StandardError = "journal+console";
            };
          };

          # ─── MOTD ────────────────────────────────────────────────────────
          environment.etc."motd".text = ''
            ╔═══════════════════════════════════════════════════════════════╗
            ║  Agent-VM: TCL MCP Test Agent                                 ║
            ${
              if debugMode then
                ''
                  ║  Mode: DEBUG - Password auth enabled                          ║
                  ║  User: testuser / Password: ${users.testuser.password}                       ║
                ''
              else
                ''
                  ║  Mode: Normal - Key auth only                                 ║
                ''
            }║                                                               ║
            ║  Run tests:                                                   ║
            ║    /etc/agent/run-tests.sh                                    ║
            ║    /etc/agent/run-tests.sh --debug                            ║
            ║                                                               ║
            ║  Network:                                                     ║
            ║    MCP:    http://${network.mcpVmIp}:3000                          ║
            ║    Target: ${network.targetVmIp}:2222                              ║
            ╚═══════════════════════════════════════════════════════════════╝
          '';
        }
      )
    ];
  };

in
nixos.config.microvm.declaredRunner
