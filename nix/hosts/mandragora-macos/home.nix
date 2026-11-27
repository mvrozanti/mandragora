{ lib, pkgs, ... }:

let
  cmdAsCtrl = true;
  ctrlBytes = {
    a = "01";
    b = "02";
    c = "03";
    d = "04";
    e = "05";
    f = "06";
    g = "07";
    i = "09";
    j = "0a";
    k = "0b";
    l = "0c";
    o = "0f";
    p = "10";
    r = "12";
    s = "13";
    u = "15";
    x = "18";
    y = "19";
    z = "1a";
  };
  cmdAsCtrlBindings = lib.mapAttrs' (
    k: v: lib.nameValuePair "cmd+${k}" "send_text all \\x${v}"
  ) ctrlBytes;
in
{
  home.packages = with pkgs; [
    coreutils
    gnused
    gnugrep
    gawk
    findutils
    gnutar
    diffutils
    flock
    iproute2mac
    pngpaste
  ];

  programs.kitty = {
    font.size = 12.5;
    settings = {
      listen_on = lib.mkForce "unix:/tmp/kitty";
      macos_option_as_alt = "yes";
      background_blur = "32";
    };
    keybindings = if cmdAsCtrl then cmdAsCtrlBindings else { };
  };
}
