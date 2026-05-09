{ config, lib, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.ttyd ];

  mandragora.hub.services.ttyd = {
    port = 7681;
    systemd = {
      description = "ttyd web shell (tailnet-only)";
      after = [ "network.target" "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "m";
        Group = "users";
        WorkingDirectory = "/home/m";
        ExecStart = "${pkgs.ttyd}/bin/ttyd -p 7681 -W ${pkgs.zsh}/bin/zsh -l";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
