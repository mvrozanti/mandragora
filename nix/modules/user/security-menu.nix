{ pkgs, ... }:

let
  security-menu = pkgs.writeShellApplication {
    name = "security-menu";
    text = ''
      VULN_NOISE=${../../hosts/mandragora-vps/compose/vuln/static/noise.json} exec ${pkgs.python3}/bin/python3 ${../../snippets/security-menu.py} "$@"
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
