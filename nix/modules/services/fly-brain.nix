{ lib, pkgs, ... }:

let
  repo = "/home/m/Projects/fly-brain";
  shell =
    cmd:
    pkgs.writeShellScript "fly-brain-${cmd.name}" ''
      export PATH=${
        lib.makeBinPath [
          pkgs.nix
          pkgs.git
          pkgs.coreutils
          pkgs.bash
        ]
      }:$PATH
      export HOME=/home/m
      cd ${repo}
      exec nix develop --command ${cmd.run}
    '';
  daemon = shell {
    name = "daemon";
    run =
      "python -m flybrain.brain_server --socket /tmp/fly-brain.sock "
      + "--device cuda --idle-timeout 900";
  };
  web = shell {
    name = "web";
    run = "python app.py";
  };
in
{
  systemd.user.services.fly-brain = {
    description =
      "flybrain resident MaleCNS connectome daemon. Started on demand, NOT "
      + "at boot: it holds ~2.1 GB of VRAM for as long as it runs and "
      + "training peaks at 14.5 GB on a 16 GB card, so autostarting it would "
      + "break every GPU run. `systemctl --user start fly-brain` when using "
      + "the panel. Speaks over a unix socket, so it opens no port. It also "
      + "exits by itself after 15 minutes with no request, releasing the GPU; "
      + "the web panel starts it again on the next request, so the unload is "
      + "just a slower first call rather than something to notice.";
    unitConfig.ConditionUser = "m";
    serviceConfig = {
      WorkingDirectory = repo;
      Environment = [ "HOME=/home/m" ];
      ExecStart = "${daemon}";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "600s";
    };
  };

  mandragora.hub.services.flybrain-web = {
    port = 8097;
    userService = true;
    maxRuntime = "6h";
    systemd = {
      description =
        "flybrain web panel (tailnet bind, public via Caddy at fly.mvr.ac). "
        + "Stateless and cheap to restart; it proxies to the fly-brain "
        + "daemon over a unix socket and renders a shaped offline state, "
        + "naming the start command, whenever that daemon is down.";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        WorkingDirectory = repo;
        Environment = [
          "PORT=8097"
          "BIND=0.0.0.0"
          "HOME=/home/m"
          "FLY_BRAIN_AUTOSTART=1"
        ];
        ExecStart = "${web}";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "300s";
      };
    };
  };
}
