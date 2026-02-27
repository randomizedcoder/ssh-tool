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

        # Import library helpers
        nixLib = import ./nix/lib { inherit pkgs lib; };
        vmVariants = nixLib.vmVariants;
        appsLib = nixLib.apps;

        # Base arguments for VM variant generation
        vmBaseArgs = {
          inherit
            pkgs
            microvm
            nixpkgs
            system
            ;
        };
      in
      {
        # Formatter for nix files
        formatter = pkgs.nixfmt-tree;

        # Development shell
        devShells.default = import ./nix/shell.nix { inherit pkgs; };

        # MicroVM packages (Linux only)
        packages = lib.optionalAttrs pkgs.stdenv.isLinux (
          # Generate all VM variants using the helper
          (vmVariants.mkVmVariants vmBaseArgs {
            name = "agent";
            vmModule = ./nix/agent-vm.nix;
            extraArgs = { inherit self; };
          })
          // (vmVariants.mkVmVariants vmBaseArgs {
            name = "mcp";
            vmModule = ./nix/mcp-vm.nix;
            extraArgs = { inherit self; };
          })
          // (vmVariants.mkVmVariants vmBaseArgs {
            name = "ssh-target";
            vmModule = ./nix/ssh-target-vm.nix;
          })
        );

        # Apps (Linux only)
        apps = lib.optionalAttrs pkgs.stdenv.isLinux (
          let
            # Import all script modules
            networkScripts = import ./nix/network-setup.nix { inherit pkgs; };
            vmScripts = import ./nix/vm-scripts.nix { inherit pkgs; };
            testScripts = import ./nix/tests/e2e-test.nix { inherit pkgs lib; };
            loadtestScripts = import ./nix/tests/loadtest.nix { inherit pkgs lib; };
            networkTestScripts = import ./nix/tests/network-commands-test.nix { inherit pkgs lib; };
            parallelTestScripts = import ./nix/tests/parallel-test.nix { inherit pkgs lib; };
          in
          # VM management apps
          (appsLib.mkApps {
            # Status checks
            ssh-vm-check = vmScripts.check;
            ssh-vm-status = vmScripts.status;
            # Start VMs
            ssh-vm-start-all = vmScripts.startAll;
            ssh-vm-start-target = vmScripts.startTarget;
            ssh-vm-start-mcp = vmScripts.startMcp;
            ssh-vm-start-agent = vmScripts.startAgent;
            # Stop VMs (graceful)
            ssh-vm-stop = vmScripts.stop;
            ssh-vm-stop-target = vmScripts.stopTarget;
            ssh-vm-stop-mcp = vmScripts.stopMcp;
            ssh-vm-stop-agent = vmScripts.stopAgent;
            # Stop VMs (force)
            ssh-vm-stop-force = vmScripts.stopForce;
            # Restart VMs
            ssh-vm-restart-all = vmScripts.restartAll;
            ssh-vm-restart-mcp = vmScripts.restartMcp;
            # SSH access
            ssh-vm-ssh-agent = vmScripts.sshAgent;
            ssh-vm-ssh-mcp = vmScripts.sshMcp;
            ssh-vm-ssh-target = vmScripts.sshTarget;
            # Logs
            ssh-vm-logs = vmScripts.logs;
          })
          # Network setup apps
          // (appsLib.mkApps {
            ssh-network-setup = networkScripts.setup;
            ssh-network-teardown = networkScripts.teardown;
          })
          # E2E test apps
          // (appsLib.mkApps {
            ssh-test-e2e = testScripts.e2e;
            ssh-test-auth = testScripts.authTests;
            ssh-test-netem = testScripts.netemTests;
            ssh-test-stability = testScripts.stabilityTests;
            ssh-test-security = testScripts.security;
            ssh-test-all = testScripts.all;
          })
          # Load test apps
          // (appsLib.mkApps {
            ssh-loadtest-quick = loadtestScripts.quick;
            ssh-loadtest = loadtestScripts.standard;
            ssh-loadtest-full = loadtestScripts.full;
            ssh-loadtest-connection-rate = loadtestScripts.connectionRate;
            ssh-loadtest-throughput = loadtestScripts.commandThroughput;
            ssh-loadtest-latency = loadtestScripts.latencyTest;
            ssh-loadtest-list = loadtestScripts.listScenarios;
            ssh-loadtest-metrics = loadtestScripts.scrapeMetrics;
          })
          # Network command test apps
          // (appsLib.mkApps {
            ssh-test-network-inspection = networkTestScripts.networkInspection;
            ssh-test-network-connectivity = networkTestScripts.connectivityTests;
            ssh-test-network-security = networkTestScripts.securityBlockedTests;
            ssh-test-network-all = networkTestScripts.all;
          })
          # Parallel test apps
          // (appsLib.mkApps {
            ssh-test-parallel = parallelTestScripts.parallel;
            ssh-test-parallel-stress = parallelTestScripts.stress;
          })
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
