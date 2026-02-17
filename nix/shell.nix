# nix/shell.nix
#
# Development shell for ssh-tool.
# Provides all tools needed for development and testing.
#
{ pkgs }:
let
  lib = pkgs.lib;

  # Expect with Tcl 9.0 support
  # TODO: Replace with pkgs.tclPackages_9_0.expect after PR #490930 merges
  expect-tcl9 = pkgs.callPackage ./expect-tcl9 { };
in
pkgs.mkShell {
  packages =
    with pkgs;
    [
      # Core dependencies (Tcl 9.0)
      expect-tcl9 # Expect with Tcl 9.0
      tcl-9_0 # TCL 9.0 runtime

      # Testing and linting tools
      shellcheck # Shell script linting
      tclint # TCL linting and formatting
      curl # HTTP client for MCP testing
      jq # JSON processing

      # Development tools
      git
      gnumake

      # Optional: debugging
      gdb
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      # Linux-specific tools
      strace
      ltrace
      sshpass # For automated SSH testing
    ];

  shellHook = ''
    echo "═══════════════════════════════════════════════════════════"
    echo "  SSH Automation Tool - Development Shell"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Available commands:"
    echo "  ./tests/run_all_tests.sh     - Run CLI mock tests"
    echo "  ./mcp/tests/run_all_tests.sh - Run MCP mock tests"
    echo "  ./tests/run_shellcheck.sh    - Lint shell scripts"
    echo ""
    echo "For MicroVM testing (Linux only):"
    echo "  nix build .#mcp-vm-debug     - Build MCP server VM"
    echo "  nix build .#ssh-target-vm-debug - Build SSH target VM"
    echo "  nix run .#ssh-test-all       - Run all test suites"
    echo ""
  '';

  # Set environment variables
  TCLSH = "${pkgs.tcl-9_0}/bin/tclsh9.0";
  EXPECT = "${expect-tcl9}/bin/expect";
}
