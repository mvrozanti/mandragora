{ lib, pkgs, ... }:

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

  programs.kitty.settings = {
    listen_on = lib.mkForce "unix:/tmp/kitty";
    macos_option_as_alt = "yes";
  };
}
