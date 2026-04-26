{ pkgs, lib, ... }:

let
  effectsDir = ../../snippets/keyledsd-effects;
  effectFiles = builtins.readDir effectsDir;
  workspaceWatcher = pkgs.writeShellApplication {
    name = "keyleds-workspace-watcher";
    runtimeInputs = [ pkgs.socat pkgs.jq pkgs.systemd pkgs.hyprland ];
    text = builtins.readFile ../../.local/bin/keyleds-workspace-watcher.sh;
  };
  keyleds-ticpu = pkgs.keyleds.overrideAttrs (old: {
    pname = "keyleds-ticpu";
    version = "unstable-2026-03-24";
    src = pkgs.fetchFromGitHub {
      owner = "ticpu";
      repo = "keyleds";
      rev = "7c429154dc377fc61a5a8a76a061911eb59f635f";
      sha256 = "1ih1cc12j79ch4h4akwk2f6jg1hdyzf44h3wb970nysrkqv8wq0q";
    };
    patches = [ ../../snippets/keyleds-extra-input.patch ];
    postPatch = "";
    buildInputs = (old.buildInputs or []) ++ [ pkgs.libevdev ];
    postInstall = (old.postInstall or "") + ''
      ${lib.concatStringsSep "\n" (map (name:
        "cp ${pkgs.writeText name (builtins.readFile (effectsDir + "/${name}"))} $out/share/keyledsd/effects/${name}"
      ) (builtins.attrNames effectFiles))}
    '';
  });
in
{
  environment.systemPackages = [ keyleds-ticpu workspaceWatcher ];

  services.udev.packages = [
    keyleds-ticpu
    (pkgs.writeTextFile {
      name = "keyleds-keyd-uaccess-rules";
      destination = "/etc/udev/rules.d/65-keyleds-keyd.rules";
      text = ''
        KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="keyd virtual keyboard", TAG+="uaccess"
      '';
    })
  ];

  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c339", MODE="0660", TAG+="uaccess"
  '';

  systemd.user.services.keyledsd = {
    description = "Keyleds RGB keyboard daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    environment.KEYLEDS_EXTRA_INPUT_NAMES = "keyd virtual keyboard";
    serviceConfig = {
      ExecStartPre = "${pkgs.python3}/bin/python3 ${../../snippets/keyleds-host-mode.py}";
      ExecStart = "${keyleds-ticpu}/bin/keyledsd -c %h/.config/keyledsd.conf -m ${keyleds-ticpu}/lib/keyledsd -m ${keyleds-ticpu}/share/keyledsd/effects";
      Restart = "on-failure";
      RestartSec = "3s";
      TimeoutStopSec = "5s";
    };
  };

  systemd.user.services.keyleds-workspace-watcher = {
    description = "Forward Hyprland workspace events to keyledsd context";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" "keyledsd.service" ];
    requires = [ "keyledsd.service" ];
    serviceConfig = {
      ExecStart = "${workspaceWatcher}/bin/keyleds-workspace-watcher";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
