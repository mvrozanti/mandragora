{ config, lib, pkgs, ... }:

{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--ssh"
      "--accept-dns=false"
    ];
  };

  sops.secrets."tailscale/auth-key" = {
    sopsFile = ../../secrets/secrets.yaml;
  };

  systemd.services.tailscale-autoconnect = {
    description = "Bring tailscaled up with sops-provided auth key";
    after = [ "tailscaled.service" "network-online.target" ];
    wants = [ "tailscaled.service" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      status=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null || true)
      if echo "$status" | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null; then
        exit 0
      fi
      ${pkgs.tailscale}/bin/tailscale up \
        --authkey "$(cat ${config.sops.secrets."tailscale/auth-key".path})" \
        --ssh \
        --accept-dns=false
    '';
    path = [ pkgs.tailscale pkgs.jq ];
  };
}
