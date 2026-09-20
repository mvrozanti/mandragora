{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mandragora.voiceAlterCore;
  voiceAlterPkg = pkgs.callPackage ../../pkgs/voice-alter-core.nix { };
in
{
  options.mandragora.voiceAlterCore = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the voice.mvr.ac real-time voice-changer AI backend (port 8095, user service).";
    };
    listenHost = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address voice-alter-core binds; the tailscale0-only firewall keeps port 8095 off the LAN/public net.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.pipewire.extraConfig.pipewire."52-voice-morph-virtmic" = {
      "context.objects" = [
        {
          factory = "adapter";
          args = {
            "factory.name" = "support.null-audio-sink";
            "node.name" = "VoiceMorph";
            "node.description" = "Voice Morph Sink";
            "media.class" = "Audio/Sink";
            "audio.position" = [
              "FL"
              "FR"
            ];
          };
        }
      ];

      "context.modules" = [
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "Voice Morph source";
            "capture.props" = {
              "node.name" = "capture.vm_to_src";
              "target.object" = "VoiceMorph";
              "stream.capture.sink" = true;
            };
            "playback.props" = {
              "node.name" = "VoiceMorphSource";
              "node.description" = "Voice Morph Source";
              "media.class" = "Audio/Source";
              "audio.position" = [
                "FL"
                "FR"
              ];
            };
          };
        }
      ];
    };

    mandragora.hub.services.voice-alter-core = {
      port = 8095;
      userService = true;
      systemd = {
        description = "voice.mvr.ac — real-time voice-changer AI backend";
        wantedBy = [ "default.target" ];
        after = [ "default.target" ];
        environment = {
          VOICE_ALTER_LISTEN_HOST = cfg.listenHost;
          VOICE_ALTER_LISTEN_PORT = "8095";
        };
        serviceConfig = {
          ExecStart = "${voiceAlterPkg}/bin/voice-alter-core";
          Restart = "on-failure";
          RestartSec = "5s";
          ProtectHome = false;
          PrivateTmp = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
          MemoryMax = "2G";
          OOMScoreAdjust = 200;
        };
      };
    };
  };
}
