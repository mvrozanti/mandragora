{ pkgs, ... }:

let
  cage = pkgs.writeShellApplication {
    name = "cage";
    runtimeInputs = [ pkgs.systemd ];
    text = builtins.readFile ../../../.local/bin/cage.sh;
  };
in
{
  systemd.user.slices.heavy = {
    description = "Capped slice for heavy interactive jobs (builds, training) launched via cage; dies before the desktop spine";
    sliceConfig = {
      MemoryHigh = "16G";
      MemoryMax = "20G";
      ManagedOOMMemoryPressure = "kill";
    };
  };

  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "20G";
    MemoryMax = "24G";
  };

  systemd.user.units."tmux-spawn-.scope" = {
    overrideStrategy = "asDropin";
    text = builtins.readFile ../../../.config/systemd/user/interactive-scope.conf;
  };

  systemd.user.units."kitty-.scope" = {
    overrideStrategy = "asDropin";
    text = builtins.readFile ../../../.config/systemd/user/interactive-scope.conf;
  };

  environment.systemPackages = [ cage ];
}
