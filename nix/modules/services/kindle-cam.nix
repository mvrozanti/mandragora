{ pkgs, ... }:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
  src = ../../../.local/share/kindle-cam/kindle_cam.py;
  port = 6686;
in
{
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];

  systemd.services.kindle-cam = {
    description = "kindle-cam — DroidCam frames transcoded to e-ink JPEG for the Paperwhite";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [ "network-online.target" ];
    restartTriggers = [ (builtins.readFile src) ];

    environment = {
      KINDLE_CAM_HOST = "0.0.0.0";
      KINDLE_CAM_PORT = toString port;
      KINDLE_CAM_SOURCE = "http://${tailnet.phone.ip}:4747/video";
      KINDLE_CAM_WIDTH = "1272";
      KINDLE_CAM_HEIGHT = "1696";
      KINDLE_CAM_FPS = "4";
      KINDLE_CAM_QUALITY = "6";
      KINDLE_CAM_ROTATE = "0";
      FFMPEG = "${pkgs.ffmpeg}/bin/ffmpeg";
    };

    serviceConfig = {
      Type = "simple";
      User = "m";
      Group = "users";
      ExecStart = "${pkgs.python3}/bin/python3 ${src}";
      Restart = "always";
      RestartSec = "5s";
      MemoryMax = "256M";
    };
  };
}
