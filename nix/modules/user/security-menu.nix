{ config, pkgs, lib, ... }:

let
  security-menu = pkgs.writeShellApplication {
    name = "security-menu";
    runtimeInputs = with pkgs; [ rofi libnotify xdg-utils procps systemd ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../snippets/security-menu.py} "$@"
    '';
  };
in
{
  home.packages = [ security-menu ];
}
