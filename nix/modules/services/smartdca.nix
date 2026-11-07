{ pkgs, ... }:

let
  repo = "/home/m/Projects/smartdca";
in
{
  mandragora.hub.services.smartdca-web = {
    port = 8435;
    userService = true;
    memoryMax = "512M";
    systemd = {
      description =
        "smartdca payday oracle (tailnet bind, public via Caddy at smartdca.mvr.ac behind Authelia). "
        + "Feeds the paycheck on the 1st and 15th through six fixed BTC/CDB rules since 2015 and "
        + "answers each payday with the rule that has made the most reais; refreshes prices every 3 h.";
      after = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        WorkingDirectory = repo;
        Environment = [ "HOME=/home/m" ];
        ExecStart = "${pkgs.python3}/bin/python3 -m smartdca serve --bind 0.0.0.0 --port 8435";
        Restart = "on-failure";
        RestartSec = "10s";
        MemorySwapMax = "0";
      };
    };
  };
}
