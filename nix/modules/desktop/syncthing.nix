{ config, pkgs, lib, ... }:

let
  musicStignore = ../../../.config/syncthing/music.stignore;
  phoneInboxStignore = ../../../.config/syncthing/phone-inbox.stignore;

  phoneDeviceId = "TXQSG4I-CFJX3BY-2CUKJOT-DZ4ATH4-HP7HQOK-23VM6PF-VDEM63Z-XGZR2Q5";
  phoneTailnetAddress = "tcp://100.114.176.5:22000";

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
      devices = lib.optionalAttrs (phoneDeviceId != null) {
        phone = {
          id = phoneDeviceId;
          name = "phone";
          addresses = [ phoneTailnetAddress "dynamic" ];
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
        "phone-dcim" = phoneFolder "mandragora-phone-dcim" "Phone DCIM" "/home/m/Pictures/PhoneInbox/dcim";
        "phone-pictures" = phoneFolder "mandragora-phone-pictures" "Phone Pictures" "/home/m/Pictures/PhoneInbox/pictures";
        "phone-whatsapp" = phoneFolder "mandragora-phone-whatsapp" "Phone WhatsApp" "/home/m/Pictures/PhoneInbox/whatsapp";
        "phone-downloads" = phoneFolder "mandragora-phone-downloads" "Phone Downloads" "/home/m/Pictures/PhoneInbox/downloads";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /home/m/Pictures/PhoneInbox 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/dcim 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/pictures 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/whatsapp 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/downloads 0755 m users -"
    "C+ /home/m/Music/.stignore 0644 m users - ${musicStignore}"
    "C+ /home/m/Pictures/PhoneInbox/dcim/.stignore 0644 m users - ${phoneInboxStignore}"
    "C+ /home/m/Pictures/PhoneInbox/pictures/.stignore 0644 m users - ${phoneInboxStignore}"
    "C+ /home/m/Pictures/PhoneInbox/whatsapp/.stignore 0644 m users - ${phoneInboxStignore}"
    "C+ /home/m/Pictures/PhoneInbox/downloads/.stignore 0644 m users - ${phoneInboxStignore}"
  ];
}
