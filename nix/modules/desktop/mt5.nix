{ config, lib, pkgs, ... }:

let
  bootstrap = pkgs.writeShellApplication {
    name = "mt5-bootstrap";
    runtimeInputs = [ pkgs.wineWowPackages.staging pkgs.winetricks pkgs.uv pkgs.curl ];
    text = builtins.readFile ../../../.local/bin/mt5-bootstrap.sh;
  };
  server = pkgs.writeShellApplication {
    name = "mt5-server";
    runtimeInputs = [ pkgs.wineWowPackages.staging pkgs.uv ];
    text = builtins.readFile ../../../.local/bin/mt5-server.sh;
  };
in
{
  environment.systemPackages = [ bootstrap server ];
}
