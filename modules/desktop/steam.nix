{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };
}
