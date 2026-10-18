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
        + "Serves duels at / (two versions of the creature's code on the "
        + "same analysed 8-bar window, mix and knobs; one answer ranks the "
        + "lineage), the single-picture rater at /rate (one of ten media, a "
        + "weight mix over ten rhythm readings, three-axis judgements that "
        + "retrain the per-axis critic every five from twenty and steer the "
        + "next mixes, knobs and medium), the motion gate at /motion that "
        + "refuses a child genome which only changes shading, and /insight. "
        + "Cuts each audio excerpt on demand. No GPU work: the engine clip "
        + "worker is off by default.";
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
