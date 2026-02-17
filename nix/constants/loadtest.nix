# nix/constants/loadtest.nix
#
# Load testing configuration for SSH-Tool MicroVM infrastructure.
# Defines resource profiles and test parameters.
#
{
  # VM resource profiles for load testing
  # Larger than default to enable meaningful performance measurements
  vmResources = {
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

  # Pool configuration for load tests
  # Increased limits to allow higher concurrency testing
  poolConfig = {
    maxConnections = 20;
    idleTimeoutMs = 300000;  # 5 minutes
    healthCheckMs = 30000;   # 30 seconds
    spareConnections = 5;
  };

  # Rate limit configuration for load tests
  # Increased to allow throughput testing
  rateLimitConfig = {
    requestsPerMinute = 500;  # 5x normal limit
    windowSeconds = 60;
  };

  # Test scenario defaults
  scenarios = {
    quick = {
      duration = 30;
      workers = 3;
    };
    standard = {
      duration = 60;
      workers = 5;
    };
    extended = {
      duration = 600;
      workers = 10;
    };
  };

  # Extrapolation targets for reporting
  extrapolation = {
    targetCpus = 8;
    targetMemoryGB = 16;
    scalingEfficiency = 0.85;
  };
}
