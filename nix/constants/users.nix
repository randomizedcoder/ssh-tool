# nix/constants/users.nix
#
# Test user definitions for SSH-Tool MicroVMs.
# Each user has different shell/prompt configuration for testing.
#
{
  # Standard test user - basic bash with simple prompt
  testuser = {
    password = "testpass";
    shell = "bash";
    ps1 = "\\$ ";
    description = "Standard test user";
  };

  # Fancy prompt user - colored prompt with user@host:path
  fancyuser = {
    password = "testpass";
    shell = "bash";
    # Green user@host, blue path
    ps1 = "\\[\\e[32m\\]\\u@\\h\\[\\e[0m\\]:\\[\\e[34m\\]\\w\\[\\e[0m\\]\\$ ";
    description = "User with colored prompt";
  };

  # Git-style prompt user - simulates git branch in prompt
  gituser = {
    password = "testpass";
    shell = "bash";
    ps1 = "[\\u@\\h \\W]\\$ ";
    promptCommand = "__git_ps1() { echo \" (main)\"; }; PS1=\"[\\u@\\h \\W\\$(__git_ps1)]\\$ \"";
    description = "User with git-style prompt";
  };

  # Zsh user - tests zsh shell handling
  zshuser = {
    password = "testpass";
    shell = "zsh";
    ps1 = "%n@%m:%~%# ";
    description = "Zsh shell user";
  };

  # Dash user - minimal POSIX shell
  dashuser = {
    password = "testpass";
    shell = "dash";
    ps1 = "$ ";
    description = "Minimal POSIX shell user";
  };

  # Slow user - used with slowauth sshd for timing tests
  slowuser = {
    password = "testpass";
    shell = "bash";
    ps1 = "\\$ ";
    description = "Used with slowauth sshd";
  };

  # Root credentials (INSECURE: Only for ephemeral test VMs)
  root = {
    password = "root";
    # Pre-computed hash for "root" - use hashedPassword in NixOS config
    hashedPassword = "$6$x.CeZmapuHoNS8EF$ANtbvz0fWN1rC/qpZtuvoQGUrZ9BbZ5TgYVHDmwBSsqmf/.SdzAmzuggst52o1ESMqrGSfT4Uvz0IuHLFHRVP/";
    shell = "bash";
    ps1 = "# ";
    description = "Root user for port 2228 testing";
  };

  # VM resource allocation (deprecated - use resources.nix instead)
  # Kept for backwards compatibility
  vmResources = (import ./resources.nix).profiles.default;
}
