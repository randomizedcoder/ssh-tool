# nix/constants/resources.nix
#
# VM resource profiles for SSH-Tool MicroVM infrastructure.
# Merges previously separate definitions from users.nix and loadtest.nix.
#
{
  # Resource profiles for different use cases
  profiles = {
    # Default profile - conservative resources for development
    default = {
      agent = {
        memoryMB = 256;
        vcpus = 1;
      };
      mcp = {
        memoryMB = 512;
        vcpus = 2;
      };
      target = {
        memoryMB = 512;
        vcpus = 2;
      };
    };

    # Load testing profile - larger resources for meaningful measurements
    loadtest = {
      agent = {
        memoryMB = 512;
        vcpus = 2;
      };
      mcp = {
        memoryMB = 1024;
        vcpus = 4;
      };
      target = {
        memoryMB = 1024;
        vcpus = 4;
      };
    };
  };

  # Helper to get resources for a VM by profile
  # Usage: resources.forVm "default" "agent"
  forVm =
    profile: vm:
    let
      profiles = (import ./resources.nix).profiles;
    in
    profiles.${profile}.${vm};
}
