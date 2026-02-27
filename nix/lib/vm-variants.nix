# nix/lib/vm-variants.nix
#
# Helper to create all 4 VM package variants from a single definition.
# Reduces flake.nix duplication by generating base/debug/tap/tap-debug variants.
#
{ lib }:
{
  # Creates 4 VM package variants from a single definition
  #
  # Usage:
  #   mkVmVariants {
  #     name = "agent";
  #     vmModule = ./nix/agent-vm.nix;
  #     extraArgs = { inherit self; };  # optional
  #   }
  #
  # Returns:
  #   {
  #     agent-vm = <derivation>;
  #     agent-vm-debug = <derivation>;
  #     agent-vm-tap = <derivation>;
  #     agent-vm-tap-debug = <derivation>;
  #   }
  #
  mkVmVariants =
    {
      pkgs,
      microvm,
      nixpkgs,
      system,
    }:
    {
      name,
      vmModule,
      extraArgs ? { },
    }:
    let
      variants = [
        {
          suffix = "";
          networking = "user";
          debugMode = false;
        }
        {
          suffix = "-debug";
          networking = "user";
          debugMode = true;
        }
        {
          suffix = "-tap";
          networking = "tap";
          debugMode = false;
        }
        {
          suffix = "-tap-debug";
          networking = "tap";
          debugMode = true;
        }
      ];
    in
    lib.listToAttrs (
      map (
        v:
        lib.nameValuePair "${name}-vm${v.suffix}" (
          import vmModule (
            {
              inherit
                pkgs
                lib
                microvm
                nixpkgs
                system
                ;
              inherit (v) networking debugMode;
            }
            // extraArgs
          )
        )
      ) variants
    );

  # Create variants for multiple VMs at once
  #
  # Usage:
  #   mkAllVmVariants baseArgs [
  #     { name = "agent"; vmModule = ./agent-vm.nix; extraArgs = { inherit self; }; }
  #     { name = "mcp"; vmModule = ./mcp-vm.nix; extraArgs = { inherit self; }; }
  #     { name = "ssh-target"; vmModule = ./ssh-target-vm.nix; }
  #   ]
  mkAllVmVariants =
    baseArgs: vmDefs:
    let
      mkVm = baseArgs: vmDef: (import ./vm-variants.nix { inherit lib; }).mkVmVariants baseArgs vmDef;
    in
    lib.foldl' (acc: vmDef: acc // (mkVm baseArgs vmDef)) { } vmDefs;
}
