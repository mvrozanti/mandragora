{ pkgs, ... }:

let
  src = ../../hosts/mandragora-phone/bridge/server.py;
  servicesJson = ../../hosts/mandragora-vps/compose/hub/static/services.json;
  tailnetJson = ../../snippets/tailnet.json;
  phoneMedia = pkgs.writeShellApplication {
    name = "phone-media";
    runtimeInputs = [
      pkgs.python3
      pkgs.imagemagick
    ];
    runtimeEnv.PHONE_MEDIA_FONT = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf";
    text = ''
      exec python3 ${../../../.local/bin/phone-media.py} "$@"
    '';
  };
in
{
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 6600 ];

  environment.systemPackages = [ phoneMedia ];

  mandragora.hub.services.phone-bridge = {
    port = 6688;
    userService = true;
    systemd = {
      description = "phone-bridge — config, desktop volume, playback lease and lyrics for the phone over the tailnet";
      wantedBy = [ "default.target" ];
      after = [ "mpd.service" ];
      restartTriggers = [ (builtins.readFile src) ];
      path = [
        pkgs.wireplumber
        pkgs.playerctl
      ];
      environment = {
        PHONE_BRIDGE_HOST = "0.0.0.0";
        PHONE_BRIDGE_PORT = "6688";
        PHONE_BRIDGE_MUSIC_DIR = "/home/m/Music";
        PHONE_BRIDGE_STATE = "/home/m/.local/state/phone-bridge";
        PHONE_BRIDGE_APP_DIR = "/home/m/.local/share/mandragora-phone/app";
        PHONE_BRIDGE_SERVICES_JSON = "${servicesJson}";
        PHONE_BRIDGE_TAILNET_JSON = "${tailnetJson}";
        PHONE_BRIDGE_OPENCODE_PASSWORD = "/home/m/.local/state/opencode/server-password";
        PHONE_BRIDGE_CLAUDE_PASSWORD = "/home/m/.local/state/claude-bridge/server-password";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
        MemoryMax = "128M";
        CPUWeight = 1000;
        IOWeight = 1000;
      };
    };
  };
}
