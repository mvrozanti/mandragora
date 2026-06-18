{ config, pkgs, lib, ... }:

let
  monitor-menu = pkgs.writeShellApplication {
    name = "monitor-menu";
    runtimeInputs = with pkgs; [ rofi libnotify ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../snippets/monitor-menu.py} "$@"
    '';
  };
in
{
  home.packages = [ monitor-menu ];
}
