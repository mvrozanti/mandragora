{ config, pkgs, lib, ... }:

let
  cfg = config.services.mandragora-seafile;

  serverUrl = "http://100.84.78.83";
  serverEmail = "mvrozanti@hotmail.com";
  seafDataParent = "/home/m/.seaf";

  syncMap = {
    Videos    = "d563b844-5b5f-4927-b5f0-ff391b868c89";
    Music     = "36908347-7384-455e-8982-ec4fae50ed1c";
    Documents = "465499b0-1761-464b-a93a-7c54cd8d11cd";
    Downloads = "37fde89c-7afc-4ee9-b309-53472d4dc644";
    Pictures  = "74ed850a-9568-49b4-9274-f822b20be5e7";
    Desktop   = "a16ec8f2-1740-4469-8327-a65ec5dcb78b";
  };

  syncLines = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: id: ''
    seaf-cli desync -d "$HOME/${name}" >/dev/null 2>&1 || true
    echo "[sync] ${name} <- ${id}"
    seaf-cli sync -l "${id}" -s "${serverUrl}" -u "${serverEmail}" -p "$SF_PW" -d "$HOME/${name}"
  '') syncMap);

  onboard = pkgs.writeShellScriptBin "seaf-onboard" ''
    set -euo pipefail

    if [ ! -d "${seafDataParent}/seafile-data" ]; then
      echo "==> seaf-cli init -d ${seafDataParent}"
      mkdir -p "${seafDataParent}"
      ${pkgs.seafile-shared}/bin/seaf-cli init -d "${seafDataParent}"
    fi

    if ! ${pkgs.seafile-shared}/bin/seaf-cli status >/dev/null 2>&1; then
      echo "==> starting seaf-cli daemon"
      ${pkgs.seafile-shared}/bin/seaf-cli start
      sleep 2
    fi

    if [ -z "''${SF_PW:-}" ]; then
      echo -n "Seafile password for ${serverEmail}: "
      read -rs SF_PW
      echo
    fi
    export SF_PW

    export PATH="${pkgs.seafile-shared}/bin:$PATH"
    ${syncLines}
    unset SF_PW

    echo
    echo "==> current sync state:"
    ${pkgs.seafile-shared}/bin/seaf-cli status
  '';
in
{
  options.services.mandragora-seafile.enable = lib.mkEnableOption "Seafile sync client daemon";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.seafile-shared pkgs.seafile-client onboard ];

    systemd.user.services.seafile-daemon = {
      description = "Seafile client daemon";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      unitConfig.ConditionPathIsDirectory = "%h/.seaf/seafile-data";
      serviceConfig = {
        Type = "forking";
        PIDFile = "%h/.seaf/seafile-data/seafile.pid";
        ExecStart = "${pkgs.seafile-shared}/bin/seaf-cli start";
        ExecStop = "${pkgs.seafile-shared}/bin/seaf-cli stop";
        Restart = "on-failure";
        RestartSec = "30s";
      };
      unitConfig.StartLimitIntervalSec = "5min";
      unitConfig.StartLimitBurst = 3;
    };
  };
}
