{ pkgs, ... }:

let
  network-menu = pkgs.writeShellApplication {
    name = "network-menu";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../snippets/network-menu.py} "$@"
    '';
    runtimeInputs = with pkgs; [
      rofi
      libnotify
      iwd
      iproute2
      iputils
    ];
  };
in
{
  home.packages = [ network-menu ];
}
