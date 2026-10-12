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
    memoryMax = "6G";
    systemd = {
      description =
        "vj rater core (tailnet bind, public via Caddy at vj.mvr.ac). "
        + "Serves the Deck, the sample API and the clips, and runs the "
        + "render worker that keeps six unrated clips ready: it plans "
        + "candidates from grammar G_v1, renders them through "
        + "generative-art-playground under gpu-lock, and muxes the audio "
        + "window. When the GPU is held by someone else it waits a minute "
        + "and retries; the page shows why nothing is ready.";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      unitConfig.ConditionPathExists = "/dev/nvidia0";
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
