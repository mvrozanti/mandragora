{ pkgs, osConfig, ... }:

let
  money-menu = pkgs.writeShellApplication {
    name = "money-menu";
    runtimeInputs = with pkgs; [
      rofi
      procps
    ];
    text = ''
      export MONEY_XPUB_FILES="${osConfig.sops.secrets."bitcoin/jade_xpub".path}:${
        osConfig.sops.secrets."bitcoin/electrum_xpub1".path
      }:${osConfig.sops.secrets."bitcoin/electrum_xpub2".path}:${
        osConfig.sops.secrets."bitcoin/electrum_xpub3".path
      }"
      export MONEY_XPUB_LABELS="jade:electrum1:electrum2:electrum3"
      export MONEY_BINANCE_KEY_FILE="${osConfig.sops.secrets."binance/api_key".path}"
      export MONEY_BINANCE_SECRET_FILE="${osConfig.sops.secrets."binance/secret_key".path}"
      export MONEY_LENDED_FILE="${osConfig.sops.secrets."bitcoin/lended_sats".path}"
      export MONEY_EVM_ADDRESS_FILE="${osConfig.sops.secrets."evm/address".path}"
      exec ${pkgs.python3}/bin/python3 ${../../snippets/money-menu.py} "$@"
    '';
  };
in
{
  home.packages = [ money-menu ];

  systemd.user.services.money-menu-refresh = {
    Unit = {
      Description = "Fetch balances and prices for the waybar money-menu";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${money-menu}/bin/money-menu refresh";
      Nice = 10;
    };
  };

  systemd.user.timers.money-menu-refresh = {
    Unit = {
      Description = "Periodic balance refresh for the waybar money-menu";
    };
    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "15min";
      RandomizedDelaySec = "60s";
      Persistent = false;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
