{ config, lib, pkgs, ... }:

{
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.allowedUDPPorts = [ ];

  networking.firewall.extraCommands = ''
    iptables -N BareMetalInstanceServices 2>/dev/null || iptables -F BareMetalInstanceServices
    iptables -A OUTPUT -d 169.254.0.0/16 -j BareMetalInstanceServices

    iptables -A BareMetalInstanceServices -d 169.254.0.2/32 -p tcp -m owner --uid-owner 0 --dport 3260 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.2.0/24  -p tcp -m owner --uid-owner 0 --dport 3260 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.4.0/24  -p tcp -m owner --uid-owner 0 --dport 3260 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.5.0/24  -p tcp -m owner --uid-owner 0 --dport 3260 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.0.2/32  -p tcp --dport 80 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.169.254/32 -p udp --dport 53 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.169.254/32 -p tcp --dport 53 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.0.3/32  -p tcp -m owner --uid-owner 0 --dport 80 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.0.4/32  -p tcp --dport 80 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.169.254/32 -p tcp --dport 80 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.169.254/32 -p udp --dport 67 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.169.254/32 -p udp --dport 69 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.169.254/32 -p udp --dport 123 -j ACCEPT
    iptables -A BareMetalInstanceServices -d 169.254.0.0/16 -p tcp -j REJECT --reject-with tcp-reset
    iptables -A BareMetalInstanceServices -d 169.254.0.0/16 -p udp -j REJECT --reject-with icmp-port-unreachable
  '';

  networking.firewall.extraStopCommands = ''
    iptables -D OUTPUT -d 169.254.0.0/16 -j BareMetalInstanceServices 2>/dev/null || true
    iptables -F BareMetalInstanceServices 2>/dev/null || true
    iptables -X BareMetalInstanceServices 2>/dev/null || true
  '';

  services.openiscsi = {
    enable = true;
    name = "iqn.1988-12.com.oracle:mandragora-vps";
  };

  services.chrony.enable = true;

  services.qemuGuest.enable = lib.mkDefault true;
}
