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
  network = import ./constants/network.nix;
  ports = import ./constants/ports.nix;
  users = import ./constants/users.nix;

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
            mem = users.vmResources.agent.memoryMB;
            vcpu = users.vmResources.agent.vcpus;

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
                    id = network.tapAgent;
                    mac = network.agentVmMac;
                  }
                ]
              else
                [
                  {
                    type = "user";
                    id = "eth0";
                    mac = network.agentVmMac;
                  }
                ];

            forwardPorts = lib.optionals (!useTap) [
              {
                from = "host";
                host.port = ports.sshForwardAgent;
                guest.port = 22;
              }
            ];

            # Serial console configuration for debugging
            # Connect with: nc localhost 4100 (slow) or nc localhost 4101 (fast)
            qemu = {
              serialConsole = false; # We configure our own
              extraArgs = [
                "-name"
                "agent-vm,process=agent-vm"
                # Slow serial console (ttyS0) - works early in boot
                "-serial"
                "tcp:127.0.0.1:${toString ports.console.agentSerial},server,nowait"
                # Fast virtio console (hvc0)
                "-device"
                "virtio-serial-pci"
                "-chardev"
                "socket,id=virtcon,port=${toString ports.console.agentVirtio},host=127.0.0.1,server=on,wait=off"
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
          networking.hostName = "agent-vm";
          networking.firewall.allowedTCPPorts = [ 22 ];

          # Use systemd-networkd for reliable interface matching
          # The TAP interface appears as enp0s3 (PCI naming) not eth0
          systemd.network = lib.mkIf useTap {
            enable = true;
            networks."10-lan" = {
              matchConfig.Driver = "virtio_net";
              address = [ "${network.agentVmIp}/24" ];
              gateway = [ network.gateway ];
            };
          };
          networking.useNetworkd = lib.mkIf useTap true;

          # ─── SSH Server (for debug access) ─────────────────────────────
          services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = debugMode;
              PermitRootLogin = if debugMode then "yes" else "prohibit-password";
            };
          };

          # ─── Packages ──────────────────────────────────────────────────
          environment.systemPackages = with pkgs; [
            tcl-9_0
            curl
            jq
            netcat-gnu
          ];

          # ─── Test User ─────────────────────────────────────────────────
          users.users.testuser = {
            isNormalUser = true;
            password = users.testuser.password;
            extraGroups = [ "wheel" ];
          };

          users.users.root.password = lib.mkIf debugMode users.root.password;

          security.sudo.wheelNeedsPassword = false;

          # ─── Agent Source ──────────────────────────────────────────────
          # Copy agent scripts to /opt/agent
          environment.etc."agent/http_client.tcl".source = "${self}/mcp/agent/http_client.tcl";
          environment.etc."agent/json.tcl".source = "${self}/mcp/agent/json.tcl";
          environment.etc."agent/mcp_client.tcl".source = "${self}/mcp/agent/mcp_client.tcl";
          environment.etc."agent/e2e_test.tcl".source = "${self}/mcp/agent/e2e_test.tcl";

          # ─── Test Runner Script ────────────────────────────────────────
          environment.etc."agent/run-tests.sh" = {
            mode = "0755";
            text = ''
              #!/bin/sh
              cd /etc/agent
              exec ${pkgs.tcl-9_0}/bin/tclsh9.0 e2e_test.tcl "$@"
            '';
          };

          # ─── Debug Mode: Auto-run Tests ────────────────────────────────
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

          # ─── MOTD ──────────────────────────────────────────────────────
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
