{ config, pkgs, lib, ... }:

let
  cfg = config.services.mandragora-seafile;
in
{
  options.services.mandragora-seafile.enable = lib.mkEnableOption "Seafile sync client daemon";

  config = lib.mkIf cfg.enable {
    # TODO: Add to secrets.yaml before enabling:
    #   sops.secrets."seafile/auth-token" = { owner = "m"; };
    # Then run once interactively as m:
    #   seaf-cli init -d ~/Seafile
    #   seaf-cli config -S <server-url> -u <email> -k <auth-token>
    # And add desired library syncs:
    #   seaf-cli sync -l <library-id> -s <server-url> -u <email> -k <token> -d ~/Seafile/<dir>
    # TODO: Replace <server-url> with the arch-slave Seafile address when available.

    environment.systemPackages = [ pkgs.seafile-client ];

    systemd.user.services.seafile-daemon = {
      description = "Seafile client daemon";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        # seaf-cli start forks seaf-daemon and exits; PIDFile lets systemd track the child.
        # The default PID file location for seaf-cli is ~/.seaf/seafile.pid — verify on first run.
        Type = "forking";
        PIDFile = "%h/.seaf/seafile.pid";
        ExecStart = "${pkgs.seafile-client}/bin/seaf-cli start";
        ExecStop = "${pkgs.seafile-client}/bin/seaf-cli stop";
        Restart = "on-failure";
        RestartSec = "30s";
        # Cap restart attempts to avoid log spam if seaf-cli init was never run
        StartLimitIntervalSec = "5min";
        StartLimitBurst = 3;
      };
    };
  };
}
