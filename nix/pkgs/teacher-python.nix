{ pkgs }:

pkgs.python3.withPackages (p: [
  p.mcp
  p.python-dotenv
])
