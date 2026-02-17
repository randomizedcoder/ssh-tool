# nix/constants/netem.nix
#
# Network emulation profiles for testing latency and packet loss.
# Each profile maps a degraded port to a base port with netem parameters.
# Uses nft marks for reliable tc filter matching.
#
{
  # Port 2322: 100ms latency (base: 2222)
  latency100 = {
    basePort = 2222;
    degradedPort = 2322;
    description = "100ms latency";
    delay = "100ms";
    jitter = "10ms";
    loss = null;
    mark = 1;
  };

  # Port 2323: 50ms latency + 5% packet loss (base: 2223)
  lossy5 = {
    basePort = 2223;
    degradedPort = 2323;
    description = "50ms latency + 5% packet loss";
    delay = "50ms";
    jitter = "5ms";
    loss = "5%";
    mark = 2;
  };

  # Port 2324: 200ms latency + 10% packet loss (base: 2224)
  severe = {
    basePort = 2224;
    degradedPort = 2324;
    description = "200ms latency + 10% packet loss";
    delay = "200ms";
    jitter = "20ms";
    loss = "10%";
    mark = 3;
  };

  # Port 2325: 500ms latency (base: 2225, combined with slow auth)
  verySlow = {
    basePort = 2225;
    degradedPort = 2325;
    description = "500ms latency (combined with slow auth)";
    delay = "500ms";
    jitter = "50ms";
    loss = null;
    mark = 4;
  };

  # Port 2326: 1000ms latency (base: 2226, slow failure detection)
  slowFail = {
    basePort = 2226;
    degradedPort = 2326;
    description = "1000ms latency (slow failure)";
    delay = "1000ms";
    jitter = "100ms";
    loss = null;
    mark = 5;
  };

  # Port 2327: 100ms latency + 2% loss (base: 2227, unstable + bad network)
  unstableNetwork = {
    basePort = 2227;
    degradedPort = 2327;
    description = "100ms latency + 2% loss (unstable service)";
    delay = "100ms";
    jitter = "30ms";
    loss = "2%";
    mark = 6;
  };

  # Port 2328: 50ms latency (base: 2228, root over slow link)
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
