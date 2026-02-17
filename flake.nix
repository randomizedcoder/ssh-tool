{
  description = "SSH Automation Tool with MCP Server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      microvm,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
        constants = import ./nix/constants;
      in
      {
        # Formatter for nix files
        formatter = pkgs.nixfmt-tree;

        # Development shell
        devShells.default = import ./nix/shell.nix { inherit pkgs; };

        # MicroVM packages (Linux only)
        packages = lib.optionalAttrs pkgs.stdenv.isLinux {
          # Agent VM variants (TCL test client)
          agent-vm = import ./nix/agent-vm.nix {
            inherit
              self
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "user";
            debugMode = false;
          };
          agent-vm-debug = import ./nix/agent-vm.nix {
            inherit
              self
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "user";
            debugMode = true;
          };
          agent-vm-tap = import ./nix/agent-vm.nix {
            inherit
              self
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "tap";
            debugMode = false;
          };
          agent-vm-tap-debug = import ./nix/agent-vm.nix {
            inherit
              self
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "tap";
            debugMode = true;
          };

          # MCP Server VM variants
          mcp-vm = import ./nix/mcp-vm.nix {
            inherit
              self
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "user";
            debugMode = false;
          };
          mcp-vm-debug = import ./nix/mcp-vm.nix {
            inherit
              self
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "user";
            debugMode = true;
          };
          mcp-vm-tap = import ./nix/mcp-vm.nix {
            inherit
              self
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "tap";
            debugMode = false;
          };
          mcp-vm-tap-debug = import ./nix/mcp-vm.nix {
            inherit
              self
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "tap";
            debugMode = true;
          };

          # SSH Target VM variants
          ssh-target-vm = import ./nix/ssh-target-vm.nix {
            inherit
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "user";
            debugMode = false;
          };
          ssh-target-vm-debug = import ./nix/ssh-target-vm.nix {
            inherit
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "user";
            debugMode = true;
          };
          ssh-target-vm-tap = import ./nix/ssh-target-vm.nix {
            inherit
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "tap";
            debugMode = false;
          };
          ssh-target-vm-tap-debug = import ./nix/ssh-target-vm.nix {
            inherit
              pkgs
              lib
              microvm
              nixpkgs
              system
              ;
            networking = "tap";
            debugMode = true;
          };
        };

        # Apps (Linux only)
        apps = lib.optionalAttrs pkgs.stdenv.isLinux (
          let
            networkScripts = import ./nix/network-setup.nix { inherit pkgs; };
            vmScripts = import ./nix/vm-scripts.nix { inherit pkgs; };
            testScripts = import ./nix/tests/e2e-test.nix { inherit pkgs lib; };
            loadtestScripts = import ./nix/tests/loadtest.nix { inherit pkgs lib; };
            networkTestScripts = import ./nix/tests/network-commands-test.nix { inherit pkgs lib; };
          in
          {
            # VM management
            ssh-vm-check = {
              type = "app";
              program = "${vmScripts.check}/bin/ssh-vm-check";
            };
            ssh-vm-stop = {
              type = "app";
              program = "${vmScripts.stop}/bin/ssh-vm-stop";
            };
            ssh-vm-ssh-agent = {
              type = "app";
              program = "${vmScripts.sshAgent}/bin/ssh-vm-ssh-agent";
            };
            ssh-vm-ssh-mcp = {
              type = "app";
              program = "${vmScripts.sshMcp}/bin/ssh-vm-ssh-mcp";
            };
            ssh-vm-ssh-target = {
              type = "app";
              program = "${vmScripts.sshTarget}/bin/ssh-vm-ssh-target";
            };

            # Network setup (for TAP mode)
            ssh-network-setup = {
              type = "app";
              program = "${networkScripts.setup}/bin/ssh-network-setup";
            };
            ssh-network-teardown = {
              type = "app";
              program = "${networkScripts.teardown}/bin/ssh-network-teardown";
            };

            # Test runners
            ssh-test-e2e = {
              type = "app";
              program = "${testScripts.e2e}/bin/ssh-test-e2e";
            };
            ssh-test-auth = {
              type = "app";
              program = "${testScripts.authTests}/bin/ssh-test-auth";
            };
            ssh-test-netem = {
              type = "app";
              program = "${testScripts.netemTests}/bin/ssh-test-netem";
            };
            ssh-test-stability = {
              type = "app";
              program = "${testScripts.stabilityTests}/bin/ssh-test-stability";
            };
            ssh-test-security = {
              type = "app";
              program = "${testScripts.security}/bin/ssh-test-security";
            };
            ssh-test-all = {
              type = "app";
              program = "${testScripts.all}/bin/ssh-test-all";
            };

            # Load test runners
            ssh-loadtest-quick = {
              type = "app";
              program = "${loadtestScripts.quick}/bin/ssh-loadtest-quick";
            };
            ssh-loadtest = {
              type = "app";
              program = "${loadtestScripts.standard}/bin/ssh-loadtest";
            };
            ssh-loadtest-full = {
              type = "app";
              program = "${loadtestScripts.full}/bin/ssh-loadtest-full";
            };
            ssh-loadtest-connection-rate = {
              type = "app";
              program = "${loadtestScripts.connectionRate}/bin/ssh-loadtest-connection-rate";
            };
            ssh-loadtest-throughput = {
              type = "app";
              program = "${loadtestScripts.commandThroughput}/bin/ssh-loadtest-throughput";
            };
            ssh-loadtest-latency = {
              type = "app";
              program = "${loadtestScripts.latencyTest}/bin/ssh-loadtest-latency";
            };
            ssh-loadtest-list = {
              type = "app";
              program = "${loadtestScripts.listScenarios}/bin/ssh-loadtest-list";
            };
            ssh-loadtest-metrics = {
              type = "app";
              program = "${loadtestScripts.scrapeMetrics}/bin/ssh-loadtest-metrics";
            };

            # Network command test runners
            # Reference: DESIGN_NETWORK_COMMANDS.md
            ssh-test-network-inspection = {
              type = "app";
              program = "${networkTestScripts.networkInspection}/bin/ssh-test-network-inspection";
            };
            ssh-test-network-connectivity = {
              type = "app";
              program = "${networkTestScripts.connectivityTests}/bin/ssh-test-connectivity";
            };
            ssh-test-network-security = {
              type = "app";
              program = "${networkTestScripts.securityBlockedTests}/bin/ssh-test-network-security";
            };
            ssh-test-network-all = {
              type = "app";
              program = "${networkTestScripts.all}/bin/ssh-test-network-all";
            };
          }
        );

        # NixOS tests (automated VM orchestration for CI)
        checks = lib.optionalAttrs pkgs.stdenv.isLinux {
          integration = import ./nix/nixos-test.nix {
            inherit
              self
              pkgs
              lib
              nixpkgs
              system
              ;
          };
        };
      }
    );
}
