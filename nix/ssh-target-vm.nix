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
  # Import all constants
  constants = import ./constants;
  network = constants.network;
  ports = constants.ports;
  users = constants.users;
  sshd = constants.sshd;
  netem = constants.netem;
  resources = constants.resources.profiles.default;

  # Import library helpers
  nixLib = import ./lib { inherit pkgs lib; };
  sshdLib = nixLib.sshdConfig;

  useTap = networking == "tap";

  # List of all sshd ports (base + netem)
  allSshPorts =
    (lib.mapAttrsToList (n: c: c.port) sshd) ++ (lib.mapAttrsToList (n: c: c.degradedPort) netem);

  # Generate port forwards for user-mode networking
  portForwards =
    (lib.flatten (
      lib.mapAttrsToList (name: cfg: [
        {
          host = cfg.port;
          guest = cfg.port;
        }
      ]) sshd
    ))
    ++ (lib.flatten (
      lib.mapAttrsToList (name: cfg: [
        {
          host = cfg.degradedPort;
          guest = cfg.degradedPort;
        }
      ]) netem
    ));

  # Build the NixOS system for the MicroVM
  nixos = nixpkgs.lib.nixosSystem {
    inherit system;

    modules = [
      microvm.nixosModules.microvm

      # Import shared modules
      ./modules/vm-base.nix
      ./modules/vm-networking.nix

      (
        { config, pkgs, ... }:
        {
          nixpkgs.hostPlatform = system;

          # ─── VM Base Configuration ───────────────────────────────────────
          vmBase = {
            vmName = "ssh-target";
            serialPort = ports.console.targetSerial;
            virtioPort = ports.console.targetVirtio;
            memoryMB = resources.target.memoryMB;
            vcpus = resources.target.vcpus;
          };

          # ─── Networking ──────────────────────────────────────────────────
          vmNetworking = {
            inherit useTap;
            tapDevice = network.tapTarget;
            macAddress = network.targetVmMac;
            ipAddress = network.targetVmIp;
            gateway = network.gateway;
            hostPorts = portForwards;
          };

          networking.hostName = "ssh-target";
          networking.firewall.allowedTCPPorts = allSshPorts;

          # ─── Disable default sshd ────────────────────────────────────────
          services.openssh.enable = false;

          # ─── SSHD privilege separation user (required for sshd) ──────────
          users.users.sshd = {
            isSystemUser = true;
            group = "sshd";
            description = "SSH privilege separation user";
          };
          users.groups.sshd = { };

          # ─── PAM configuration for sshd ──────────────────────────────────
          security.pam.services.sshd = {
            startSession = true;
            showMotd = true;
            unixAuth = true;
          };

          # ─── Network Command Test Infrastructure ─────────────────────────
          # Reference: DESIGN_NETWORK_COMMANDS.md "VM Test Infrastructure"

          # Enable nftables with test rules for firewall inspection testing
          networking.nftables = {
            enable = true;
            ruleset = ''
              table inet test_filter {
                chain input {
                  type filter hook input priority 0; policy accept;
                  # Test rules for inspection
                  counter comment "test input counter"
                }
                chain output {
                  type filter hook output priority 0; policy accept;
                  counter comment "test output counter"
                }
              }
              table inet test_nat {
                chain prerouting {
                  type nat hook prerouting priority 0;
                }
                chain postrouting {
                  type nat hook postrouting priority 0;
                }
              }
            '';
          };

          # Enable connection tracking for conntrack -L testing
          boot.kernelModules = [
            "nf_conntrack"
            "dummy"
            "bridge"
          ];

          # ─── Packages ────────────────────────────────────────────────────
          # Reference: DESIGN_NETWORK_COMMANDS.md "VM Test Infrastructure"
          environment.systemPackages = with pkgs; [
            coreutils
            procps # ps, top
            iproute2 # ip, ss, tc (for netem)
            util-linux # hostname
            openssh # sshd, ssh-keygen
            nftables # port forwarding for netem
            zsh # for zshuser
            dash # for dashuser
            git # for gituser prompt simulation
            # Network diagnostic tools for network command testing
            ethtool # ethtool -S/-i/-k
            conntrack-tools # conntrack -L
            bridge-utils # brctl (legacy, bridge cmd preferred)
            bind.dnsutils # dig, nslookup, host
            traceroute # traceroute
            mtr # mtr --report
            iputils # ping
            tcpdump # packet capture for debugging
          ];

          # ─── Test Users ──────────────────────────────────────────────────
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

          users.users.gituser = {
            isNormalUser = true;
            password = users.gituser.password;
            shell = pkgs.bash;
            extraGroups = [ "wheel" ];
          };

          users.users.zshuser = {
            isNormalUser = true;
            password = users.zshuser.password;
            shell = pkgs.zsh;
            extraGroups = [ "wheel" ];
            ignoreShellProgramCheck = true;
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

          users.users.root.password = users.root.password;
          security.sudo.wheelNeedsPassword = false;

          # ─── User Shell Configurations ───────────────────────────────────
          system.activationScripts.user-shells = ''
            # testuser - simple prompt
            mkdir -p /home/testuser
            echo 'export PS1="${users.testuser.ps1}"' > /home/testuser/.bashrc
            chown testuser:users /home/testuser/.bashrc

            # fancyuser - colored prompt
            mkdir -p /home/fancyuser
            echo 'export PS1="${users.fancyuser.ps1}"' > /home/fancyuser/.bashrc
            chown fancyuser:users /home/fancyuser/.bashrc

            # gituser - git-style prompt
            mkdir -p /home/gituser
            cat > /home/gituser/.bashrc << 'GITBASHRC'
            ${users.gituser.promptCommand}
            GITBASHRC
            chown gituser:users /home/gituser/.bashrc

            # zshuser - zsh prompt
            mkdir -p /home/zshuser
            echo 'export PS1="${users.zshuser.ps1}"' > /home/zshuser/.zshrc
            chown zshuser:users /home/zshuser/.zshrc

            # slowuser - simple prompt
            mkdir -p /home/slowuser
            echo 'export PS1="${users.slowuser.ps1}"' > /home/slowuser/.bashrc
            chown slowuser:users /home/slowuser/.bashrc
          '';

          # ─── Generate SSH Host Keys ──────────────────────────────────────
          # All sshd daemons share the same host keys
          system.activationScripts.ssh-host-keys = ''
            if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
              ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
            fi
            if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
              ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
            fi
          '';

          # ─── SSHD Services ───────────────────────────────────────────────
          systemd.services = (sshdLib.mkSshdServices sshd) // {
            # SSH Host Keys Service
            ssh-host-keys = sshdLib.mkSshHostKeysServiceWithBefore sshd;

            # ─── Netem Network Emulation ─────────────────────────────────
            # Uses nftables to redirect and mark packets, tc/netem for delay/loss
            netem-setup = {
              description = "Setup netem network emulation with nft marks";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "netem-setup" ''
                  set -e

                  # Create base tc qdisc structure on loopback
                  ${pkgs.iproute2}/bin/tc qdisc del dev lo root 2>/dev/null || true
                  ${pkgs.iproute2}/bin/tc qdisc add dev lo root handle 1: prio bands 16

                  # Create nftables table for netem
                  ${pkgs.nftables}/bin/nft add table inet netem 2>/dev/null || true
                  ${pkgs.nftables}/bin/nft flush table inet netem
                  ${pkgs.nftables}/bin/nft add chain inet netem output { type filter hook output priority -150 \; }
                  ${pkgs.nftables}/bin/nft add chain inet netem prerouting { type nat hook prerouting priority -100 \; }

                  ${lib.concatStrings (
                    lib.mapAttrsToList (name: cfg: ''
                      # ─── ${name}: ${cfg.description} ───
                      # Port ${toString cfg.degradedPort} -> mark ${toString cfg.mark} -> netem -> redirect to ${toString cfg.basePort}

                      # Create tc class with netem for this profile
                      ${pkgs.iproute2}/bin/tc qdisc add dev lo parent 1:${toString cfg.mark} handle ${toString (cfg.mark * 10)}: netem \
                        delay ${cfg.delay}${if cfg.jitter != null then " ${cfg.jitter}" else ""}${
                          if cfg.loss != null then " loss ${cfg.loss}" else ""
                        } 2>/dev/null || true

                      # tc filter: match packets with this mark -> route to netem class
                      ${pkgs.iproute2}/bin/tc filter add dev lo parent 1: protocol ip prio ${toString cfg.mark} handle ${toString cfg.mark} fw flowid 1:${toString cfg.mark} 2>/dev/null || true

                      # nft: mark packets destined for degraded port
                      ${pkgs.nftables}/bin/nft add rule inet netem output tcp dport ${toString cfg.degradedPort} meta mark set ${toString cfg.mark}

                      # nft: redirect degraded port to base port
                      ${pkgs.nftables}/bin/nft add rule inet netem prerouting tcp dport ${toString cfg.degradedPort} redirect to :${toString cfg.basePort}

                    '') netem
                  )}

                  echo "Netem setup complete"
                '';
              };
            };

            # ─── Network Test Infrastructure ─────────────────────────────
            # Reference: DESIGN_NETWORK_COMMANDS.md "VM Test Infrastructure"

            # Create test network namespace with veth pair
            setup-test-netns = {
              description = "Create test network namespace";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "setup-test-netns" ''
                  set -e
                  # Create namespace
                  ${pkgs.iproute2}/bin/ip netns add testns 2>/dev/null || true

                  # Create veth pair
                  ${pkgs.iproute2}/bin/ip link add veth-host type veth peer name veth-ns 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip link set veth-ns netns testns 2>/dev/null || true

                  # Configure host side
                  ${pkgs.iproute2}/bin/ip addr add 10.200.0.1/24 dev veth-host 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip link set veth-host up

                  # Configure namespace side
                  ${pkgs.iproute2}/bin/ip netns exec testns ip addr add 10.200.0.2/24 dev veth-ns
                  ${pkgs.iproute2}/bin/ip netns exec testns ip link set veth-ns up
                  ${pkgs.iproute2}/bin/ip netns exec testns ip link set lo up

                  echo "Test network namespace setup complete"
                '';
              };
            };

            # Create dummy interface and bridge for network inspection testing
            setup-test-interfaces = {
              description = "Create test interfaces (dummy, bridge)";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "setup-test-interfaces" ''
                  set -e
                  # Create dummy interface for ethtool/ip testing
                  ${pkgs.iproute2}/bin/ip link add dummy0 type dummy 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip addr add 10.99.0.1/24 dev dummy0 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip link set dummy0 up

                  # Create bridge interface for bridge command testing
                  ${pkgs.iproute2}/bin/ip link add testbr0 type bridge 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip addr add 10.98.0.1/24 dev testbr0 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip link set testbr0 up

                  echo "Test interfaces setup complete"
                '';
              };
            };

            # Setup traffic control qdiscs for tc command testing
            setup-test-qdisc = {
              description = "Setup test traffic control qdiscs";
              wantedBy = [ "multi-user.target" ];
              after = [
                "network.target"
                "setup-test-interfaces.service"
              ];
              wants = [ "setup-test-interfaces.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "setup-test-qdisc" ''
                  set -e
                  # Add htb qdisc to dummy0 for tc inspection testing
                  ${pkgs.iproute2}/bin/tc qdisc add dev dummy0 root handle 1: htb default 10 2>/dev/null || true
                  ${pkgs.iproute2}/bin/tc class add dev dummy0 parent 1: classid 1:10 htb rate 100mbit 2>/dev/null || true

                  echo "Test qdisc setup complete"
                '';
              };
            };
          };

          # ─── Test Files and MOTD ─────────────────────────────────────────
          environment.etc = {
            "test-file.txt".text = ''
              This is a test file for ssh_cat_file testing.
              Line 2 of the test file.
              Line 3 of the test file.
            '';

            "large-test-file.txt".text = lib.concatStrings (
              lib.genList (
                i:
                "Line ${toString i}: This is line number ${toString i} of the large test file for buffer testing.\n"
              ) 1000
            );

            "motd".text = ''
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
          };
        }
      )
    ];
  };

in
nixos.config.microvm.declaredRunner
