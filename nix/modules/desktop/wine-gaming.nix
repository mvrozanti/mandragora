{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    wineWow64Packages.staging
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
