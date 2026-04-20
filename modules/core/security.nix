{ config, pkgs, lib, ... }:

{
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
    logRefusedConnections = false;
  };

  networking.networkmanager.dns = "systemd-resolved";

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNS = "1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com";
        FallbackDNS = "9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net";
        DNSOverTLS = "yes";
        DNSSEC = "allow-downgrade";
        LLMNR = "false";
        Domains = "~.";
      };
    };
  };

  services.openssh = {
    enable = false;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
      AllowUsers = [ "m" ];
      MaxAuthTries = 3;
      LoginGraceTime = 20;
    };
  };

  security.sudo = {
    execWheelOnly = true;
    extraConfig = builtins.readFile ../../snippets/sudo.conf;
    extraRules = [{
      users = [ "m" ];
      commands = [{
        command = "/run/current-system/sw/bin/nixos-rebuild";
        options = [ "NOPASSWD" ];
      }];
    }];
  };

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "net.core.bpf_jit_harden" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "kernel.yama.ptrace_scope" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
  };
}
