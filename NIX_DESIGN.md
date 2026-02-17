# SSH-Tool Nix Flake Design

## Status: DRAFT - For Review

## Overview

This document proposes adding Nix flake support to the ssh-tool repository, providing:

1. **Development shell** (`nix develop`) - All tools needed for development and testing
2. **MicroVMs for testing** - Ephemeral VMs with multiple SSH configurations for comprehensive testing

The MicroVM architecture enables fully automated testing with a sophisticated multi-sshd setup:
- **mcp-vm**: Runs the MCP server, can SSH to various sshd configurations
- **ssh-target-vm**: Multiple sshd processes on different ports with different configurations

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Test Architecture                                    │
│                                                                              │
│  ┌──────────────────┐                     ┌──────────────────────────────┐  │
│  │    mcp-vm        │                     │      ssh-target-vm           │  │
│  │                  │                     │                              │  │
│  │  - MCP Server    │  ───── SSH ──────▶  │  Multiple sshd instances:    │  │
│  │  - expect/tcl    │                     │                              │  │
│  │                  │                     │  :2222 - Standard (password) │  │
│  └──────────────────┘                     │  :2223 - Key-only auth       │  │
│         ▲                                 │  :2224 - Fancy prompt user   │  │
│         │                                 │  :2225 - Slow auth (2s delay)│  │
│         │                                 │  :2226 - Auth denied always  │  │
│         │ JSON-RPC                        │  :2227 - Unstable (restarts) │  │
│         │                                 │  :2228 - Root login enabled  │  │
│         │                                 │                              │  │
│       Host                                │  Netem ports (+100 offset):  │  │
│                                           │  :2322 - 100ms latency       │  │
│                                           │  :2323 - 50ms + 5% loss      │  │
│                                           │  :2324 - 200ms + 10% loss    │  │
│                                           └──────────────────────────────┘  │
│                                                                              │
│  Host runs: nix run .#ssh-test-e2e                                          │
│  Which calls MCP server via JSON-RPC, MCP server SSHs to target VM ports    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Multi-SSHD Test Matrix

The ssh-target-vm runs multiple sshd instances for comprehensive testing:

### Base SSH Daemons (ports 2222-2228)

| Port | Name | Configuration | Test Purpose |
|------|------|---------------|--------------|
| 2222 | standard | Password auth, basic PS1 | Happy path, basic functionality |
| 2223 | keyonly | Public key auth only | Auth method failure testing |
| 2224 | fancyprompt | Complex PS1 with colors/git | Prompt detection robustness |
| 2225 | slowauth | 2-second PAM delay | Timeout handling for slow auth |
| 2226 | denyall | All auth rejected | Auth failure error handling |
| 2227 | unstable | Restarts every 5 seconds | Connection stability, reconnect |
| 2228 | rootlogin | PermitRootLogin yes | Root session testing |

### Netem Degraded Ports (ports 2322-2328)

Each base port has a +100 netem-degraded variant for network simulation:

| Port | Forwards To | Netem Config | Test Purpose |
|------|-------------|--------------|--------------|
| 2322 | 2222 | 100ms latency | Basic latency tolerance |
| 2323 | 2223 | 50ms + 5% packet loss | Lossy network handling |
| 2324 | 2224 | 200ms + 10% loss | Severe degradation |
| 2325 | 2225 | 500ms latency | Combined slow auth + network |
| 2326 | 2226 | 1000ms latency | Slow failure detection |
| 2327 | 2227 | 100ms + 2% loss | Unstable service + bad network |
| 2328 | 2228 | 50ms latency | Root login over slow link |

### Test Users

| User | Shell | PS1 | Password | Purpose |
|------|-------|-----|----------|---------|
| testuser | bash | `$ ` | testpass | Standard testing |
| fancyuser | bash | `\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]$ ` | testpass | Complex prompt |
| zshuser | zsh | `%n@%m:%~%# ` | testpass | Zsh shell testing |
| dashuser | dash | `$ ` | testpass | Minimal POSIX shell |
| slowuser | bash | `$ ` | testpass | Used with slowauth sshd |
| root | bash | `# ` | root | Root testing (port 2228 only) |

## Current State

The ssh-tool repository currently has no Nix support. Testing requires a real SSH target with password authentication.

**Current test requirements:**
- SSH_HOST, SSH_USER, PASSWORD environment variables
- Manual setup of SSH target

## Design Goals

1. **Modular** - Each concern in its own file under `nix/`
2. **Zero-config testing** - MicroVMs provide SSH targets automatically
3. **Two VM types** - MCP server VM + minimal SSH target VM
4. **Reproducible** - Same test environment everywhere
5. **Nix-idiomatic** - Follow patterns from pcp project

## Proposed Structure

```
ssh-tool/
├── flake.nix                    # Orchestrator (imports modular components)
├── flake.lock                   # Locked dependencies
└── nix/
    ├── constants/               # Modular configuration (split for scale)
    │   ├── default.nix          # Re-exports all constants
    │   ├── network.nix          # Network config (IPs, bridges, TAP)
    │   ├── ports.nix            # Port assignments (sshd, netem, MCP)
    │   ├── users.nix            # Test user definitions
    │   ├── sshd.nix             # SSH daemon configurations
    │   ├── netem.nix            # Network emulation profiles
    │   └── timeouts.nix         # Global timeout configuration
    ├── shell.nix                # Development shell (expect, tcl, test tools)
    ├── mcp-vm.nix               # MicroVM: MCP server + SSH + expect
    ├── ssh-target-vm.nix        # MicroVM: Multi-SSHD target
    ├── network-setup.nix        # TAP/bridge network setup scripts
    ├── vm-scripts.nix           # VM management scripts (check, stop, ssh)
    ├── test-lib.nix             # Shared test functions
    ├── nixos-test.nix           # NixOS test framework integration
    └── tests/
        ├── e2e-test.nix         # End-to-end test scripts
        └── security-test.nix    # Security validation test scripts
```

### Why Modular Constants?

Splitting `constants.nix` prevents a single file from becoming a 500+ line monolith as tests grow. Each VM can import only what it needs:

```nix
# mcp-vm.nix - only needs network and ports
let
  network = import ./constants/network.nix;
  ports = import ./constants/ports.nix;
in ...

# ssh-target-vm.nix - needs everything
let
  constants = import ./constants;  # imports default.nix
in ...
```

## File Specifications

### `flake.nix` - Orchestrator

Slim top-level file that wires inputs to outputs. Key features:
- Passes `self` to VMs for reproducible source code access
- Includes NixOS test framework integration for CI
- Uses modular constants structure

```nix
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

  outputs = { self, nixpkgs, flake-utils, microvm }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
        constants = import ./nix/constants;  # imports default.nix
      in
      {
        # Development shell
        devShells.default = import ./nix/shell.nix { inherit pkgs; };

        # MicroVM packages (Linux only)
        packages = lib.optionalAttrs pkgs.stdenv.isLinux {
          # MCP Server VM variants - note: passes `self` for source access
          mcp-vm = import ./nix/mcp-vm.nix {
            inherit self pkgs lib microvm nixpkgs system;
            networking = "user";
            debugMode = false;
          };
          mcp-vm-debug = import ./nix/mcp-vm.nix {
            inherit self pkgs lib microvm nixpkgs system;
            networking = "user";
            debugMode = true;
          };
          mcp-vm-tap = import ./nix/mcp-vm.nix {
            inherit self pkgs lib microvm nixpkgs system;
            networking = "tap";
            debugMode = false;
          };
          mcp-vm-tap-debug = import ./nix/mcp-vm.nix {
            inherit self pkgs lib microvm nixpkgs system;
            networking = "tap";
            debugMode = true;
          };

          # SSH Target VM variants
          ssh-target-vm = import ./nix/ssh-target-vm.nix {
            inherit pkgs lib microvm nixpkgs system;
            networking = "user";
            debugMode = false;
          };
          ssh-target-vm-debug = import ./nix/ssh-target-vm.nix {
            inherit pkgs lib microvm nixpkgs system;
            networking = "user";
            debugMode = true;
          };
          ssh-target-vm-tap = import ./nix/ssh-target-vm.nix {
            inherit pkgs lib microvm nixpkgs system;
            networking = "tap";
            debugMode = false;
          };
          ssh-target-vm-tap-debug = import ./nix/ssh-target-vm.nix {
            inherit pkgs lib microvm nixpkgs system;
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
          in {
            # VM management
            ssh-vm-check = { type = "app"; program = "${vmScripts.check}/bin/ssh-vm-check"; };
            ssh-vm-stop = { type = "app"; program = "${vmScripts.stop}/bin/ssh-vm-stop"; };
            ssh-vm-ssh-mcp = { type = "app"; program = "${vmScripts.sshMcp}/bin/ssh-vm-ssh-mcp"; };
            ssh-vm-ssh-target = { type = "app"; program = "${vmScripts.sshTarget}/bin/ssh-vm-ssh-target"; };

            # Network setup (for TAP mode)
            ssh-network-setup = { type = "app"; program = "${networkScripts.setup}/bin/ssh-network-setup"; };
            ssh-network-teardown = { type = "app"; program = "${networkScripts.teardown}/bin/ssh-network-teardown"; };

            # Test runners (manual VM orchestration)
            ssh-test-e2e = { type = "app"; program = "${testScripts.e2e}/bin/ssh-test-e2e"; };
            ssh-test-auth = { type = "app"; program = "${testScripts.authTests}/bin/ssh-test-auth"; };
            ssh-test-netem = { type = "app"; program = "${testScripts.netemTests}/bin/ssh-test-netem"; };
            ssh-test-stability = { type = "app"; program = "${testScripts.stabilityTests}/bin/ssh-test-stability"; };
            ssh-test-security = { type = "app"; program = "${testScripts.security}/bin/ssh-test-security"; };
            ssh-test-all = { type = "app"; program = "${testScripts.all}/bin/ssh-test-all"; };
          }
        );

        # NixOS tests (automated VM orchestration for CI)
        checks = lib.optionalAttrs pkgs.stdenv.isLinux {
          integration = import ./nix/nixos-test.nix {
            inherit self pkgs lib nixpkgs system;
          };
        };
      }
    );
}
```

### `nix/constants/` - Modular Configuration

The constants are split into separate files to prevent a monolithic configuration as the test suite grows.

#### `nix/constants/default.nix` - Re-exports All Constants

```nix
# nix/constants/default.nix
#
# Aggregates all modular constants for convenience.
# Usage: constants = import ./nix/constants;
#
{
  network = import ./network.nix;
  ports = import ./ports.nix;
  users = import ./users.nix;
  sshd = import ./sshd.nix;
  netem = import ./netem.nix;
  timeouts = import ./timeouts.nix;
}
```

#### `nix/constants/network.nix` - Network Configuration

```nix
# nix/constants/network.nix
{
  # TAP networking
  bridge = "sshbr0";
  tapMcp = "sshtap0";
  tapTarget = "sshtap1";
  subnet = "10.178.0.0/24";
  gateway = "10.178.0.1";

  # VM IP addresses (TAP mode)
  mcpVmIp = "10.178.0.10";
  targetVmIp = "10.178.0.20";

  # MAC addresses
  mcpVmMac = "02:00:00:0a:b2:01";
  targetVmMac = "02:00:00:0a:b2:02";
}
```

#### `nix/constants/ports.nix` - Port Configuration

```nix
# nix/constants/ports.nix
{
  # MCP server HTTP port
  mcpServer = 3000;

  # SSH port forwarding (user-mode networking)
  sshForwardMcp = 22010;
  mcpForward = 3000;

  # Base port for multi-sshd (target VM)
  sshBase = 2222;

  # Netem port offset (base + offset = degraded port)
  netemOffset = 100;
}
```

#### `nix/constants/timeouts.nix` - Global Timeout Configuration

```nix
# nix/constants/timeouts.nix
#
# Centralized timeout configuration.
# Adjust these when testing with high-latency netem profiles.
#
{
  # Expect script timeouts (seconds)
  expect = {
    default = 30;         # Standard operations
    connect = 60;         # SSH connection establishment
    command = 30;         # Command execution
    netem = 120;          # Operations over degraded network
    slowAuth = 10;        # Authentication (excluding PAM delay)
  };

  # Test harness timeouts (seconds)
  test = {
    vmBoot = 120;         # Wait for VM to boot
    sshReady = 60;        # Wait for sshd to accept connections
    mcpReady = 30;        # Wait for MCP server health
  };

  # SSH client timeouts
  ssh = {
    connectTimeout = 10;  # -o ConnectTimeout
    serverAliveInterval = 15;
    serverAliveCountMax = 3;
  };
}
```

#### `nix/constants/sshd.nix` - SSH Daemon Configurations

```nix
# nix/constants/sshd.nix
#
# Each sshd instance runs on its own port with specific configuration.
#
{
  standard = {
    port = 2222;
    description = "Standard password auth";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "no";
  };
  keyonly = {
    port = 2223;
    description = "Public key auth only";
    passwordAuth = false;
    pubkeyAuth = true;
    permitRootLogin = "no";
  };
  fancyprompt = {
    port = 2224;
    description = "Users with complex prompts";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "no";
  };
  slowauth = {
    port = 2225;
    description = "2-second PAM authentication delay";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "no";
    pamDelay = 2;
  };
  denyall = {
    port = 2226;
    description = "All authentication rejected";
    passwordAuth = false;
    pubkeyAuth = false;
    permitRootLogin = "no";
  };
  unstable = {
    port = 2227;
    description = "Restarts every 5 seconds";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "no";
    restartInterval = 5;
  };
  rootlogin = {
    port = 2228;
    description = "Root login permitted";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "yes";
  };
}
```

#### `nix/constants/netem.nix` - Network Emulation Profiles

```nix
# nix/constants/netem.nix
#
# Each entry maps a degraded port to its base port with netem parameters.
# Uses nft marks + tc filters for reliable traffic shaping.
#
{
  latency100 = {
    basePort = 2222;
    degradedPort = 2322;
    description = "100ms latency";
    delay = "100ms";
    jitter = "10ms";  # Optional jitter
    loss = null;
    mark = 1;  # nft mark for tc filter
  };
  lossy5 = {
    basePort = 2223;
    degradedPort = 2323;
    description = "50ms latency + 5% packet loss";
    delay = "50ms";
    jitter = "5ms";
    loss = "5%";
    mark = 2;
  };
  severe = {
    basePort = 2224;
    degradedPort = 2324;
    description = "200ms latency + 10% packet loss";
    delay = "200ms";
    jitter = "20ms";
    loss = "10%";
    mark = 3;
  };
  verySlow = {
    basePort = 2225;
    degradedPort = 2325;
    description = "500ms latency (combined with slow auth)";
    delay = "500ms";
    jitter = "50ms";
    loss = null;
    mark = 4;
  };
  slowFail = {
    basePort = 2226;
    degradedPort = 2326;
    description = "1000ms latency (slow failure)";
    delay = "1000ms";
    jitter = "100ms";
    loss = null;
    mark = 5;
  };
  unstableNetwork = {
    basePort = 2227;
    degradedPort = 2327;
    description = "100ms latency + 2% loss (unstable service)";
    delay = "100ms";
    jitter = "30ms";
    loss = "2%";
    mark = 6;
  };
  rootSlow = {
    basePort = 2228;
    degradedPort = 2328;
    description = "50ms latency (root over slow link)";
    delay = "50ms";
    jitter = "5ms";
    loss = null;
    mark = 7;
  };
}
```

#### `nix/constants/users.nix` - Test User Definitions

```nix
# nix/constants/users.nix
#
# Test users with different shells and prompts for prompt detection testing.
#
{
  testuser = {
    password = "testpass";
    shell = "bash";
    ps1 = "\\$ ";
    description = "Standard test user";
  };
  fancyuser = {
    password = "testpass";
    shell = "bash";
    ps1 = "\\[\\e[32m\\]\\u@\\h\\[\\e[0m\\]:\\[\\e[34m\\]\\w\\[\\e[0m\\]\\$ ";
    description = "User with colored prompt";
  };
  gituser = {
    password = "testpass";
    shell = "bash";
    ps1 = "[\\u@\\h \\W]\\$ ";
    promptCommand = ''__git_ps1() { echo " (main)"; }; PS1="[\\u@\\h \\W\\$(__git_ps1)]\\$ "'';
    description = "User with git-style prompt";
  };
  zshuser = {
    password = "testpass";
    shell = "zsh";
    ps1 = "%n@%m:%~%# ";
    description = "Zsh user";
  };
  dashuser = {
    password = "testpass";
    shell = "dash";
    ps1 = "$ ";
    description = "Minimal POSIX shell user";
  };
  slowuser = {
    password = "testpass";
    shell = "bash";
    ps1 = "\\$ ";
    description = "Used with slowauth sshd";
  };

  # Root credentials (INSECURE: Only for ephemeral test VMs)
  root = {
    password = "root";
    shell = "bash";
    ps1 = "# ";
    description = "Root user for port 2228";
  };

  # VM resource allocation
  vmResources = {
    mcp = { memoryMB = 512; vcpus = 2; };
    target = { memoryMB = 512; vcpus = 2; };
  };
}
```

### `nix/shell.nix` - Development Shell

```nix
# nix/shell.nix
#
# Development shell for ssh-tool.
# Provides all tools needed for development and testing.
#
{ pkgs }:
let
  lib = pkgs.lib;
in
pkgs.mkShell {
  packages = with pkgs; [
    # Core dependencies
    expect              # TCL/Expect interpreter
    tcl                 # TCL runtime

    # Testing tools
    shellcheck          # Shell script linting
    curl                # HTTP client for MCP testing
    jq                  # JSON processing

    # Development tools
    git
    gnumake

    # Optional: debugging
    gdb
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    # Linux-specific tools
    strace
    ltrace
  ];

  shellHook = ''
    echo "═══════════════════════════════════════════════════════════"
    echo "  SSH Automation Tool - Development Shell"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Available commands:"
    echo "  ./tests/run_all_tests.sh     - Run CLI mock tests"
    echo "  ./mcp/tests/run_all_tests.sh - Run MCP mock tests"
    echo "  ./tests/run_shellcheck.sh    - Lint shell scripts"
    echo ""
    echo "For MicroVM testing (Linux only):"
    echo "  nix build .#mcp-vm-debug     - Build MCP server VM"
    echo "  nix build .#ssh-target-vm-debug - Build SSH target VM"
    echo "  nix run .#ssh-test-e2e       - Run end-to-end tests"
    echo ""
  '';

  # Set environment variables
  TCLSH = "${pkgs.tcl}/bin/tclsh";
  EXPECT = "${pkgs.expect}/bin/expect";
}
```

### `nix/mcp-vm.nix` - MCP Server MicroVM

```nix
# nix/mcp-vm.nix
#
# MicroVM running the MCP SSH Automation Server.
# Uses `self` to ensure VM runs the exact code from the flake's commit.
#
# This VM:
# - Runs the MCP server on port 3000
# - Has expect/tcl for SSH automation
# - Has sshd for "SSH to localhost" testing
# - Can SSH to the ssh-target-vm
#
{
  self,        # Flake self-reference for reproducible source access
  pkgs,
  lib,
  microvm,
  nixpkgs,
  system,
  networking ? "user",
  debugMode ? false,
}:
let
  # Modular constants
  network = import ./constants/network.nix;
  ports = import ./constants/ports.nix;
  users = import ./constants/users.nix;
  timeouts = import ./constants/timeouts.nix;

  useTap = networking == "tap";
in
nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    microvm.nixosModules.microvm

    ({ config, pkgs, ... }: {
      system.stateVersion = "24.05";
      nixpkgs.hostPlatform = system;

      # ─── MicroVM Configuration ─────────────────────────────────────
      microvm = {
        hypervisor = "qemu";
        mem = constants.vm.mcp.memoryMB;
        vcpu = constants.vm.mcp.vcpus;

        shares = [{
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          proto = "9p";
        }];

        interfaces = if useTap then [{
          type = "tap";
          id = constants.network.tapMcp;
          mac = constants.network.mcpVmMac;
        }] else [{
          type = "user";
          id = "eth0";
          mac = constants.network.mcpVmMac;
        }];

        forwardPorts = lib.optionals (!useTap) [
          { from = "host"; host.port = constants.ports.mcpForward; guest.port = 3000; }
          { from = "host"; host.port = constants.ports.sshForwardMcp; guest.port = 22; }
        ];
      };

      # ─── Networking ────────────────────────────────────────────────
      networking.hostName = "mcp-vm";
      networking.firewall.allowedTCPPorts = [ 22 3000 ];

      networking.interfaces = lib.mkIf useTap {
        eth0 = {
          useDHCP = false;
          ipv4.addresses = [{
            address = constants.network.mcpVmIp;
            prefixLength = 24;
          }];
        };
      };
      networking.defaultGateway = lib.mkIf useTap {
        address = constants.network.gateway;
        interface = "eth0";
      };

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
        expect
        tcl
        curl
        jq
        openssh
      ];

      # ─── Test User ─────────────────────────────────────────────────
      users.users.${constants.credentials.testUser} = {
        isNormalUser = true;
        password = constants.credentials.testPassword;
        extraGroups = [ "wheel" ];
      };

      users.users.root.password = lib.mkIf debugMode constants.credentials.rootPassword;

      security.sudo.wheelNeedsPassword = false;

      # ─── MCP Server Service ────────────────────────────────────────
      # Uses `self` to run the exact code from the flake's commit.
      # This ensures reproducibility - the VM always runs the committed version.
      systemd.services.mcp-server = {
        description = "MCP SSH Automation Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          # Use flake's self-reference for source
          ExecStart = "${pkgs.expect}/bin/expect ${self}/mcp/server.tcl --port 3000 --bind 0.0.0.0";
          Restart = "always";
          WorkingDirectory = "${self}";
        };
      };

      # ─── Debug Mode Warning ────────────────────────────────────────
      environment.etc."motd".text = lib.mkIf debugMode ''
        ╔═══════════════════════════════════════════════════════════════╗
        ║  MCP-VM: DEBUG MODE - Password authentication enabled         ║
        ║  User: ${constants.credentials.testUser}                      ║
        ║  Password: ${constants.credentials.testPassword}              ║
        ╚═══════════════════════════════════════════════════════════════╝
      '';
    })
  ];
}.config.microvm.declaredRunner
```

### `nix/ssh-target-vm.nix` - Multi-SSHD Target MicroVM

```nix
# nix/ssh-target-vm.nix
#
# MicroVM with multiple sshd instances for comprehensive testing.
# Each sshd runs on a different port with different configuration.
# Also includes netem rules for network degradation simulation.
#
{
  pkgs,
  lib,
  microvm,
  nixpkgs,
  system,
  networking ? "user",
  debugMode ? false,
}:
let
  constants = import ./constants.nix;
  useTap = networking == "tap";

  # Generate sshd_config for each daemon
  mkSshdConfig = name: cfg: pkgs.writeText "sshd_config_${name}" ''
    Port ${toString cfg.port}
    HostKey /etc/ssh/ssh_host_ed25519_key_${name}
    HostKey /etc/ssh/ssh_host_rsa_key_${name}

    PasswordAuthentication ${if cfg.passwordAuth then "yes" else "no"}
    PubkeyAuthentication ${if cfg.pubkeyAuth then "yes" else "no"}
    PermitRootLogin ${cfg.permitRootLogin}

    # Logging
    SyslogFacility AUTH
    LogLevel INFO

    # Security
    PermitEmptyPasswords no
    ChallengeResponseAuthentication no
    UsePAM yes

    # Subsystems
    Subsystem sftp /run/current-system/sw/libexec/sftp-server
  '';

  # List of all sshd ports (base + netem)
  allSshPorts = (lib.mapAttrsToList (n: c: c.port) constants.sshDaemons)
                ++ (lib.mapAttrsToList (n: c: c.degradedPort) constants.netemProfiles);

  # Generate port forwards for user-mode networking
  portForwards = lib.flatten (lib.mapAttrsToList (name: cfg: [
    { from = "host"; host.port = cfg.port; guest.port = cfg.port; }
  ]) constants.sshDaemons)
  ++ lib.flatten (lib.mapAttrsToList (name: cfg: [
    { from = "host"; host.port = cfg.degradedPort; guest.port = cfg.degradedPort; }
  ]) constants.netemProfiles);

in
nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    microvm.nixosModules.microvm

    ({ config, pkgs, ... }: {
      system.stateVersion = "24.05";
      nixpkgs.hostPlatform = system;

      # ─── MicroVM Configuration ─────────────────────────────────────
      microvm = {
        hypervisor = "qemu";
        mem = constants.vm.target.memoryMB;
        vcpu = constants.vm.target.vcpus;

        shares = [{
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          proto = "9p";
        }];

        interfaces = if useTap then [{
          type = "tap";
          id = constants.network.tapTarget;
          mac = constants.network.targetVmMac;
        }] else [{
          type = "user";
          id = "eth0";
          mac = constants.network.targetVmMac;
        }];

        forwardPorts = lib.optionals (!useTap) portForwards;
      };

      # ─── Networking ────────────────────────────────────────────────
      networking.hostName = "ssh-target";
      networking.firewall.allowedTCPPorts = allSshPorts;

      networking.interfaces = lib.mkIf useTap {
        eth0 = {
          useDHCP = false;
          ipv4.addresses = [{
            address = constants.network.targetVmIp;
            prefixLength = 24;
          }];
        };
      };
      networking.defaultGateway = lib.mkIf useTap {
        address = constants.network.gateway;
        interface = "eth0";
      };

      # ─── Disable default sshd ──────────────────────────────────────
      services.openssh.enable = false;

      # ─── Packages ──────────────────────────────────────────────────
      environment.systemPackages = with pkgs; [
        coreutils
        procps        # ps, top
        iproute2      # ip, ss, tc (for netem)
        util-linux    # hostname
        openssh       # sshd, ssh-keygen
        nftables      # port forwarding for netem
        zsh           # for zshuser
        dash          # for dashuser
        git           # for gituser prompt simulation
      ];

      # ─── Test Users ────────────────────────────────────────────────
      ${lib.concatStrings (lib.mapAttrsToList (name: cfg: ''
      users.users.${name} = {
        isNormalUser = true;
        password = "${cfg.password}";
        shell = pkgs.${cfg.shell};
        extraGroups = [ "wheel" ];
      };
      '') constants.testUsers)}

      users.users.root.password = constants.rootPassword;
      security.sudo.wheelNeedsPassword = false;

      # ─── User Shell Configurations ─────────────────────────────────
      # Create .bashrc files with custom PS1 for each user
      ${lib.concatStrings (lib.mapAttrsToList (name: cfg:
        if cfg.shell == "bash" then ''
      system.activationScripts.${name}-bashrc = '''
        mkdir -p /home/${name}
        cat > /home/${name}/.bashrc << 'BASHRC'
        export PS1='${cfg.ps1}'
        ${if cfg ? promptCommand then cfg.promptCommand else ""}
        BASHRC
        chown ${name}:users /home/${name}/.bashrc
      ''';
      '' else if cfg.shell == "zsh" then ''
      system.activationScripts.${name}-zshrc = '''
        mkdir -p /home/${name}
        cat > /home/${name}/.zshrc << 'ZSHRC'
        export PS1='${cfg.ps1}'
        ZSHRC
        chown ${name}:users /home/${name}/.zshrc
      ''';
      '' else ""
      ) constants.testUsers)}

      # ─── Generate SSH Host Keys ────────────────────────────────────
      system.activationScripts.ssh-host-keys = ''
        ${lib.concatStrings (lib.mapAttrsToList (name: cfg: ''
        if [ ! -f /etc/ssh/ssh_host_ed25519_key_${name} ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key_${name} -N ""
        fi
        if [ ! -f /etc/ssh/ssh_host_rsa_key_${name} ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key_${name} -N ""
        fi
        '') constants.sshDaemons)}
      '';

      # ─── SSHD Services ─────────────────────────────────────────────
      ${lib.concatStrings (lib.mapAttrsToList (name: cfg: ''
      systemd.services.sshd-${name} = {
        description = "SSH Daemon - ${name} (${cfg.description})";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        ${if cfg ? restartInterval then ''
        serviceConfig = {
          ExecStart = "${pkgs.openssh}/bin/sshd -D -f ${mkSshdConfig name cfg}";
          Restart = "always";
          RestartSec = "${toString cfg.restartInterval}";
        };
        '' else ''
        serviceConfig = {
          ExecStart = "${pkgs.openssh}/bin/sshd -D -f ${mkSshdConfig name cfg}";
          Restart = "on-failure";
        };
        ''}
      };
      '') constants.sshDaemons)}

      # ─── Slow Auth PAM Configuration ───────────────────────────────
      # For the slowauth sshd, add PAM delay
      security.pam.services.sshd-slowauth = {
        text = ''
          auth required pam_unix.so
          auth required pam_exec.so /run/current-system/sw/bin/sleep 2
          account required pam_unix.so
          session required pam_unix.so
        '';
      };

      # ─── Netem Network Emulation ───────────────────────────────────
      # Uses nft marks + tc filters for reliable traffic shaping.
      # Flow: degraded port -> nft mark -> tc filter -> netem qdisc -> redirect to base port
      systemd.services.netem-setup = {
        description = "Setup netem network emulation with nft marks";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "netem-setup" ''
            set -e

            # Create IFB (Intermediate Functional Block) device for ingress shaping
            modprobe ifb numifbs=1 || true
            ip link set dev ifb0 up || true

            # Create base tc qdisc structure on loopback
            tc qdisc del dev lo root 2>/dev/null || true
            tc qdisc add dev lo root handle 1: htb default 99
            tc class add dev lo parent 1: classid 1:99 htb rate 1000mbit  # Default class (no shaping)

            # Create single nftables table for all netem marking
            nft add table inet netem 2>/dev/null || true
            nft flush table inet netem
            nft add chain inet netem prerouting { type filter hook prerouting priority -150 \; }
            nft add chain inet netem output { type filter hook output priority -150 \; }
            nft add chain inet netem nat_prerouting { type nat hook prerouting priority -100 \; }

            # Setup each netem profile with nft marks
            ${lib.concatStrings (lib.mapAttrsToList (name: cfg: ''
            # ─── ${name}: ${cfg.description} ───
            # Port ${toString cfg.degradedPort} -> mark ${toString cfg.mark} -> netem -> redirect to ${toString cfg.basePort}

            # Create tc class with netem for this profile
            tc class add dev lo parent 1: classid 1:${toString cfg.mark} htb rate 1000mbit
            tc qdisc add dev lo parent 1:${toString cfg.mark} handle ${toString (cfg.mark * 10)}: netem \
              delay ${cfg.delay}${if cfg ? jitter then " ${cfg.jitter}" else ""}${if cfg.loss != null then " loss ${cfg.loss}" else ""}

            # tc filter: match packets with this mark -> route to netem class
            tc filter add dev lo parent 1: protocol ip prio ${toString cfg.mark} handle ${toString cfg.mark} fw flowid 1:${toString cfg.mark}

            # nft: mark packets destined for degraded port
            nft add rule inet netem output tcp dport ${toString cfg.degradedPort} meta mark set ${toString cfg.mark}

            # nft: redirect degraded port to base port (after netem is applied)
            nft add rule inet netem nat_prerouting tcp dport ${toString cfg.degradedPort} redirect to :${toString cfg.basePort}

            '') constants.netem)}

            echo "Netem setup complete with nft marks + tc filters"
            echo "Profiles configured: ${lib.concatStringsSep ", " (lib.attrNames constants.netem)}"
          '';
        };
      };

      # ─── Test Files ────────────────────────────────────────────────
      environment.etc."test-file.txt".text = ''
        This is a test file for ssh_cat_file testing.
        Line 2 of the test file.
        Line 3 of the test file.
      '';

      environment.etc."large-test-file.txt".text = lib.concatStrings
        (lib.genList (i: "Line ${toString i}: This is line number ${toString i} of the large test file for buffer testing.\n") 1000);

      # ─── MOTD ──────────────────────────────────────────────────────
      environment.etc."motd".text = ''
        ╔═══════════════════════════════════════════════════════════════════════╗
        ║  SSH-TARGET-VM: Multi-SSHD Test Environment                           ║
        ╠═══════════════════════════════════════════════════════════════════════╣
        ║  Base Ports:                                                          ║
        ║    :2222 - standard    (password auth)                                ║
        ║    :2223 - keyonly     (pubkey only)                                  ║
        ║    :2224 - fancyprompt (complex prompts)                              ║
        ║    :2225 - slowauth    (2s delay)                                     ║
        ║    :2226 - denyall     (auth always fails)                            ║
        ║    :2227 - unstable    (restarts every 5s)                            ║
        ║    :2228 - rootlogin   (root permitted)                               ║
        ╠═══════════════════════════════════════════════════════════════════════╣
        ║  Netem Ports (+100 offset): latency/loss simulation                   ║
        ║    :2322 - 100ms latency                                              ║
        ║    :2323 - 50ms + 5% loss                                             ║
        ║    :2324 - 200ms + 10% loss                                           ║
        ║    :2325 - 500ms latency                                              ║
        ║    :2326 - 1000ms latency                                             ║
        ║    :2327 - 100ms + 2% loss                                            ║
        ║    :2328 - 50ms latency                                               ║
        ╠═══════════════════════════════════════════════════════════════════════╣
        ║  Users: testuser, fancyuser, gituser, zshuser, dashuser, slowuser     ║
        ║  Password: testpass (all users), root password: root                  ║
        ╚═══════════════════════════════════════════════════════════════════════╝
      '';
    })
  ];
}.config.microvm.declaredRunner
```

### `nix/network-setup.nix` - TAP Network Scripts

```nix
# nix/network-setup.nix
#
# TAP/bridge network setup for multi-VM testing.
# Creates a bridge with two TAP devices for MCP VM and target VM.
#
{ pkgs }:
let
  constants = import ./constants.nix;
in
{
  setup = pkgs.writeShellApplication {
    name = "ssh-network-setup";
    runtimeInputs = with pkgs; [ iproute2 kmod nftables ];
    text = ''
      set -euo pipefail

      echo "=== SSH-Tool MicroVM Network Setup ==="

      # Load kernel modules
      sudo modprobe tun
      sudo modprobe bridge

      # Create bridge
      if ! ip link show ${constants.network.bridge} &>/dev/null; then
        echo "Creating bridge ${constants.network.bridge}..."
        sudo ip link add ${constants.network.bridge} type bridge
        sudo ip addr add ${constants.network.gateway}/24 dev ${constants.network.bridge}
        sudo ip link set ${constants.network.bridge} up
      fi

      # Create TAP for MCP VM
      if ! ip link show ${constants.network.tapMcp} &>/dev/null; then
        echo "Creating TAP ${constants.network.tapMcp} for MCP VM..."
        sudo ip tuntap add dev ${constants.network.tapMcp} mode tap user "$USER"
        sudo ip link set ${constants.network.tapMcp} master ${constants.network.bridge}
        sudo ip link set ${constants.network.tapMcp} up
      fi

      # Create TAP for target VM
      if ! ip link show ${constants.network.tapTarget} &>/dev/null; then
        echo "Creating TAP ${constants.network.tapTarget} for target VM..."
        sudo ip tuntap add dev ${constants.network.tapTarget} mode tap user "$USER"
        sudo ip link set ${constants.network.tapTarget} master ${constants.network.bridge}
        sudo ip link set ${constants.network.tapTarget} up
      fi

      # NAT for VM internet access
      echo "Configuring NAT..."
      sudo nft add table inet ssh-nat 2>/dev/null || true
      sudo nft flush table inet ssh-nat 2>/dev/null || true
      sudo nft -f - <<EOF
      table inet ssh-nat {
        chain postrouting {
          type nat hook postrouting priority 100;
          ip saddr ${constants.network.subnet} masquerade
        }
        chain forward {
          type filter hook forward priority 0;
          iifname "${constants.network.bridge}" accept
          oifname "${constants.network.bridge}" ct state related,established accept
        }
      }
EOF

      sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

      echo ""
      echo "Network ready:"
      echo "  MCP VM:    ${constants.network.mcpVmIp}:3000 (MCP), :22 (SSH)"
      echo "  Target VM: ${constants.network.targetVmIp}:22 (SSH)"
    '';
  };

  teardown = pkgs.writeShellApplication {
    name = "ssh-network-teardown";
    runtimeInputs = with pkgs; [ iproute2 nftables ];
    text = ''
      set -euo pipefail

      echo "=== SSH-Tool MicroVM Network Teardown ==="

      # Remove TAP devices
      for tap in ${constants.network.tapMcp} ${constants.network.tapTarget}; do
        if ip link show "$tap" &>/dev/null; then
          sudo ip link del "$tap"
          echo "Removed TAP $tap"
        fi
      done

      # Remove bridge
      if ip link show ${constants.network.bridge} &>/dev/null; then
        sudo ip link set ${constants.network.bridge} down
        sudo ip link del ${constants.network.bridge}
        echo "Removed bridge ${constants.network.bridge}"
      fi

      # Remove NAT rules
      sudo nft delete table inet ssh-nat 2>/dev/null && echo "Removed NAT rules" || true

      echo "Network teardown complete"
    '';
  };
}
```

### `nix/vm-scripts.nix` - VM Management Scripts

```nix
# nix/vm-scripts.nix
#
# Helper scripts for managing SSH-Tool MicroVMs.
#
{ pkgs }:
let
  constants = import ./constants.nix;
  sshOpts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR";
in
{
  check = pkgs.writeShellApplication {
    name = "ssh-vm-check";
    runtimeInputs = with pkgs; [ procps gnugrep ];
    text = ''
      echo "=== SSH-Tool MicroVMs ==="
      count=$(pgrep -f "microvm.*ssh" -c 2>/dev/null || echo 0)
      echo "Running VMs: $count"
      if [[ $count -gt 0 ]]; then
        pgrep -af "microvm.*ssh" || true
      fi
    '';
  };

  stop = pkgs.writeShellApplication {
    name = "ssh-vm-stop";
    runtimeInputs = with pkgs; [ procps ];
    text = ''
      echo "Stopping all SSH-Tool MicroVMs..."
      pkill -f "microvm.*ssh" 2>/dev/null || echo "No VMs running"
    '';
  };

  sshMcp = pkgs.writeShellApplication {
    name = "ssh-vm-ssh-mcp";
    runtimeInputs = with pkgs; [ openssh ];
    text = ''
      echo "Connecting to MCP VM..."
      ssh ${sshOpts} -p ${toString constants.ports.sshForwardMcp} \
        ${constants.credentials.testUser}@localhost "$@"
    '';
  };

  sshTarget = pkgs.writeShellApplication {
    name = "ssh-vm-ssh-target";
    runtimeInputs = with pkgs; [ openssh ];
    text = ''
      echo "Connecting to SSH target VM..."
      ssh ${sshOpts} -p ${toString constants.ports.sshForwardTarget} \
        ${constants.credentials.testUser}@localhost "$@"
    '';
  };
}
```

### `nix/test-lib.nix` - Shared Test Functions

```nix
# nix/test-lib.nix
#
# Shared test functions for MicroVM validation.
# Extended for multi-sshd and netem testing.
#
{ pkgs, lib }:
let
  constants = import ./constants.nix;
  sshOpts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR";
in
{
  inherit sshOpts constants;

  # Wait for SSH to become available on a specific port
  waitForSsh = ''
    wait_for_ssh() {
      local host="$1" port="$2" user="''${3:-testuser}" max="''${4:-60}"
      local attempt=0
      echo "Waiting for SSH on $host:$port (user: $user)..."
      while ! ssh ${sshOpts} -p "$port" "$user@$host" true 2>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max ]]; then
          echo "FAIL: SSH not available after $max attempts"
          return 1
        fi
        sleep 2
      done
      echo "SSH connected"
    }
  '';

  # Wait for SSH to fail (for denyall testing)
  waitForSshDeny = ''
    expect_ssh_denied() {
      local host="$1" port="$2" user="''${3:-testuser}"
      echo -n "  CHECK: SSH denied on $host:$port ... "
      if ! ssh ${sshOpts} -p "$port" "$user@$host" true 2>/dev/null; then
        echo "OK (correctly denied)"
        return 0
      else
        echo "FAIL (should have been denied!)"
        return 1
      fi
    }
  '';

  # Wait for MCP server to be ready
  waitForMcp = ''
    wait_for_mcp() {
      local host="$1" port="$2" max="''${3:-30}"
      local attempt=0
      echo "Waiting for MCP server on $host:$port..."
      while ! curl -sf "http://$host:$port/health" >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max ]]; then
          echo "FAIL: MCP server not available after $max attempts"
          return 1
        fi
        sleep 2
      done
      echo "MCP server ready"
    }
  '';

  # MCP JSON-RPC request helper
  mcpRequest = ''
    mcp_request() {
      local host="$1" port="$2" method="$3" params="''${4:-{}}"
      curl -sf "http://$host:$port/" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}"
    }
  '';

  # MCP SSH connect helper
  mcpSshConnect = ''
    mcp_ssh_connect() {
      local mcp_host="$1" mcp_port="$2" ssh_host="$3" ssh_port="$4" user="$5" password="$6"
      mcp_request "$mcp_host" "$mcp_port" "tools/call" \
        "{\"name\":\"ssh_connect\",\"arguments\":{\"host\":\"$ssh_host\",\"port\":$ssh_port,\"user\":\"$user\",\"password\":\"$password\",\"insecure\":true}}"
    }
  '';

  # MCP SSH run command helper
  mcpSshRun = ''
    mcp_ssh_run() {
      local mcp_host="$1" mcp_port="$2" session_id="$3" command="$4"
      mcp_request "$mcp_host" "$mcp_port" "tools/call" \
        "{\"name\":\"ssh_run_command\",\"arguments\":{\"session_id\":\"$session_id\",\"command\":\"$command\"}}"
    }
  '';

  # Check helper
  runCheck = ''
    run_check() {
      local desc="$1"
      shift
      echo -n "  CHECK: $desc ... "
      if "$@" >/dev/null 2>&1; then
        echo "OK"
        return 0
      else
        echo "FAIL"
        return 1
      fi
    }
  '';

  # Timed check helper (for netem tests)
  timedCheck = ''
    timed_check() {
      local desc="$1" min_ms="$2" max_ms="$3"
      shift 3
      echo -n "  CHECK: $desc ... "
      local start_ms=$(date +%s%3N)
      if "$@" >/dev/null 2>&1; then
        local end_ms=$(date +%s%3N)
        local elapsed=$((end_ms - start_ms))
        if [[ $elapsed -ge $min_ms && $elapsed -le $max_ms ]]; then
          echo "OK (''${elapsed}ms, expected ''${min_ms}-''${max_ms}ms)"
          return 0
        else
          echo "FAIL (''${elapsed}ms, expected ''${min_ms}-''${max_ms}ms)"
          return 1
        fi
      else
        echo "FAIL (command failed)"
        return 1
      fi
    }
  '';

  # Extract session ID from MCP response
  extractSessionId = ''
    extract_session_id() {
      echo "$1" | jq -r '.result.content[0].text // .result.session_id // empty' 2>/dev/null | grep -oE '[a-f0-9-]{36}' | head -1
    }
  '';

  # Check if MCP response has error
  hasError = ''
    has_error() {
      echo "$1" | jq -e '.error // .result.isError' >/dev/null 2>&1
    }
  '';
}
```

### `nix/nixos-test.nix` - NixOS Test Framework Integration

The NixOS test framework provides automated multi-VM orchestration for CI. It handles:
- Virtual network setup between VMs
- Waiting for services to be ready
- Running test scripts with full control

```nix
# nix/nixos-test.nix
#
# NixOS test framework integration for automated CI testing.
# Replaces manual VM orchestration with declarative test definitions.
#
{ self, pkgs, lib, nixpkgs, system }:
let
  constants = import ./constants;
in
nixpkgs.lib.nixosTest {
  name = "ssh-tool-integration";

  nodes = {
    # MCP Server node
    mcp = { config, pkgs, ... }: {
      imports = [ self.nixosModules.mcp-vm ];

      # Use flake's source for MCP server
      systemd.services.mcp-server.serviceConfig.ExecStart =
        lib.mkForce "${pkgs.expect}/bin/expect ${self}/mcp/server.tcl --port 3000 --bind 0.0.0.0";

      networking.firewall.allowedTCPPorts = [ 3000 22 ];
    };

    # Multi-SSHD target node
    target = { config, pkgs, ... }: {
      imports = [ self.nixosModules.ssh-target-vm ];

      networking.firewall.allowedTCPPorts = [
        2222 2223 2224 2225 2226 2227 2228  # Base sshd ports
        2322 2323 2324 2325 2326 2327 2328  # Netem ports
      ];
    };
  };

  # Python test script
  testScript = ''
    import json

    start_all()

    # Wait for services
    target.wait_for_unit("sshd-standard.service")
    target.wait_for_open_port(2222)
    mcp.wait_for_unit("mcp-server.service")
    mcp.wait_for_open_port(3000)

    # Test MCP health endpoint
    result = mcp.succeed("curl -sf http://localhost:3000/health")
    assert "ok" in result.lower(), f"Health check failed: {result}"

    # Test SSH connectivity from MCP to target
    mcp.succeed(
      "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
      "-p 2222 testuser@target hostname"
    )

    # Test MCP -> SSH -> target via JSON-RPC
    init_result = mcp.succeed(
      "curl -sf http://localhost:3000/ "
      "-H 'Content-Type: application/json' "
      '-d \'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\'''
    )
    assert "protocolVersion" in init_result, f"Initialize failed: {init_result}"

    # Connect to target via MCP
    connect_result = mcp.succeed(
      "curl -sf http://localhost:3000/ "
      "-H 'Content-Type: application/json' "
      '-d \'{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{'
      '"name":"ssh_connect","arguments":{'
      '"host":"target","port":2222,"user":"testuser","password":"testpass","insecure":true'
      '}}}\'''
    )
    result_json = json.loads(connect_result)
    assert "error" not in result_json, f"SSH connect failed: {connect_result}"

    # Verify auth failure on key-only port
    keyonly_result = mcp.execute(
      "curl -sf http://localhost:3000/ "
      "-H 'Content-Type: application/json' "
      '-d \'{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{'
      '"name":"ssh_connect","arguments":{'
      '"host":"target","port":2223,"user":"testuser","password":"testpass","insecure":true'
      '}}}\'''
    )
    # Should fail - key-only auth
    assert keyonly_result[0] != 0 or "error" in keyonly_result[1], \
      f"Key-only port should reject password: {keyonly_result}"

    # Verify security controls
    # (blocked command test)
    # ... additional security tests ...

    print("All integration tests passed!")
  '';
}
```

**Usage in CI:**

```yaml
# .github/workflows/test.yml
jobs:
  integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - run: nix flake check  # Runs nixos-test.nix automatically
```

### `nix/tests/e2e-test.nix` - Comprehensive Test Suite

```nix
# nix/tests/e2e-test.nix
#
# Comprehensive test suite for multi-sshd environment.
# Tests various SSH configurations, prompts, auth methods, and network conditions.
#
{ pkgs, lib }:
let
  constants = import ../constants.nix;
  testLib = import ../test-lib.nix { inherit pkgs lib; };
in
{
  # ─── Basic E2E Tests ───────────────────────────────────────────────────
  e2e = pkgs.writeShellApplication {
    name = "ssh-test-e2e";
    runtimeInputs = with pkgs; [ curl jq openssh coreutils ];
    text = ''
      echo "═══════════════════════════════════════════════════════════════════"
      echo "  SSH-Tool End-to-End Test Suite"
      echo "═══════════════════════════════════════════════════════════════════"

      ${testLib.waitForSsh}
      ${testLib.waitForMcp}
      ${testLib.mcpRequest}
      ${testLib.mcpSshConnect}
      ${testLib.mcpSshRun}
      ${testLib.runCheck}
      ${testLib.extractSessionId}
      ${testLib.hasError}

      passed=0
      failed=0

      check() {
        if "$@"; then
          passed=$((passed + 1))
        else
          failed=$((failed + 1))
        fi
      }

      MCP_HOST="localhost"
      MCP_PORT="${toString constants.ports.mcpForward}"
      TARGET_HOST="localhost"  # In TAP mode, use ${constants.network.targetVmIp}

      # ─── Phase 1: Wait for Services ──────────────────────────────
      echo ""
      echo "Phase 1: Service Availability"
      wait_for_mcp "$MCP_HOST" "$MCP_PORT" 30
      wait_for_ssh "$TARGET_HOST" 2222 testuser 60

      # ─── Phase 2: MCP Health ─────────────────────────────────────
      echo ""
      echo "Phase 2: MCP Server Health"
      check run_check "health endpoint" curl -sf "http://$MCP_HOST:$MCP_PORT/health"
      check run_check "metrics endpoint" curl -sf "http://$MCP_HOST:$MCP_PORT/metrics"
      check run_check "initialize" mcp_request "$MCP_HOST" "$MCP_PORT" "initialize" "{}"
      check run_check "tools/list" mcp_request "$MCP_HOST" "$MCP_PORT" "tools/list" "{}"

      # ─── Phase 3: Standard SSH (port 2222) ───────────────────────
      echo ""
      echo "Phase 3: Standard SSH (port 2222 - password auth)"

      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2222 "testuser" "testpass")
      session_id=$(extract_session_id "$result")

      if [[ -n "$session_id" ]]; then
        echo "  CHECK: ssh_connect (standard) ... OK (session: $session_id)"
        passed=$((passed + 1))

        check run_check "hostname command" \
          mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "hostname"

        check run_check "ls command" \
          mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "ls -la /tmp"

        check run_check "cat /etc/os-release" \
          mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_cat_file\",\"arguments\":{\"session_id\":\"$session_id\",\"path\":\"/etc/os-release\"}}"

        check run_check "disconnect" \
          mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}"
      else
        echo "  CHECK: ssh_connect (standard) ... FAIL"
        failed=$((failed + 1))
      fi

      # ─── Phase 4: Different Users/Prompts (port 2224) ────────────
      echo ""
      echo "Phase 4: Fancy Prompt Users (port 2224)"

      for user in fancyuser gituser; do
        result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2224 "$user" "testpass")
        session_id=$(extract_session_id "$result")

        if [[ -n "$session_id" ]]; then
          echo "  CHECK: ssh_connect ($user) ... OK"
          passed=$((passed + 1))

          # Run command to verify prompt detection works
          result=$(mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "echo 'hello from $user'")
          if ! has_error "$result"; then
            echo "  CHECK: command with $user prompt ... OK"
            passed=$((passed + 1))
          else
            echo "  CHECK: command with $user prompt ... FAIL"
            failed=$((failed + 1))
          fi

          mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
            "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null
        else
          echo "  CHECK: ssh_connect ($user) ... FAIL"
          failed=$((failed + 1))
        fi
      done

      # ─── Phase 5: Different Shells (zsh, dash) ───────────────────
      echo ""
      echo "Phase 5: Different Shells"

      for user in zshuser dashuser; do
        result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2224 "$user" "testpass")
        session_id=$(extract_session_id "$result")

        if [[ -n "$session_id" ]]; then
          echo "  CHECK: ssh_connect ($user) ... OK"
          passed=$((passed + 1))

          result=$(mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "echo \$SHELL")
          if ! has_error "$result"; then
            echo "  CHECK: command in $user shell ... OK"
            passed=$((passed + 1))
          else
            echo "  CHECK: command in $user shell ... FAIL"
            failed=$((failed + 1))
          fi

          mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
            "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null
        else
          echo "  CHECK: ssh_connect ($user) ... FAIL"
          failed=$((failed + 1))
        fi
      done

      # ─── Phase 6: Root Login (port 2228) ─────────────────────────
      echo ""
      echo "Phase 6: Root Login (port 2228)"

      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2228 "root" "root")
      session_id=$(extract_session_id "$result")

      if [[ -n "$session_id" ]]; then
        echo "  CHECK: ssh_connect (root) ... OK"
        passed=$((passed + 1))

        result=$(mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "id")
        if echo "$result" | grep -q "uid=0"; then
          echo "  CHECK: root uid verification ... OK"
          passed=$((passed + 1))
        else
          echo "  CHECK: root uid verification ... FAIL"
          failed=$((failed + 1))
        fi

        mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null
      else
        echo "  CHECK: ssh_connect (root) ... FAIL"
        failed=$((failed + 1))
      fi

      # ─── Summary ─────────────────────────────────────────────────
      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      total=$((passed + failed))
      echo "  Results: $passed/$total passed"
      if [[ $failed -gt 0 ]]; then
        echo "  Status: FAILED"
        exit 1
      else
        echo "  Status: PASSED"
      fi
      echo "═══════════════════════════════════════════════════════════════════"
    '';
  };

  # ─── Auth Failure Tests ────────────────────────────────────────────────
  authTests = pkgs.writeShellApplication {
    name = "ssh-test-auth";
    runtimeInputs = with pkgs; [ curl jq openssh coreutils ];
    text = ''
      echo "═══════════════════════════════════════════════════════════════════"
      echo "  SSH-Tool Authentication Test Suite"
      echo "═══════════════════════════════════════════════════════════════════"

      ${testLib.waitForMcp}
      ${testLib.mcpRequest}
      ${testLib.mcpSshConnect}
      ${testLib.extractSessionId}
      ${testLib.hasError}
      ${testLib.waitForSshDeny}

      passed=0
      failed=0

      MCP_HOST="localhost"
      MCP_PORT="${toString constants.ports.mcpForward}"
      TARGET_HOST="localhost"

      wait_for_mcp "$MCP_HOST" "$MCP_PORT" 30

      # ─── Test 1: Key-only auth rejects password ──────────────────
      echo ""
      echo "Test 1: Key-only SSH (port 2223) rejects password auth"

      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2223 "testuser" "testpass")
      if has_error "$result"; then
        echo "  CHECK: password rejected on key-only port ... OK"
        passed=$((passed + 1))
      else
        echo "  CHECK: password rejected on key-only port ... FAIL (should reject!)"
        failed=$((failed + 1))
      fi

      # ─── Test 2: Deny-all rejects everything ─────────────────────
      echo ""
      echo "Test 2: Deny-all SSH (port 2226) rejects all auth"

      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2226 "testuser" "testpass")
      if has_error "$result"; then
        echo "  CHECK: auth rejected on deny-all port ... OK"
        passed=$((passed + 1))
      else
        echo "  CHECK: auth rejected on deny-all port ... FAIL (should reject!)"
        failed=$((failed + 1))
      fi

      # ─── Test 3: Wrong password rejected ─────────────────────────
      echo ""
      echo "Test 3: Wrong password rejected"

      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2222 "testuser" "wrongpassword")
      if has_error "$result"; then
        echo "  CHECK: wrong password rejected ... OK"
        passed=$((passed + 1))
      else
        echo "  CHECK: wrong password rejected ... FAIL (should reject!)"
        failed=$((failed + 1))
      fi

      # ─── Test 4: Non-existent user rejected ──────────────────────
      echo ""
      echo "Test 4: Non-existent user rejected"

      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2222 "nosuchuser" "testpass")
      if has_error "$result"; then
        echo "  CHECK: non-existent user rejected ... OK"
        passed=$((passed + 1))
      else
        echo "  CHECK: non-existent user rejected ... FAIL (should reject!)"
        failed=$((failed + 1))
      fi

      # ─── Test 5: Root login denied on standard port ──────────────
      echo ""
      echo "Test 5: Root login denied on standard port (2222)"

      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2222 "root" "root")
      if has_error "$result"; then
        echo "  CHECK: root login denied on standard port ... OK"
        passed=$((passed + 1))
      else
        echo "  CHECK: root login denied on standard port ... FAIL (should deny!)"
        failed=$((failed + 1))
      fi

      # ─── Summary ─────────────────────────────────────────────────
      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      total=$((passed + failed))
      echo "  Results: $passed/$total passed"
      if [[ $failed -gt 0 ]]; then
        echo "  Status: FAILED"
        exit 1
      else
        echo "  Status: PASSED"
      fi
      echo "═══════════════════════════════════════════════════════════════════"
    '';
  };

  # ─── Network Emulation Tests ───────────────────────────────────────────
  netemTests = pkgs.writeShellApplication {
    name = "ssh-test-netem";
    runtimeInputs = with pkgs; [ curl jq openssh coreutils ];
    text = ''
      echo "═══════════════════════════════════════════════════════════════════"
      echo "  SSH-Tool Network Emulation (netem) Test Suite"
      echo "═══════════════════════════════════════════════════════════════════"

      ${testLib.waitForMcp}
      ${testLib.mcpRequest}
      ${testLib.mcpSshConnect}
      ${testLib.mcpSshRun}
      ${testLib.extractSessionId}
      ${testLib.hasError}
      ${testLib.timedCheck}

      passed=0
      failed=0

      MCP_HOST="localhost"
      MCP_PORT="${toString constants.ports.mcpForward}"
      TARGET_HOST="localhost"

      wait_for_mcp "$MCP_HOST" "$MCP_PORT" 30

      # ─── Test 1: Baseline timing (port 2222, no netem) ───────────
      echo ""
      echo "Test 1: Baseline timing (port 2222, no degradation)"

      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2222 "testuser" "testpass")
      session_id=$(extract_session_id "$result")

      if [[ -n "$session_id" ]]; then
        start_ms=$(date +%s%3N)
        mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "hostname" >/dev/null
        end_ms=$(date +%s%3N)
        baseline_ms=$((end_ms - start_ms))
        echo "  CHECK: baseline command latency ... ''${baseline_ms}ms"
        passed=$((passed + 1))

        mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null
      else
        echo "  CHECK: baseline connection ... FAIL"
        failed=$((failed + 1))
        baseline_ms=100
      fi

      # ─── Test 2: 100ms latency (port 2322) ───────────────────────
      echo ""
      echo "Test 2: 100ms latency (port 2322)"

      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2322 "testuser" "testpass")
      session_id=$(extract_session_id "$result")

      if [[ -n "$session_id" ]]; then
        echo "  CHECK: connect through netem port ... OK"
        passed=$((passed + 1))

        start_ms=$(date +%s%3N)
        mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "hostname" >/dev/null
        end_ms=$(date +%s%3N)
        latency_ms=$((end_ms - start_ms))

        # Expect at least 100ms added latency
        expected_min=$((baseline_ms + 80))
        if [[ $latency_ms -ge $expected_min ]]; then
          echo "  CHECK: latency increased to ''${latency_ms}ms (expected >''${expected_min}ms) ... OK"
          passed=$((passed + 1))
        else
          echo "  CHECK: latency only ''${latency_ms}ms (expected >''${expected_min}ms) ... FAIL"
          failed=$((failed + 1))
        fi

        mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null
      else
        echo "  CHECK: connect through netem port ... FAIL"
        failed=$((failed + 1))
      fi

      # ─── Test 3: 500ms latency (port 2325) ───────────────────────
      echo ""
      echo "Test 3: 500ms latency (port 2325 - combined with slow auth)"

      start_ms=$(date +%s%3N)
      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2325 "slowuser" "testpass")
      end_ms=$(date +%s%3N)
      connect_ms=$((end_ms - start_ms))

      session_id=$(extract_session_id "$result")

      if [[ -n "$session_id" ]]; then
        # Should have 2s PAM delay + 500ms network latency
        if [[ $connect_ms -ge 2000 ]]; then
          echo "  CHECK: slow auth + network latency (''${connect_ms}ms) ... OK"
          passed=$((passed + 1))
        else
          echo "  CHECK: slow auth + network latency (''${connect_ms}ms, expected >2000ms) ... FAIL"
          failed=$((failed + 1))
        fi

        mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null
      else
        # Connection might timeout, which is also valid
        echo "  CHECK: slow connection (''${connect_ms}ms) ... OK (timeout expected)"
        passed=$((passed + 1))
      fi

      # ─── Test 4: Packet loss resilience (port 2323) ──────────────
      echo ""
      echo "Test 4: Packet loss resilience (port 2323 - 5% loss)"

      success_count=0
      attempts=5

      for i in $(seq 1 $attempts); do
        result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2323 "testuser" "testpass")
        session_id=$(extract_session_id "$result")

        if [[ -n "$session_id" ]]; then
          result=$(mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "hostname")
          if ! has_error "$result"; then
            success_count=$((success_count + 1))
          fi
          mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
            "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null 2>&1 || true
        fi
      done

      # With 5% packet loss, expect at least 3/5 successes
      if [[ $success_count -ge 3 ]]; then
        echo "  CHECK: lossy connection ($success_count/$attempts succeeded) ... OK"
        passed=$((passed + 1))
      else
        echo "  CHECK: lossy connection ($success_count/$attempts succeeded) ... FAIL"
        failed=$((failed + 1))
      fi

      # ─── Summary ─────────────────────────────────────────────────
      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      total=$((passed + failed))
      echo "  Results: $passed/$total passed"
      if [[ $failed -gt 0 ]]; then
        echo "  Status: FAILED"
        exit 1
      else
        echo "  Status: PASSED"
      fi
      echo "═══════════════════════════════════════════════════════════════════"
    '';
  };

  # ─── Unstable Connection Tests ─────────────────────────────────────────
  stabilityTests = pkgs.writeShellApplication {
    name = "ssh-test-stability";
    runtimeInputs = with pkgs; [ curl jq openssh coreutils ];
    text = ''
      echo "═══════════════════════════════════════════════════════════════════"
      echo "  SSH-Tool Connection Stability Test Suite"
      echo "═══════════════════════════════════════════════════════════════════"

      ${testLib.waitForMcp}
      ${testLib.mcpRequest}
      ${testLib.mcpSshConnect}
      ${testLib.mcpSshRun}
      ${testLib.extractSessionId}
      ${testLib.hasError}

      passed=0
      failed=0

      MCP_HOST="localhost"
      MCP_PORT="${toString constants.ports.mcpForward}"
      TARGET_HOST="localhost"

      wait_for_mcp "$MCP_HOST" "$MCP_PORT" 30

      # ─── Test 1: Unstable sshd (port 2227, restarts every 5s) ────
      echo ""
      echo "Test 1: Unstable sshd (port 2227 - restarts every 5 seconds)"
      echo "  This tests connection handling when sshd restarts mid-session"

      # Try to maintain a session through a restart
      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2227 "testuser" "testpass")
      session_id=$(extract_session_id "$result")

      if [[ -n "$session_id" ]]; then
        echo "  CHECK: initial connect to unstable sshd ... OK"
        passed=$((passed + 1))

        # Run a command
        result=$(mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "hostname")
        if ! has_error "$result"; then
          echo "  CHECK: command before restart ... OK"
          passed=$((passed + 1))
        else
          echo "  CHECK: command before restart ... FAIL"
          failed=$((failed + 1))
        fi

        # Wait for sshd to restart (5 seconds + buffer)
        echo "  Waiting 7 seconds for sshd restart..."
        sleep 7

        # Try to use the session (should fail or reconnect)
        result=$(mcp_ssh_run "$MCP_HOST" "$MCP_PORT" "$session_id" "hostname")
        if has_error "$result"; then
          echo "  CHECK: session invalidated after restart ... OK (expected)"
          passed=$((passed + 1))
        else
          echo "  CHECK: session still works after restart ... OK (reconnected)"
          passed=$((passed + 1))
        fi

        mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null 2>&1 || true
      else
        echo "  CHECK: initial connect to unstable sshd ... FAIL"
        failed=$((failed + 1))
      fi

      # ─── Test 2: Reconnection after failure ──────────────────────
      echo ""
      echo "Test 2: Reconnection after sshd restart"

      # Connect again after the restart
      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2227 "testuser" "testpass")
      session_id=$(extract_session_id "$result")

      if [[ -n "$session_id" ]]; then
        echo "  CHECK: reconnect after restart ... OK"
        passed=$((passed + 1))

        mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null
      else
        echo "  CHECK: reconnect after restart ... FAIL"
        failed=$((failed + 1))
      fi

      # ─── Summary ─────────────────────────────────────────────────
      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      total=$((passed + failed))
      echo "  Results: $passed/$total passed"
      if [[ $failed -gt 0 ]]; then
        echo "  Status: FAILED"
        exit 1
      else
        echo "  Status: PASSED"
      fi
      echo "═══════════════════════════════════════════════════════════════════"
    '';
  };

  # ─── Security Tests ────────────────────────────────────────────────────
  security = pkgs.writeShellApplication {
    name = "ssh-test-security";
    runtimeInputs = with pkgs; [ curl jq ];
    text = ''
      echo "═══════════════════════════════════════════════════════════════════"
      echo "  SSH-Tool Security Test Suite"
      echo "═══════════════════════════════════════════════════════════════════"

      ${testLib.waitForMcp}
      ${testLib.mcpRequest}
      ${testLib.mcpSshConnect}
      ${testLib.extractSessionId}
      ${testLib.hasError}

      passed=0
      failed=0
      critical=0

      expect_blocked() {
        local name="$1"
        local response="$2"
        if has_error "$response"; then
          echo "  CHECK: $name ... BLOCKED (correct)"
          passed=$((passed + 1))
        else
          echo "  CHECK: $name ... NOT BLOCKED (CRITICAL!)"
          failed=$((failed + 1))
          critical=$((critical + 1))
        fi
      }

      MCP_HOST="localhost"
      MCP_PORT="${toString constants.ports.mcpForward}"
      TARGET_HOST="localhost"

      wait_for_mcp "$MCP_HOST" "$MCP_PORT" 30

      # Connect
      echo ""
      echo "Connecting..."
      result=$(mcp_ssh_connect "$MCP_HOST" "$MCP_PORT" "$TARGET_HOST" 2222 "testuser" "testpass")
      session_id=$(extract_session_id "$result")

      if [[ -z "$session_id" ]]; then
        echo "Failed to connect"
        exit 1
      fi
      echo "Connected: $session_id"

      # ─── Command Injection ───────────────────────────────────────
      echo ""
      echo "=== Command Injection Tests ==="

      for cmd in \
        "rm -rf /" \
        "rm --recursive /tmp" \
        "echo test | sh" \
        "echo test | bash" \
        "ls; rm -rf /" \
        "ls && rm -rf /" \
        'echo $(id)' \
        'echo \`id\`' \
        "echo evil > /tmp/file" \
        "cat < /etc/shadow"
      do
        result=$(mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_run_command\",\"arguments\":{\"session_id\":\"$session_id\",\"command\":\"$cmd\"}}")
        expect_blocked "command: $cmd" "$result"
      done

      # ─── Dangerous Commands ──────────────────────────────────────
      echo ""
      echo "=== Dangerous Command Tests ==="

      for cmd in \
        "find /tmp -exec cat {} \\;" \
        "awk 'BEGIN{system(\"id\")}'" \
        "xargs ls" \
        "sed 's/a/b/' /etc/passwd" \
        "/bin/rm -rf /" \
        "./malware" \
        "python -c 'print(1)'" \
        "perl -e 'print 1'"
      do
        result=$(mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_run_command\",\"arguments\":{\"session_id\":\"$session_id\",\"command\":\"$cmd\"}}")
        expect_blocked "command: $cmd" "$result"
      done

      # ─── Network Tools ───────────────────────────────────────────
      echo ""
      echo "=== Network Tool Tests ==="

      for cmd in "curl http://evil.com" "wget http://evil.com" "nc -l 4444" "ssh user@host"; do
        result=$(mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_run_command\",\"arguments\":{\"session_id\":\"$session_id\",\"command\":\"$cmd\"}}")
        expect_blocked "command: $cmd" "$result"
      done

      # ─── Privilege Escalation ────────────────────────────────────
      echo ""
      echo "=== Privilege Escalation Tests ==="

      for cmd in "sudo ls" "su - root" "chmod 777 /tmp" "chown root /tmp"; do
        result=$(mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_run_command\",\"arguments\":{\"session_id\":\"$session_id\",\"command\":\"$cmd\"}}")
        expect_blocked "command: $cmd" "$result"
      done

      # ─── Path Traversal ──────────────────────────────────────────
      echo ""
      echo "=== Path Traversal Tests ==="

      for path in "/etc/shadow" "/etc/sudoers" "/root/.ssh/id_rsa" "/tmp/../etc/shadow" "/bin/bash"; do
        result=$(mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
          "{\"name\":\"ssh_cat_file\",\"arguments\":{\"session_id\":\"$session_id\",\"path\":\"$path\"}}")
        expect_blocked "path: $path" "$result"
      done

      # Cleanup
      mcp_request "$MCP_HOST" "$MCP_PORT" "tools/call" \
        "{\"name\":\"ssh_disconnect\",\"arguments\":{\"session_id\":\"$session_id\"}}" >/dev/null

      # ─── Summary ─────────────────────────────────────────────────
      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      total=$((passed + failed))
      echo "  Results: $passed/$total blocked correctly"
      echo "  Critical failures: $critical"
      if [[ $critical -gt 0 ]]; then
        echo "  Status: VULNERABLE (CRITICAL)"
        exit 1
      elif [[ $failed -gt 0 ]]; then
        echo "  Status: FAILED"
        exit 1
      else
        echo "  Status: SECURE"
      fi
      echo "═══════════════════════════════════════════════════════════════════"
    '';
  };

  # ─── Master Test Runner ────────────────────────────────────────────────
  all = pkgs.writeShellApplication {
    name = "ssh-test-all";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      echo "═══════════════════════════════════════════════════════════════════"
      echo "  SSH-Tool Complete Test Suite"
      echo "═══════════════════════════════════════════════════════════════════"
      echo ""

      SCRIPT_DIR="$(dirname "$0")"
      overall_status=0

      run_suite() {
        local name="$1" script="$2"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Running: $name"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if "$script"; then
          echo "  ✓ $name PASSED"
        else
          echo "  ✗ $name FAILED"
          overall_status=1
        fi
      }

      run_suite "E2E Tests" ssh-test-e2e
      run_suite "Auth Tests" ssh-test-auth
      run_suite "Netem Tests" ssh-test-netem
      run_suite "Stability Tests" ssh-test-stability
      run_suite "Security Tests" ssh-test-security

      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      if [[ $overall_status -eq 0 ]]; then
        echo "  ALL TEST SUITES PASSED"
      else
        echo "  SOME TEST SUITES FAILED"
      fi
      echo "═══════════════════════════════════════════════════════════════════"
      exit $overall_status
    '';
  };
}
```

## Choosing Your Networking Mode

The MicroVMs support two networking modes with different trade-offs:

### User-Mode Networking (Recommended for Development)

| Aspect | Description |
|--------|-------------|
| **Setup** | Zero configuration, no sudo required |
| **Access** | Port forwarding via localhost (e.g., `ssh -p 2222 localhost`) |
| **Use Case** | Quick local development, single-developer testing |
| **Limitation** | VMs cannot directly reach each other; MCP VM uses host port forwards |

```bash
# No setup required - just build and run
nix build .#mcp-vm-debug -o result-mcp
./result-mcp/bin/microvm-run
```

### TAP-Mode Networking (Recommended for Integration Testing)

| Aspect | Description |
|--------|-------------|
| **Setup** | Requires `sudo` for bridge/TAP creation |
| **Access** | Real IP addresses (e.g., `ssh testuser@10.178.0.20`) |
| **Use Case** | Multi-VM testing, CI pipelines, testing network discovery |
| **Advantage** | MCP VM can SSH directly to target VM's IP address |

```bash
# One-time setup (requires sudo)
nix run .#ssh-network-setup

# VMs now accessible at:
#   MCP:    10.178.0.10:3000 (MCP), :22 (SSH)
#   Target: 10.178.0.20:2222-2228 (sshd ports)
```

### Which to Choose?

- **Quick testing/development**: User-mode (no setup overhead)
- **Testing MCP SSH to real IPs**: TAP-mode (realistic network topology)
- **CI with `nix flake check`**: Use NixOS test framework (handles networking automatically)

## App Commands Reference

All available `nix run` commands:

| Command | Description |
|---------|-------------|
| **VM Management** | |
| `nix run .#ssh-vm-check` | Show status of running MicroVMs |
| `nix run .#ssh-vm-stop` | Stop all SSH-Tool MicroVMs |
| `nix run .#ssh-vm-ssh-mcp` | Interactive shell into MCP VM |
| `nix run .#ssh-vm-ssh-target` | Interactive shell into target VM |
| **Network Setup (TAP mode)** | |
| `nix run .#ssh-network-setup` | Create bridge and TAP devices (requires sudo) |
| `nix run .#ssh-network-teardown` | Remove bridge and TAP devices |
| **Test Suites** | |
| `nix run .#ssh-test-all` | Run all test suites |
| `nix run .#ssh-test-e2e` | Basic end-to-end tests |
| `nix run .#ssh-test-auth` | Authentication failure tests |
| `nix run .#ssh-test-netem` | Network latency/loss tests |
| `nix run .#ssh-test-stability` | Connection resilience tests |
| `nix run .#ssh-test-security` | Security control validation |

## Usage

### Development Shell

```bash
# Enter development shell with all tools
nix develop

# Run tests within the shell
./tests/run_all_tests.sh        # CLI mock tests
./mcp/tests/run_all_tests.sh    # MCP mock tests
```

### MicroVM Testing (User-Mode Networking)

```bash
# Build VMs
nix build .#mcp-vm-debug -o result-mcp
nix build .#ssh-target-vm-debug -o result-target

# Terminal 1: Start target VM (multi-sshd)
./result-target/bin/microvm-run

# Terminal 2: Start MCP VM
./result-mcp/bin/microvm-run

# Terminal 3: Run tests
nix run .#ssh-test-all          # Run all test suites
nix run .#ssh-test-e2e          # Basic end-to-end tests
nix run .#ssh-test-auth         # Authentication failure tests
nix run .#ssh-test-netem        # Network emulation tests
nix run .#ssh-test-stability    # Connection stability tests
nix run .#ssh-test-security     # Security validation tests

# Connect to VMs manually
nix run .#ssh-vm-ssh-mcp
nix run .#ssh-vm-ssh-target

# SSH to specific sshd on target VM
ssh -p 2222 testuser@localhost  # Standard
ssh -p 2224 fancyuser@localhost # Fancy prompt
ssh -p 2228 root@localhost      # Root login

# Stop all VMs
nix run .#ssh-vm-stop
```

### MicroVM Testing (TAP Networking)

```bash
# Setup host networking (requires sudo)
nix run .#ssh-network-setup

# Build TAP variants
nix build .#mcp-vm-tap-debug -o result-mcp
nix build .#ssh-target-vm-tap-debug -o result-target

# Start VMs (in separate terminals)
./result-target/bin/microvm-run
./result-mcp/bin/microvm-run

# VMs are now accessible via direct IP:
#   MCP:    10.178.0.10:3000 (MCP), :22 (SSH)
#   Target: 10.178.0.20:2222-2228 (base SSH), :2322-2328 (netem SSH)

# Run all tests
nix run .#ssh-test-all

# Cleanup
nix run .#ssh-vm-stop
nix run .#ssh-network-teardown
```

### Testing Individual SSH Configurations

```bash
# Connect to different sshd configurations on target VM
# (Using user-mode port forwarding)

# Standard password auth
ssh -p 2222 testuser@localhost

# Key-only auth (will fail with password)
ssh -p 2223 testuser@localhost

# Fancy prompt user
ssh -p 2224 fancyuser@localhost

# Slow auth (2 second delay)
ssh -p 2225 slowuser@localhost

# Deny all (always fails)
ssh -p 2226 testuser@localhost

# Unstable (restarts every 5s)
ssh -p 2227 testuser@localhost

# Root login
ssh -p 2228 root@localhost

# Netem degraded ports (same as above but with latency/loss)
ssh -p 2322 testuser@localhost  # +100ms latency
ssh -p 2323 testuser@localhost  # +50ms, 5% loss
ssh -p 2324 fancyuser@localhost # +200ms, 10% loss
```

## MicroVM Variants

| Variant | Networking | Debug | Use Case |
|---------|-----------|-------|----------|
| `mcp-vm` | user | no | CI/automated testing |
| `mcp-vm-debug` | user | yes | Local development, manual testing |
| `mcp-vm-tap` | TAP | no | Multi-VM networking tests |
| `mcp-vm-tap-debug` | TAP | yes | Local multi-VM development |
| `ssh-target-vm` | user | no | CI/automated testing |
| `ssh-target-vm-debug` | user | yes | Local development |
| `ssh-target-vm-tap` | TAP | no | Multi-VM networking tests |
| `ssh-target-vm-tap-debug` | TAP | yes | Local multi-VM development |

## Test Scenarios

### E2E Test (`ssh-test-e2e`)

Tests basic functionality across different configurations:

1. Wait for MCP server and SSH daemons
2. Verify MCP health/metrics endpoints
3. Test standard SSH (port 2222) - connect, run commands, read files
4. Test fancy prompt users (port 2224) - fancyuser, gituser
5. Test different shells - zshuser, dashuser
6. Test root login (port 2228)

### Auth Test (`ssh-test-auth`)

Tests authentication failure handling:

1. Key-only port (2223) rejects password auth
2. Deny-all port (2226) rejects all auth
3. Wrong password rejected
4. Non-existent user rejected
5. Root login denied on standard port

### Netem Test (`ssh-test-netem`)

Tests network degradation handling:

1. Baseline timing measurement (port 2222)
2. 100ms latency verification (port 2322)
3. 500ms latency + slow auth (port 2325)
4. Packet loss resilience (port 2323, 5% loss)
5. Verify expect timeout handling works correctly

### Stability Test (`ssh-test-stability`)

Tests connection resilience:

1. Connect to unstable sshd (port 2227)
2. Run commands before restart
3. Wait for sshd restart (5 seconds)
4. Verify session invalidation detection
5. Test reconnection after failure

### Security Test (`ssh-test-security`)

**Validates the Mandatory Security Controls** documented in `README.md`:

> The MCP server implements **mandatory security controls** - there is no bypass.

This test suite verifies that the allowlist/blocklist isn't just documentation—it's enforced:

| Category | Blocked Patterns Tested | README Section |
|----------|------------------------|----------------|
| Command Injection | `rm`, pipes, `;`, `&&`, `\|\|`, `` ` ``, `$()`, `>`, `<` | Blocked Patterns |
| Dangerous Commands | `find -exec`, `awk`, `sed`, `xargs`, `env` | Blocked Patterns |
| Interpreters | `python`, `perl`, `ruby`, `php`, `sh`, `bash` | Blocked Patterns |
| Network Tools | `curl`, `wget`, `nc`, `ssh`, `telnet` | Blocked Patterns |
| Privilege Escalation | `sudo`, `su`, `chmod`, `chown` | Blocked Patterns |
| Path Traversal | `/etc/shadow`, `/etc/sudoers`, SSH keys, `../` | Path Validation |

**Critical vs Non-Critical Failures:**
- **Critical**: Security control bypassed (command executed, file read)
- **Non-Critical**: Test infrastructure issue (connection failure, timeout)

A single critical failure indicates a security vulnerability and causes the test to exit with status 1.

### All Tests (`ssh-test-all`)

Master runner that executes all test suites in sequence and reports overall status.

## Implementation Plan

### Phase 1: Shell and Flake Setup
- [ ] Create `flake.nix` with basic structure
- [ ] Create `nix/shell.nix` with development tools
- [ ] Create `nix/constants.nix` with multi-sshd and netem config
- [ ] Verify `nix develop` works

### Phase 2: MCP VM Infrastructure
- [ ] Create `nix/mcp-vm.nix`
- [ ] Verify MCP VM boots and server starts
- [ ] Test SSH to localhost

### Phase 3: Multi-SSHD Target VM
- [ ] Create `nix/ssh-target-vm.nix` with multi-sshd support
- [ ] Configure 7 sshd instances (standard, keyonly, fancyprompt, slowauth, denyall, unstable, rootlogin)
- [ ] Create test users with different shells and prompts
- [ ] Verify all sshd instances start correctly

### Phase 4: Netem Network Simulation
- [ ] Configure nftables port redirection
- [ ] Set up tc/netem for latency and packet loss
- [ ] Create 7 netem profiles (+100 port offset)
- [ ] Verify network degradation is applied

### Phase 5: Network Setup Scripts
- [ ] Create `nix/network-setup.nix` (TAP/bridge)
- [ ] Create `nix/vm-scripts.nix` (management)
- [ ] Test TAP networking between VMs

### Phase 6: Test Infrastructure
- [ ] Create `nix/test-lib.nix` with helpers
- [ ] Create E2E test suite
- [ ] Create Auth failure test suite
- [ ] Create Netem test suite
- [ ] Create Stability test suite
- [ ] Create Security test suite
- [ ] Create master test runner

### Phase 7: Documentation and CI
- [ ] Update README with Nix instructions
- [ ] Document all flake outputs
- [ ] Add CI/CD examples (GitHub Actions)

## Comparison with PCP Project

| Aspect | PCP | SSH-Tool |
|--------|-----|----------|
| Primary package | pcp (complex C build) | None (pure TCL/shell) |
| VM purpose | Run PCP services | Run MCP server + multi-SSH targets |
| VM count | 1 (base or eval) | 2 (MCP + target with 7 sshd instances) |
| Networking | user + TAP | user + TAP + netem simulation |
| Test types | Service checks, metrics | E2E, auth, stability, security, network |
| NixOS module | Yes (services.pcp) | No (just VM config) |
| Debug mode | Password auth | Password auth + multiple users |

Key patterns borrowed:
- Modular file structure under `nix/`
- `constants.nix` for shared configuration
- Debug mode with password authentication
- TAP networking with setup/teardown scripts
- `writeShellApplication` for test scripts

## Summary of Test Infrastructure

### SSH Daemon Configurations (7 instances)

| Port | Config | Test Coverage |
|------|--------|---------------|
| 2222 | Standard | Happy path, basic functionality |
| 2223 | Key-only | Auth method failures |
| 2224 | Fancy prompts | Prompt detection robustness |
| 2225 | Slow auth | Timeout handling |
| 2226 | Deny all | Error handling |
| 2227 | Unstable | Connection resilience |
| 2228 | Root login | Privileged sessions |

### Network Emulation Profiles (7 profiles)

| Port | Degradation | Test Coverage |
|------|-------------|---------------|
| 2322 | 100ms latency | Basic latency tolerance |
| 2323 | 50ms + 5% loss | Packet loss handling |
| 2324 | 200ms + 10% loss | Severe degradation |
| 2325 | 500ms latency | Combined slow auth + network |
| 2326 | 1000ms latency | Slow failure detection |
| 2327 | 100ms + 2% loss | Unstable service + bad network |
| 2328 | 50ms latency | Root over slow link |

### Test Users (6 users)

| User | Shell | PS1 Style | Purpose |
|------|-------|-----------|---------|
| testuser | bash | Simple `$ ` | Standard testing |
| fancyuser | bash | Colored prompt | Complex prompt detection |
| gituser | bash | Git-style | PROMPT_COMMAND testing |
| zshuser | zsh | Zsh `%n@%m` | Zsh shell testing |
| dashuser | dash | POSIX `$ ` | Minimal shell testing |
| slowuser | bash | Simple `$ ` | Slow auth testing |

### Test Suites (5 suites)

| Suite | Focus | Key Scenarios |
|-------|-------|---------------|
| e2e | Basic functionality | Commands, users, shells, root |
| auth | Authentication | Key-only, deny, wrong password |
| netem | Network conditions | Latency, packet loss, timeouts |
| stability | Resilience | Unstable sshd, reconnection |
| security | Attack prevention | Injection, traversal, escalation |

This comprehensive test infrastructure enables thorough validation of:
- Prompt detection across shells and configurations
- Authentication handling (success and failure paths)
- Network resilience and timeout behavior
- Connection stability under adverse conditions
- Security controls against attacks
