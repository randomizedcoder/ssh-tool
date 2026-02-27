# nix/modules/vm-users.nix
#
# Test user configuration module for MicroVMs.
# Provides standard test user setup used across VMs.
#
# Usage in VM file:
#   imports = [ ../modules/vm-users.nix ];
#   vmUsers = {
#     testUserPassword = "testpass";
#     enableDebugRoot = true;
#     rootPassword = "root";
#   };
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.vmUsers;
in
{
  options.vmUsers = {
    testUserPassword = lib.mkOption {
      type = lib.types.str;
      description = "Password for the testuser account";
    };

    enableDebugRoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable root password for debugging (INSECURE)";
    };

    rootPassword = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Root password when debug mode is enabled";
    };

    rootHashedPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Hashed root password (overrides rootPassword)";
    };

    enablePasswordAuth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SSH password authentication";
    };
  };

  config = {
    # Test user - standard across all VMs
    users.users.testuser = {
      isNormalUser = true;
      password = cfg.testUserPassword;
      extraGroups = [ "wheel" ];
    };

    # Root password (only in debug mode, unless hashedPassword provided)
    users.users.root = lib.mkMerge [
      (lib.mkIf (cfg.rootHashedPassword != null) { hashedPassword = cfg.rootHashedPassword; })
      (lib.mkIf (cfg.enableDebugRoot && cfg.rootHashedPassword == null) { password = cfg.rootPassword; })
    ];

    # Passwordless sudo for wheel group
    security.sudo.wheelNeedsPassword = false;

    # SSH server configuration
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = cfg.enablePasswordAuth || cfg.enableDebugRoot;
        PermitRootLogin = if cfg.enableDebugRoot then "yes" else "prohibit-password";
      };
    };
  };
}
