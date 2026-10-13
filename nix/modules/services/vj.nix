{ lib, pkgs, ... }:

let
  repo = "/home/m/Projects/vj";
  web = pkgs.writeShellScript "vj-web" ''
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
    exec nix develop --command python -m vj serve --port 8100 --bind 0.0.0.0
  '';
in
{
  mandragora.hub.services.vj-web = {
    port = 8100;
    userService = true;
    memoryMax = "3G";
    systemd = {
      description =
        "vj rater core (tailnet bind, public via Caddy at vj.mvr.ac). "
        + "Serves trials (an analysed 8-bar window, one of ten media, a "
        + "weight mix over ten rhythm readings) that the browser draws live, "
        + "cuts each audio excerpt on demand, stores the three-axis "
        + "judgements, retrains the per-axis critic every five from twenty, "
        + "steers the next mixes, media knobs and medium choice, and serves "
        + "/insight. No GPU work: the engine clip worker is off by default.";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        WorkingDirectory = repo;
        Environment = [
          "HOME=/home/m"
          "VJ_ENGINE_ROOT=/home/m/Projects/generative-art-playground"
        ];
        ExecStart = "${web}";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "600s";
        MemorySwapMax = "0";
      };
    };
  };
}
