{ pkgs, ... }:

let
  soundboard = pkgs.writeShellApplication {
    name = "soundboard";
    runtimeInputs = with pkgs; [
      mpv
      rofi
      libnotify
      findutils
      coreutils
    ];
    text = builtins.readFile ../../../.local/bin/soundboard.sh;
  };

  soundboard-mic = pkgs.writeShellApplication {
    name = "soundboard-mic";
    runtimeInputs = with pkgs; [
      pulseaudio
      libnotify
    ];
    text = builtins.readFile ../../../.local/bin/soundboard-mic.sh;
  };
in
{
  environment.systemPackages = [
    soundboard
    soundboard-mic
  ];

  systemd.tmpfiles.rules = [
    "d /home/m/.local/share/soundboard 0755 m users -"
    "d /home/m/.local/share/soundboard/slots 0755 m users -"
  ];

  services.pipewire.extraConfig.pipewire."51-soundboard-virtmic" = {
    "context.objects" = [
      {
        factory = "adapter";
        args = {
          "factory.name" = "support.null-audio-sink";
          "node.name" = "Soundboard";
          "node.description" = "Soundboard";
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
          "node.name" = "VirtualMicBus";
          "node.description" = "Virtual Mic Bus";
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
          "node.description" = "Mic to VirtualMic";
          "capture.props" = {
            "node.name" = "capture.mic_to_virtmic";
            "target.object" = "alsa_input.pci-0000_10_00.6.analog-stereo";
          };
          "playback.props" = {
            "node.name" = "playback.mic_to_virtmic";
            "media.class" = "Stream/Output/Audio";
            "target.object" = "VirtualMicBus";
            "stream.dont-remix" = true;
          };
        };
      }
      {
        name = "libpipewire-module-loopback";
        args = {
          "node.description" = "Soundboard to VirtualMic";
          "capture.props" = {
            "node.name" = "capture.sb_to_virtmic";
            "target.object" = "Soundboard";
            "stream.capture.sink" = true;
          };
          "playback.props" = {
            "node.name" = "playback.sb_to_virtmic";
            "media.class" = "Stream/Output/Audio";
            "target.object" = "VirtualMicBus";
          };
        };
      }
      {
        name = "libpipewire-module-loopback";
        args = {
          "node.description" = "VirtualMic source";
          "capture.props" = {
            "node.name" = "capture.bus_to_virtmic";
            "target.object" = "VirtualMicBus";
            "stream.capture.sink" = true;
          };
          "playback.props" = {
            "node.name" = "VirtualMic";
            "node.description" = "VirtualMic";
            "media.class" = "Audio/Source";
            "audio.position" = [
              "FL"
              "FR"
            ];
          };
        };
      }
      {
        name = "libpipewire-module-loopback";
        args = {
          "node.description" = "Soundboard to Speakers";
          "capture.props" = {
            "node.name" = "capture.sb_to_speakers";
            "target.object" = "Soundboard";
            "stream.capture.sink" = true;
          };
          "playback.props" = {
            "node.name" = "playback.sb_to_speakers";
            "media.class" = "Stream/Output/Audio";
          };
        };
      }
    ];
  };
}
