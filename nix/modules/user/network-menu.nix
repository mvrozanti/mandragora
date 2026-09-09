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
      systemd
      iproute2
      curl
    ];
  };
in
{
  home.packages = [ network-menu ];
}
