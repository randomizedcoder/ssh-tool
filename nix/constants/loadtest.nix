# nix/constants/loadtest.nix
#
# Load testing configuration for SSH-Tool MicroVM infrastructure.
# Defines resource profiles and test parameters.
#
{
  # VM resource profiles for load testing (deprecated - use resources.nix instead)
  # Kept for backwards compatibility
  vmResources = (import ./resources.nix).profiles.loadtest;

  # Pool configuration for load tests
  # Increased limits to allow higher concurrency testing
  poolConfig = {
    maxConnections = 20;
    idleTimeoutMs = 300000; # 5 minutes
    healthCheckMs = 30000; # 30 seconds
    spareConnections = 5;
  };

  # Rate limit configuration for load tests
  # Increased to allow throughput testing
  rateLimitConfig = {
    requestsPerMinute = 500; # 5x normal limit
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
