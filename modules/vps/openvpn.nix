{ config, lib, pkgs, ... }:

{
  sops.secrets = {
    "openvpn/ca-key" = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "root";
      mode = "0400";
    };
    "openvpn/server-key" = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "root";
      mode = "0400";
    };
    "openvpn/tls-crypt-key" = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "root";
      mode = "0400";
    };
  };

  environment.etc = {
    "openvpn/ca.crt".source = ./files/openvpn/ca.crt;
    "openvpn/server.crt".source = ./files/openvpn/server.crt;
    "openvpn/crl.pem".source = ./files/openvpn/crl.pem;
  };

  services.openvpn.servers.mandragora = {
    config = ''
      ${builtins.readFile ./files/openvpn/server.conf}

      ca   /etc/openvpn/ca.crt
      cert /etc/openvpn/server.crt
      key  ${config.sops.secrets."openvpn/server-key".path}
      tls-crypt ${config.sops.secrets."openvpn/tls-crypt-key".path}
      crl-verify /etc/openvpn/crl.pem
    '';
    autoStart = true;
  };

  networking.firewall = {
    allowedTCPPorts = [ 1194 ];
    allowedUDPPorts = [ 1194 ];
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.nat = {
    enable = true;
    externalInterface = "enp0s6";
    internalInterfaces = [ "tun0" ];
  };
}
