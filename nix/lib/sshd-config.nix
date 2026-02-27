# nix/lib/sshd-config.nix
#
# SSHD configuration generation helpers.
# Provides functions to generate sshd_config files and systemd services.
#
{ pkgs, lib }:
{
  # Generate sshd_config file for a daemon
  # All daemons share the same host keys (different ports, same identity)
  mkSshdConfig =
    name: cfg:
    pkgs.writeText "sshd_config_${name}" ''
      Port ${toString cfg.port}
      HostKey /etc/ssh/ssh_host_ed25519_key
      HostKey /etc/ssh/ssh_host_rsa_key

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
      Subsystem sftp ${pkgs.openssh}/libexec/sftp-server
    '';

  # Generate sshd_config text (for NixOS test environment.etc)
  mkSshdConfigText = cfg: ''
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

  # Generate systemd service for an sshd instance
  mkSshdService = name: cfg: sshdConfig: {
    description = "SSH Daemon - ${name} (${cfg.description})";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "ssh-host-keys.service"
    ];
    wants = [ "ssh-host-keys.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.openssh}/bin/sshd -D -f ${sshdConfig}";
      Restart = if cfg ? restartInterval then "always" else "on-failure";
    }
    // (lib.optionalAttrs (cfg ? restartInterval) {
      RestartSec = toString cfg.restartInterval;
    });
  };

  # Generate all sshd services from sshd constants
  mkSshdServices =
    sshdConfigs:
    lib.mapAttrs' (
      name: cfg:
      let
        configFile = pkgs.writeText "sshd_config_${name}" ''
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
      in
      lib.nameValuePair "sshd-${name}" {
        description = "SSH Daemon - ${name} (${cfg.description})";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network.target"
          "ssh-host-keys.service"
        ];
        wants = [ "ssh-host-keys.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.openssh}/bin/sshd -D -f ${configFile}";
          Restart = if cfg ? restartInterval then "always" else "on-failure";
        }
        // (lib.optionalAttrs (cfg ? restartInterval) {
          RestartSec = toString cfg.restartInterval;
        });
      }
    ) sshdConfigs;

  # SSH host key generation service
  sshHostKeysService = {
    description = "Generate SSH host keys";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "generate-ssh-keys" ''
        mkdir -p /etc/ssh
        chmod 755 /etc/ssh
        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
          chmod 600 /etc/ssh/ssh_host_ed25519_key
          chmod 644 /etc/ssh/ssh_host_ed25519_key.pub
        fi
        if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
          chmod 600 /etc/ssh/ssh_host_rsa_key
          chmod 644 /etc/ssh/ssh_host_rsa_key.pub
        fi
      '';
    };
  };

  # Helper to set "before" on the ssh-host-keys service
  mkSshHostKeysServiceWithBefore = sshdConfigs: {
    description = "Generate SSH host keys";
    wantedBy = [ "multi-user.target" ];
    before = lib.mapAttrsToList (name: cfg: "sshd-${name}.service") sshdConfigs;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "generate-ssh-keys" ''
        mkdir -p /etc/ssh
        chmod 755 /etc/ssh
        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
          chmod 600 /etc/ssh/ssh_host_ed25519_key
          chmod 644 /etc/ssh/ssh_host_ed25519_key.pub
        fi
        if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
          chmod 600 /etc/ssh/ssh_host_rsa_key
          chmod 644 /etc/ssh/ssh_host_rsa_key.pub
        fi
      '';
    };
  };
}
