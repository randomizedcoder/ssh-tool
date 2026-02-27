# nix/lib/apps.nix
#
# Helper functions for creating flake app definitions.
# Reduces boilerplate in flake.nix apps section.
#
{ lib }:
{
  # Convert a single derivation to an app definition
  # The derivation should have a bin/ directory with an executable
  #
  # Usage:
  #   mkApp drv "binary-name"
  #
  mkApp = drv: binName: {
    type = "app";
    program = "${drv}/bin/${binName}";
  };

  # Convert a derivation to an app using its derivation name
  # Assumes the binary name matches the derivation name
  #
  # Usage:
  #   mkAppFromName drv  # uses drv.name as binary name
  #
  mkAppFromName = drv: {
    type = "app";
    program = "${drv}/bin/${drv.name}";
  };

  # Convert an attrset of derivations to app definitions
  # Keys become app names, values are converted using mkApp
  #
  # Usage:
  #   mkApps {
  #     my-script = myScriptDrv;  # Binary: my-script
  #     other-script = otherDrv;   # Binary: other-script
  #   }
  #
  # Returns:
  #   {
  #     my-script = { type = "app"; program = ".../bin/my-script"; };
  #     other-script = { type = "app"; program = ".../bin/other-script"; };
  #   }
  #
  mkApps =
    apps:
    lib.mapAttrs (name: drv: {
      type = "app";
      program = "${drv}/bin/${name}";
    }) apps;

  # Convert script modules (like vm-scripts.nix output) to apps
  # Takes an attrset where each value has a derivation with a known binary name
  #
  # Usage:
  #   mkAppsFromScripts {
  #     check = { drv = checkScript; bin = "ssh-vm-check"; };
  #     stop = { drv = stopScript; bin = "ssh-vm-stop"; };
  #   }
  #
  mkAppsFromScripts =
    scripts:
    lib.mapAttrs (
      name:
      { drv, bin }:
      {
        type = "app";
        program = "${drv}/bin/${bin}";
      }
    ) scripts;

  # Convert test scripts from test modules to apps
  # Maps test script outputs to flake apps with custom names
  #
  # Usage:
  #   mkTestApps "ssh-test" testScripts
  #   where testScripts = { e2e = drv; auth = drv; }
  #
  # Returns:
  #   {
  #     ssh-test-e2e = { type = "app"; program = ".../bin/ssh-test-e2e"; };
  #     ssh-test-auth = { type = "app"; program = ".../bin/ssh-test-auth"; };
  #   }
  #
  mkTestApps =
    prefix: testScripts:
    lib.mapAttrs' (
      name: drv:
      lib.nameValuePair "${prefix}-${name}" {
        type = "app";
        program = "${drv}/bin/${prefix}-${name}";
      }
    ) testScripts;
}
