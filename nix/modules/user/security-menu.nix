{ pkgs, ... }:

let
  security-menu = pkgs.writeShellApplication {
    name = "security-menu";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../snippets/security-menu.py} "$@"
    '';
    runtimeInputs = with pkgs; [
      rofi
      libnotify
      xdg-utils
      procps
      systemd
    ];
  };
in
{
  home.packages = [ security-menu ];
}
