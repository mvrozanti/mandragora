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
  headless = pkgs.writeShellApplication {
    name = "mt5-headless";
    runtimeInputs = [ pkgs.wineWowPackages.staging pkgs.xorg.xvfb pkgs.coreutils ];
    text = builtins.readFile ../../../.local/bin/mt5-headless.sh;
  };
in
{
  environment.systemPackages = [ bootstrap server headless ];

  systemd.user.services.mt5 = {
    description = "Headless MT5 terminal + mt5linux rpyc bridge";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${headless}/bin/mt5-headless";
      Restart = "always";
      RestartSec = "30";
      TimeoutStopSec = "20";
    };
  };
}
