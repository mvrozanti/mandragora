{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mandragora.voiceAlterCore;
  voiceAlterPkg = pkgs.callPackage ../../pkgs/voice-alter-core.nix { };
  supervisor = import ../../pkgs/idle-socket-supervisor.nix { inherit pkgs; };
in
{
  options.mandragora.voiceAlterCore = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the voice.mvr.ac room relay: mic claim, synced settings, RVC bridge (port 8095, user service).";
    };
    listenHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Loopback address voice-alter-core binds behind the 8095 socket.";
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
        {
          factory = "adapter";
          args = {
            "factory.name" = "support.null-audio-sink";
            "node.name" = "RvcOut";
            "node.description" = "RVC Output Sink";
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
              "node.passive" = true;
              "node.name" = "capture.vm_to_src";
              "target.object" = "RvcOut";
              "stream.capture.sink" = true;
            };
            "playback.props" = {
              "node.passive" = true;
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

    systemd.user.sockets.voice-alter-core = {
      description = "voice.mvr.ac room-relay socket — on-demand :8095";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "0.0.0.0:8095" ];
    };

    mandragora.hub.services.voice-alter-core = {
      maxRuntime = "12h";
      port = 8095;
      userService = true;
      systemd = {
        description = "voice.mvr.ac — real-time voice-changer AI backend";
        after = [ "voice-alter-core.socket" ];
        requires = [ "voice-alter-core.socket" ];
        environment = {
          VOICE_ALTER_LISTEN_HOST = cfg.listenHost;
          VOICE_ALTER_LISTEN_PORT = "18095";
          VOICE_ALTER_RVC_WS = "ws://127.0.0.1:8098/ws";
          VOICE_ALTER_RVC_HEALTH = "http://127.0.0.1:8098/healthz";
          UPSTREAM_ADDR = "127.0.0.1";
          UPSTREAM_PORT = "18095";
          IDLE_TIMEOUT = "600";
          STARTUP_TIMEOUT = "300";
        };
        serviceConfig = {
          ExecStart = "${supervisor}/bin/idle-socket-supervisor ${voiceAlterPkg}/bin/voice-alter-core";
          StateDirectory = "voice-alter-core";
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
