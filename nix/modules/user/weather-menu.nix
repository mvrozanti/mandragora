{ pkgs, ... }:

let
  pyEnv = pkgs.python3.withPackages (ps: with ps; [ requests ]);

  weather-menu = pkgs.writeShellApplication {
    name = "weather-menu";
    runtimeInputs = with pkgs; [
      rofi
      libnotify
    ];
    text = ''
      exec ${pyEnv}/bin/python3 ${../../snippets/weather-menu.py} "$@"
    '';
  };
in
{
  home.packages = [ weather-menu ];
}
