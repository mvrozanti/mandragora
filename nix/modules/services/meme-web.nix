{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mandragora.memeWeb;
  memePkgs = pkgs.callPackage ../../pkgs/meme-cli.nix { };
  stateDir = "/home/m/.local/share/meme";
  sidecarRoots = lib.concatMapStringsSep ":" toString cfg.sidecarRoots;
  nightlyTag = pkgs.writeShellApplication {
    name = "meme-nightly-tag";
    runtimeInputs = [
      memePkgs.meme
      memePkgs.vfind
      pkgs.sqlite
      pkgs.coreutils
    ];
    text = builtins.readFile ../../snippets/meme-nightly-tag.sh;
  };
in
{
  options.mandragora.memeWeb = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the meme.mvr.ac runner web UI (port 8093, user service).";
    };
    targetDir = lib.mkOption {
      type = lib.types.path;
      description = ''
        Directory the meme-server subprocess will recursively tag when
        the user clicks Start. Set per host; no default.
      '';
    };
    listenHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address meme-server binds. Defaults to loopback. Set to the host's
        tailscale IP so the VPS caddy proxy (meme.mvr.ac) can reach it while
        the tailscale0-only firewall keeps port 8093 off the LAN/public net.
      '';
    };
    sidecarRoots = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Directories whose media must stay byte-identical: tags for files
        under them go to a `<file>.xmp` sidecar instead of into the file.
      '';
    };
    nightly = {
      roots = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "Directories whose untagged media is tagged and reindexed every night.";
      };
      start = lib.mkOption {
        type = lib.types.str;
        default = "02:30";
        description = "Time of day the nightly tagging run starts.";
      };
      until = lib.mkOption {
        type = lib.types.str;
        default = "06:30";
        description = "Time of day the nightly tagging run stops, wherever it is.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.meme-nightly-tag = lib.mkIf (cfg.nightly.roots != [ ]) {
      description = "Tag the night's untagged memes, then refresh the meme.mvr.ac index";
      environment = {
        VTAG_STATE_DIR = stateDir;
        VTAG_SIDECAR_ROOTS = sidecarRoots;
        MEME_NIGHTLY_ROOTS = lib.concatMapStringsSep ":" toString cfg.nightly.roots;
        MEME_NIGHTLY_UNTIL = cfg.nightly.until;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${nightlyTag}/bin/meme-nightly-tag";
        Nice = 15;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "6h";
        MemoryMax = "6G";
      };
    };

    systemd.user.timers.meme-nightly-tag = lib.mkIf (cfg.nightly.roots != [ ]) {
      description = "Nightly trigger for meme tagging, inside the hours the operator sleeps";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${cfg.nightly.start}:00";
        Persistent = false;
      };
    };

    mandragora.hub.services.meme-web = {
      maxRuntime = "12h";
      port = 8093;
      userService = true;
      systemd = {
        description = "meme.mvr.ac — meme runner web UI";
        wantedBy = [ "default.target" ];
        after = [ "default.target" ];
        environment = {
          VTAG_STATE_DIR = stateDir;
          VTAG_SIDECAR_ROOTS = sidecarRoots;
          VTAG_HUB_TARGET_DIR = toString cfg.targetDir;
          VTAG_HUB_LISTEN_HOST = cfg.listenHost;
          VTAG_HUB_LISTEN_PORT = "8093";
          VTAG_HUB_VTAG_BIN = "${memePkgs.meme}/bin/meme";
        };
        serviceConfig = {
          ExecStart = "${memePkgs.meme-server}/bin/meme-server";
          Restart = "always";
          RestartSec = "5s";
          ProtectHome = false;
          PrivateTmp = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
          MemoryMax = "1G";
          OOMScoreAdjust = 200;
        };
      };
    };
  };
}
