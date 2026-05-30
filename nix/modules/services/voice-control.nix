{ config, lib, pkgs, ... }:

let
  srcDir = pkgs.runCommandLocal "voice-control-src" {} ''
    mkdir -p $out
    cp ${../../../.local/share/voice-control/main.py} $out/main.py
    cp -r ${../../../.local/share/voice-control/static} $out/static
  '';
  src = "${srcDir}/main.py";
  staticDir = "${srcDir}/static";
  pyEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);

  presetNames = [
    "voice-bypass.json"
    "voice-deeper.json"
    "voice-higher.json"
    "voice-anime.json"
    "voice-demon.json"
    "voice-robot.json"
    "voice-radio.json"
    "voice-helium.json"
    "voice-broadcast.json"
  ];

  presetsRepoDir = ../../../.config/easyeffects/input;

  pipewireDrop = pkgs.writeTextDir
    "share/pipewire/pipewire.conf.d/10-voice-virtual-mic.conf"
    (builtins.readFile ../../../.config/pipewire/pipewire.conf.d/10-voice-virtual-mic.conf);
in {
  services.pipewire.configPackages = [ pipewireDrop ];

  environment.systemPackages = [ pkgs.easyeffects ];

  home-manager.users.m = {
    services.easyeffects.enable = true;
    home.file = lib.listToAttrs (map
      (n: lib.nameValuePair ".config/easyeffects/input/${n}" {
        source = presetsRepoDir + "/${n}";
      })
      presetNames);
  };

  mandragora.hub.services.voice-control = {
    port = 8094;
    systemd = {
      description = "voice-control — EasyEffects preset switcher + web UI";
      after = [ "network.target" "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        VOICE_CONTROL_HOST = "0.0.0.0";
        VOICE_CONTROL_PORT = "8094";
        VOICE_CONTROL_STATIC_DIR = staticDir;
        VOICE_CONTROL_PRESETS_DIR = "/home/m/.config/easyeffects/input";
        VOICE_CONTROL_STATE_FILE = "/home/m/.local/state/voice-control/state.json";
        HOME = "/home/m";
        XDG_RUNTIME_DIR = "/run/user/1000";
        DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
      };
      path = [ pkgs.glib pkgs.easyeffects pkgs.systemd ];
      serviceConfig = {
        User = "m";
        Group = "users";
        ExecStart = "${pyEnv}/bin/python ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
