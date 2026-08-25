{ pkgs, ... }:

{
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8173 ];

  systemd.user.services.lenia-bridge = {
    description = "Lenia static server and MPD reactivity bridge";
    wantedBy = [ "default.target" ];
    after = [ "network.target" "mpd.service" ];

    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 /home/m/Projects/lenia-experiments/serve.py --port 8173 --bind 0.0.0.0";
      WorkingDirectory = "/home/m/Projects/lenia-experiments";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
