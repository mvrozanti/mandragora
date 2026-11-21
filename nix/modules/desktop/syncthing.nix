{ lib, ... }:

let
  musicStignore = ../../../.config/syncthing/music.stignore;
  notesStignore = ../../../.config/syncthing/notes.stignore;

  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
  identity = builtins.fromJSON (builtins.readFile ../../hosts/mandragora-phone/identity.json);
  phoneDeviceId = identity.syncthing.deviceId;
  phoneTailnetAddress = "tcp://${tailnet.phone.ip}:${toString identity.syncthing.port}";

  phoneShared = lib.optionals (phoneDeviceId != null) [ "phone" ];

  phoneFolder = id: label: path: {
    inherit id label path;
    type = "sendreceive";
    devices = phoneShared;
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
    overrideFolders = true;

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
      devices = lib.optionalAttrs (phoneDeviceId != null) {
        phone = {
          id = phoneDeviceId;
          name = "phone";
          addresses = [
            phoneTailnetAddress
            "dynamic"
          ];
          autoAcceptFolders = false;
        };
      };
      folders = {
        "music" = {
          id = "mandragora-music";
          label = "Music";
          path = "/home/m/Music";
          type = "sendonly";
          devices = phoneShared;
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
        "notes" = phoneFolder "mandragora-notes" "Notes" "/home/m/Documents/notes";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /home/m/Documents/notes 0755 m users -"
    "C+ /home/m/Documents/notes/.stignore 0644 m users - ${notesStignore}"
    "C+ /home/m/Music/.stignore 0644 m users - ${musicStignore}"
  ];
}
