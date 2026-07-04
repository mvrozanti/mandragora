{ pkgs, ... }:

let
  gpu-menu = pkgs.writeShellApplication {
    name = "gpu-menu";
    runtimeInputs = with pkgs; [ rofi libnotify procps ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../snippets/gpu-menu.py} "$@"
    '';
  };
in
{
  home.packages = [ gpu-menu ];
}
