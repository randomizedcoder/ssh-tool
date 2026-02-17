# nix/nixos-test.nix
#
# NixOS test framework integration for automated CI testing.
# Creates three VMs (Agent + MCP server + SSH target) and runs integration tests.
#
# Usage:
#   nix build .#checks.x86_64-linux.integration
#   nix flake check
#
{
  self,
  pkgs,
  lib,
  nixpkgs,
  system,
}:
let
  constants = import ./constants;
  network = constants.network;
  ports = constants.ports;
  users = constants.users;
  sshd = constants.sshd;
  netem = constants.netem;
  timeouts = constants.timeouts;

  # Expect with Tcl 9.0 support
  # TODO: Replace with pkgs.tclPackages_9_0.expect after PR #490930 merges
  expect-tcl9 = pkgs.callPackage ./expect-tcl9 { };

in
pkgs.testers.nixosTest {
  name = "ssh-tool-integration";

  nodes = {
    # ─── Agent Node (TCL Test Client) ───────────────────────────────
    agent =
      { config, pkgs, ... }:
      {
        # Network
        networking.firewall.allowedTCPPorts = [ 22 ];

        # SSH Server for debug access
        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = true;
            PermitRootLogin = "yes";
          };
        };

        # Test user
        users.users.testuser = {
          isNormalUser = true;
          password = users.testuser.password;
          extraGroups = [ "wheel" ];
        };
        users.users.root.hashedPassword = users.root.hashedPassword;
        security.sudo.wheelNeedsPassword = false;

        # Packages (tcl-9_0 for Tcl 9.0+ support required by agent scripts)
        environment.systemPackages = with pkgs; [
          tcl-9_0
          curl
          jq
          netcat-gnu
        ];

        # Agent source files
        environment.etc."agent/http_client.tcl".source = "${self}/mcp/agent/http_client.tcl";
        environment.etc."agent/json.tcl".source = "${self}/mcp/agent/json.tcl";
        environment.etc."agent/mcp_client.tcl".source = "${self}/mcp/agent/mcp_client.tcl";
        environment.etc."agent/e2e_test.tcl".source = "${self}/mcp/agent/e2e_test.tcl";
      };

    # ─── MCP Server Node ────────────────────────────────────────────
    mcp =
      { config, pkgs, ... }:
      {
        # Network
        networking.firewall.allowedTCPPorts = [
          22
          3000
        ];

        # SSH Server for testing
        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = true;
            PermitRootLogin = "yes";
          };
        };

        # Test user
        users.users.testuser = {
          isNormalUser = true;
          password = users.testuser.password;
          extraGroups = [ "wheel" ];
        };
        users.users.root.hashedPassword = users.root.hashedPassword;
        security.sudo.wheelNeedsPassword = false;

        # Packages (expect-tcl9 for Tcl 9.0 support)
        environment.systemPackages = with pkgs; [
          expect-tcl9
          tcl-9_0
          curl
          jq
          openssh
          sshpass
        ];

        # MCP Server Service
        systemd.services.mcp-server = {
          description = "MCP SSH Automation Server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${expect-tcl9}/bin/expect ${self}/mcp/server.tcl --port 3000 --bind 0.0.0.0";
            Restart = "always";
            WorkingDirectory = "${self}";
          };
        };
      };

    # ─── SSH Target Node ────────────────────────────────────────────
    target =
      { config, pkgs, ... }:
      {
        # Ensure passwords are set at build time (not mutable)
        users.mutableUsers = false;

        # Network
        networking.firewall.allowedTCPPorts =
          (lib.mapAttrsToList (n: c: c.port) sshd) ++ (lib.mapAttrsToList (n: c: c.degradedPort) netem);

        # Disable default sshd
        services.openssh.enable = false;

        # SSHD privilege separation user (required for sshd)
        users.users.sshd = {
          isSystemUser = true;
          group = "sshd";
          description = "SSH privilege separation user";
        };
        users.groups.sshd = { };

        # PAM configuration for sshd
        security.pam.services.sshd = {
          startSession = true;
          showMotd = true;
          unixAuth = true;
          rootOK = true;
        };

        # Enable zsh for zshuser
        programs.zsh.enable = true;

        # Packages
        environment.systemPackages = with pkgs; [
          coreutils
          procps
          iproute2
          util-linux
          openssh
          zsh
          dash
        ];

        # Test Users
        users.users.testuser = {
          isNormalUser = true;
          password = users.testuser.password;
          shell = pkgs.bash;
          extraGroups = [ "wheel" ];
        };

        users.users.fancyuser = {
          isNormalUser = true;
          password = users.fancyuser.password;
          shell = pkgs.bash;
          extraGroups = [ "wheel" ];
        };

        users.users.zshuser = {
          isNormalUser = true;
          password = users.zshuser.password;
          shell = pkgs.zsh;
          extraGroups = [ "wheel" ];
        };

        users.users.dashuser = {
          isNormalUser = true;
          password = users.dashuser.password;
          shell = pkgs.dash;
          extraGroups = [ "wheel" ];
        };

        users.users.slowuser = {
          isNormalUser = true;
          password = users.slowuser.password;
          shell = pkgs.bash;
          extraGroups = [ "wheel" ];
        };

        users.users.root.hashedPassword = users.root.hashedPassword;
        security.sudo.wheelNeedsPassword = false;

        # Generate sshd configs and test files
        environment.etc =
          (lib.mapAttrs' (
            name: cfg:
            lib.nameValuePair "ssh/sshd_config_${name}" {
              text = ''
                Port ${toString cfg.port}
                HostKey /etc/ssh/ssh_host_ed25519_key
                HostKey /etc/ssh/ssh_host_rsa_key

                PasswordAuthentication ${if cfg.passwordAuth then "yes" else "no"}
                PubkeyAuthentication ${if cfg.pubkeyAuth then "yes" else "no"}
                PermitRootLogin ${cfg.permitRootLogin}

                SyslogFacility AUTH
                LogLevel INFO
                PermitEmptyPasswords no
                ChallengeResponseAuthentication no
                UsePAM yes

                Subsystem sftp ${pkgs.openssh}/libexec/sftp-server
              '';
            }
          ) sshd)
          // {
            # Test files
            "test-file.txt".text = ''
              This is a test file for ssh_cat_file testing.
              Line 2 of the test file.
              Line 3 of the test file.
            '';
            "large-test-file.txt".text = lib.concatStrings (
              lib.genList (i: "Line ${toString i}: Test content for buffer testing.\n") 1000
            );
          };

        # SSHD Services (merged with keygen service)
        systemd.services =
          (lib.mapAttrs' (
            name: cfg:
            lib.nameValuePair "sshd-${name}" {
              description = "SSH Daemon - ${name}";
              wantedBy = [ "multi-user.target" ];
              after = [
                "network.target"
                "sshd-keygen.service"
              ];
              wants = [ "sshd-keygen.service" ];
              serviceConfig = {
                ExecStart = "${pkgs.openssh}/bin/sshd -D -f /etc/ssh/sshd_config_${name}";
                Restart = if cfg ? restartInterval then "always" else "on-failure";
              }
              // (lib.optionalAttrs (cfg ? restartInterval) {
                RestartSec = toString cfg.restartInterval;
              });
            }
          ) sshd)
          // {
            # SSH Key Generation Service
            sshd-keygen = {
              description = "Generate SSH host keys";
              wantedBy = [ "multi-user.target" ];
              before = lib.mapAttrsToList (name: cfg: "sshd-${name}.service") sshd;
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "ssh-keygen" ''
                  if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
                    ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
                  fi
                  if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
                    ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
                  fi
                '';
              };
            };
          };
      };
  };

  # ─── Test Script (Python) ─────────────────────────────────────────
  testScript = ''
    start_all()

    # Wait for SSH target services
    with subtest("Wait for SSH target services"):
        target.wait_for_unit("sshd-standard.service")
        target.wait_for_unit("sshd-keyonly.service")
        target.wait_for_unit("sshd-fancyprompt.service")
        target.wait_for_unit("sshd-rootlogin.service")
        target.wait_for_open_port(${toString sshd.standard.port})

    # Wait for MCP server
    with subtest("Wait for MCP server"):
        mcp.wait_for_unit("mcp-server.service")
        mcp.wait_for_open_port(3000)

    # Wait for agent
    with subtest("Wait for agent"):
        agent.wait_for_unit("multi-user.target")

    # Use hostnames for inter-VM communication (NixOS tests set up /etc/hosts)
    mcp_ip = "mcp"
    target_ip = "target"
    print(f"MCP hostname: {mcp_ip}, Target hostname: {target_ip}")

    # Test MCP health endpoint
    with subtest("MCP health check"):
        result = mcp.succeed("curl -sf http://localhost:3000/health || echo 'HEALTH_FAILED'")
        assert "HEALTH_FAILED" not in result, f"MCP health check failed: {result}"

    # Test MCP health from agent
    with subtest("Agent can reach MCP health"):
        result = agent.succeed(f"curl -sf http://{mcp_ip}:3000/health || echo 'HEALTH_FAILED'")
        assert "HEALTH_FAILED" not in result, f"Agent cannot reach MCP: {result}"

    # Test basic SSH from MCP to target
    with subtest("SSH from MCP to target"):
        mcp.succeed(
            f"sshpass -p '${users.testuser.password}' ssh -o StrictHostKeyChecking=no "
            f"-o UserKnownHostsFile=/dev/null -p ${toString sshd.standard.port} "
            f"testuser@{target_ip} hostname"
        )

    # ─── Agent E2E Tests ────────────────────────────────────────────
    with subtest("Agent E2E test - MCP initialize"):
        # Run TCL agent tests from agent VM
        result = agent.succeed(
            f"cd /etc/agent && tclsh e2e_test.tcl "
            f"--mcp-host {mcp_ip} --target-host {target_ip} "
            f"--target-port ${toString sshd.standard.port} 2>&1 || true"
        )
        print(f"Agent E2E output:\n{result}")
        # Check for test results
        assert "PASS" in result, "Agent E2E tests should have passing tests"

    # Test password rejection on keyonly port
    with subtest("Keyonly port rejects password"):
        exit_code = mcp.execute(
            f"sshpass -p '${users.testuser.password}' ssh -o StrictHostKeyChecking=no "
            f"-o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "
            f"-p ${toString sshd.keyonly.port} testuser@{target_ip} hostname"
        )[0]
        assert exit_code != 0, "Keyonly port should reject password auth"

    # Test root login on rootlogin port
    with subtest("Root login on rootlogin port"):
        result = mcp.succeed(
            f"sshpass -p '${users.root.password}' ssh -o StrictHostKeyChecking=no "
            f"-o UserKnownHostsFile=/dev/null -p ${toString sshd.rootlogin.port} "
            f"root@{target_ip} id -u"
        )
        assert "0" in result, f"Root should have uid 0, got: {result}"

    # Test different users
    with subtest("Different user shells"):
        result = mcp.succeed(
            f"sshpass -p '${users.zshuser.password}' ssh -o StrictHostKeyChecking=no "
            f"-o UserKnownHostsFile=/dev/null -p ${toString sshd.standard.port} "
            f"zshuser@{target_ip} 'echo $SHELL'"
        )
        assert "zsh" in result, f"zshuser should have zsh shell, got: {result}"

    # Test file reading
    with subtest("Read test file"):
        result = mcp.succeed(
            f"sshpass -p '${users.testuser.password}' ssh -o StrictHostKeyChecking=no "
            f"-o UserKnownHostsFile=/dev/null -p ${toString sshd.standard.port} "
            f"testuser@{target_ip} 'cat /etc/test-file.txt'"
        )
        assert "test file" in result, f"Test file should contain 'test file', got: {result}"

    # Test large file (buffer handling)
    with subtest("Read large test file"):
        result = mcp.succeed(
            f"sshpass -p '${users.testuser.password}' ssh -o StrictHostKeyChecking=no "
            f"-o UserKnownHostsFile=/dev/null -p ${toString sshd.standard.port} "
            f"testuser@{target_ip} 'wc -l < /etc/large-test-file.txt'"
        )
        line_count = int(result.strip())
        assert line_count >= 100, f"Large file should have >= 100 lines, got: {line_count}"
  '';
}
