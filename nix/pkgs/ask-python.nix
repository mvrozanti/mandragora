{ pkgs }:

pkgs.python3.withPackages (p: [
  p.httpx
  p.ddgs
  p.beautifulsoup4
  p.lxml
])
