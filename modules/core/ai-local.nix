{ config, pkgs, lib, ... }:

let
  mkPythonBin = name: src:
    pkgs.stdenv.mkDerivation {
      inherit name;
      src = src;
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/bin
        echo "#!${pkgs.python3}/bin/python3" > $out/bin/${name}
        cat $src >> $out/bin/${name}
        chmod +x $out/bin/${name}
      '';
    };

  gemma = mkPythonBin "gemma" ../../.local/bin/gemma.py;
  local-ai-mcp-server = mkPythonBin "local-ai-mcp-server" ../../.local/bin/local-ai-mcp-server.py;
in

{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  environment.systemPackages = [
    pkgs.oterm
    gemma
    local-ai-mcp-server
  ];
}
