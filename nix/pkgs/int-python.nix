{ pkgs }:

pkgs.python3.withPackages (p: [
  p.flask
  p.requests
  p.beautifulsoup4
  p.langdetect
])
