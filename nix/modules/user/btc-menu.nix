{ pkgs, osConfig, ... }:

let
  btc-menu = pkgs.writeShellApplication {
    name = "btc-menu";
    runtimeInputs = with pkgs; [
      rofi
      procps
    ];
    text = ''
      export BTC_XPUB_FILES="${osConfig.sops.secrets."bitcoin/jade_xpub".path}:${
        osConfig.sops.secrets."bitcoin/electrum_xpub1".path
      }:${osConfig.sops.secrets."bitcoin/electrum_xpub2".path}:${
        osConfig.sops.secrets."bitcoin/electrum_xpub3".path
      }"
      export BTC_XPUB_LABELS="jade:electrum1:electrum2:electrum3"
      export BTC_BINANCE_KEY_FILE="${osConfig.sops.secrets."binance/api_key".path}"
      export BTC_BINANCE_SECRET_FILE="${osConfig.sops.secrets."binance/secret_key".path}"
      export BTC_LENDED_FILE="${osConfig.sops.secrets."bitcoin/lended_sats".path}"
      exec ${pkgs.python3}/bin/python3 ${../../snippets/btc-menu.py} "$@"
    '';
  };
in
{
  home.packages = [ btc-menu ];

  systemd.user.services.btc-menu-refresh = {
    Unit = {
      Description = "Fetch bitcoin balances and prices for waybar btc-menu";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${btc-menu}/bin/btc-menu refresh";
      Nice = 10;
    };
  };

  systemd.user.timers.btc-menu-refresh = {
    Unit = {
      Description = "Periodic bitcoin balance refresh for waybar btc-menu";
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
