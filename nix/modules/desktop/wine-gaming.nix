{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    wineWowPackages.staging
    winetricks
    dxvk
    vkd3d-proton
    gamemode
    gamescope
    mangohud
    protontricks
    bubblewrap
    firejail
  ];

  programs.gamemode.enable = true;
}
