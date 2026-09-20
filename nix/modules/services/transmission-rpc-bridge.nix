{ pkgs, ... }:
let
  bridgePort = 6687;
  rpcAddress = "127.0.0.1:9091";
in
{
  mandragora.hub.services.transmission-rpc = {
    port = bridgePort;
    userService = true;
    systemd = {
      description = "transmission RPC tailnet bridge (:${toString bridgePort} -> ${rpcAddress}, caddy-only)";
      after = [
        "network.target"
        "transmission.service"
      ];
      wants = [ "transmission.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString bridgePort},reuseaddr,fork,keepalive TCP:${rpcAddress}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
