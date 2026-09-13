{ pkgs, ... }:

let
  pyEnv = pkgs.python3.withPackages (ps: [
    ps.numpy
    ps.pillow
  ]);
  src = ../../hosts/mandragora-kindle/vis/server.py;
  port = 6612;
in
{
  systemd.services.mandragora-mpd-vis = {
    description = "mandragora-mpd-vis — MPD spectrum bands and dithered cover art for mandragora-kindle";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ (builtins.readFile ../../hosts/mandragora-kindle/vis/server.py) ];
    environment = {
      MPD_VIS_FIFO = "/tmp/mpd.fifo";
      MPD_VIS_BIND = "0.0.0.0";
      MPD_VIS_PORT = toString port;
      MPD_VIS_MPD_HOST = "127.0.0.1";
      MPD_VIS_MPD_PORT = "6600";
      MPD_VIS_BANDS = "48";
      MPD_VIS_FPS = "10";
      MPD_VIS_RATE = "44100";
    };
    serviceConfig = {
      Type = "simple";
      User = "m";
      Group = "users";
      ExecStart = "${pyEnv}/bin/python3 ${src}";
      Restart = "always";
      RestartSec = "5s";
      MemoryMax = "256M";
      Nice = 5;
    };
  };

  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [ port ];
}
