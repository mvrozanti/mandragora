{ lib, pkgs, ... }:

let
  repo = "/home/m/Projects/slither-io-simulator";
  launcher = pkgs.writeShellScript "fly-brain-serve" ''
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
    exec nix develop --command python -m slither_gym.policies.connectome.brain_server \
      --socket /tmp/fly-brain.sock --device cuda
  '';
in
{
  systemd.user.services.fly-brain = {
    description =
      "Resident MaleCNS connectome daemon for the fly brain panel. "
      + "Started on demand, NOT at boot: it holds ~2.1 GB of VRAM for as "
      + "long as it runs, and training peaks at 14.5 GB on a 16 GB card, "
      + "so an always-on daemon would break every training run. Start it "
      + "with `systemctl --user start fly-brain` when using the panel and "
      + "stop it afterwards. serve.py reaches it over the unix socket, so "
      + "no TCP port is opened and it needs no hub-services entry.";
    unitConfig.ConditionUser = "m";
    serviceConfig = {
      WorkingDirectory = repo;
      Environment = [ "HOME=/home/m" ];
      ExecStart = "${launcher}";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "600s";
    };
  };
}
