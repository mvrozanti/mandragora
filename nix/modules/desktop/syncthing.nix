{ config, pkgs, lib, ... }:

let
  musicStignore = ../../../.config/syncthing/music.stignore;
in
{
  services.syncthing = {
    enable = true;
    user = "m";
    group = "users";
    dataDir = "/home/m";
    configDir = "/home/m/.config/syncthing";
    openDefaultPorts = true;
    overrideDevices = false;
    overrideFolders = false;

    settings = {
      gui = {
        address = "127.0.0.1:8384";
      };
      options = {
        urAccepted = -1;
        relaysEnabled = true;
        natEnabled = true;
        startBrowser = false;
        localAnnounceEnabled = true;
        globalAnnounceEnabled = true;
      };
      folders = {
        "music" = {
          id = "mandragora-music";
          label = "Music";
          path = "/home/m/Music";
          type = "sendreceive";
          ignorePerms = true;
          rescanIntervalS = 60;
          fsWatcherEnabled = true;
          fsWatcherDelayS = 10;
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";
              maxAge = "2592000";
            };
          };
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "C+ /home/m/Music/.stignore 0644 m users - ${musicStignore}"
  ];
}
