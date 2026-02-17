# nix/constants/sshd.nix
#
# SSH daemon configurations for multi-sshd target VM.
# Each daemon runs on its own port with specific settings.
#
{
  # Port 2222: Standard password authentication
  standard = {
    port = 2222;
    description = "Standard password auth";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "no";
  };

  # Port 2223: Public key only (password rejected)
  keyonly = {
    port = 2223;
    description = "Public key auth only";
    passwordAuth = false;
    pubkeyAuth = true;
    permitRootLogin = "no";
  };

  # Port 2224: Users with complex prompts
  fancyprompt = {
    port = 2224;
    description = "Users with complex prompts";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "no";
  };

  # Port 2225: Slow authentication (2-second PAM delay)
  slowauth = {
    port = 2225;
    description = "2-second PAM authentication delay";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "no";
    pamDelay = 2;
  };

  # Port 2226: All authentication rejected
  denyall = {
    port = 2226;
    description = "All authentication rejected";
    passwordAuth = false;
    pubkeyAuth = false;
    permitRootLogin = "no";
  };

  # Port 2227: Unstable (restarts every 5 seconds)
  unstable = {
    port = 2227;
    description = "Restarts every 5 seconds";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "no";
    restartInterval = 5;
  };

  # Port 2228: Root login permitted
  rootlogin = {
    port = 2228;
    description = "Root login permitted";
    passwordAuth = true;
    pubkeyAuth = true;
    permitRootLogin = "yes";
  };
}
