{ pkgs, ... }:

let
  netPrefer = pkgs.writeShellApplication {
    name = "net-prefer";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../../snippets/net-prefer.sh;
  };
in
{
  environment.systemPackages = [ netPrefer ];

  security.sudo.extraRules = [
    {
      users = [ "m" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/net-prefer";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  boot.kernel.sysctl = {
    "net.ipv4.conf.enp8s0.rp_filter" = 2;
    "net.ipv4.conf.wlan0.rp_filter" = 2;
  };

  systemd.services.net-failover = {
    description = "Uplink failover: prefer LAN, fall back to Wi-Fi hotspot when LAN loses internet";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [
      pkgs.iproute2
      pkgs.iputils
      pkgs.util-linux
      pkgs.gawk
      pkgs.gnugrep
      pkgs.coreutils
    ];
    serviceConfig = {
      Restart = "always";
      RestartSec = "5";
      RuntimeDirectory = "net-failover";
      RuntimeDirectoryPreserve = "yes";
    };
    script = builtins.readFile ../../snippets/net-failover.sh;
  };
}
