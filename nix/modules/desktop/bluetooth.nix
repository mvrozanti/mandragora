{ pkgs, lib, ... }:
{
  boot.extraModprobeConfig = builtins.readFile ../../snippets/bluetooth-modprobe.conf;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        ControllerMode = "dual";
        Experimental = true;
      };
      Policy = {
        AutoEnable = true;
        ReconnectAttempts = 7;
        ReconnectIntervals = "1,2,4,8,16,32,64";
      };
    };
  };

  systemd.services.bt-autoconnect-jbl = {
    description = "Auto-connect the trusted JBL Wave Beam 2 when present";
    after = [ "bluetooth.service" ];
    wants = [ "bluetooth.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.bluez ];
    serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash ${../../snippets/bt-autoconnect.sh}";
      Restart = "always";
      RestartSec = 10;
    };
  };

  # Use a simpler WirePlumber config that doesn't restrict roles or codecs unless needed
  services.pipewire.wireplumber.extraConfig."10-bluez-clean" = {
    "monitor.bluez.properties" = {
      "bluez5.enable-hw-volume" = false;
    };
  };

  services.pipewire.wireplumber.extraConfig."11-bluez-priority" = {
    "monitor.bluez.rules" = [
      {
        matches = [ { "node.name" = "~bluez_output.*"; } ];
        actions.update-props = {
          "priority.session" = 2000;
          "priority.driver" = 2000;
        };
      }
    ];
  };

  services.pipewire.wireplumber.extraConfig."12-follow-default" = {
    "wireplumber.settings" = {
      "node.stream.restore-target" = false;
    };
  };

  services.blueman.enable = true;

  systemd.user.services.blueman-applet.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    bluez
    bluez-tools
  ];
}
