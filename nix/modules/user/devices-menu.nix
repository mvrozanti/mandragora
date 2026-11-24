{ pkgs, ... }:

let
  devices-menu = pkgs.writeShellApplication {
    name = "devices-menu";
    text = ''
      export DEVICES_TAILNET=${../../snippets/tailnet.json}
      exec ${pkgs.python3}/bin/python3 ${../../snippets/devices-menu.py} "$@"
    '';
    runtimeInputs = with pkgs; [
      tailscale
      openssh
      util-linux
      pulseaudio
      systemd
    ];
  };
in
{
  home.packages = [ devices-menu ];
}
