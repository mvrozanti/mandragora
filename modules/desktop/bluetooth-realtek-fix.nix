{ pkgs, ... }:
{
  boot.extraModprobeConfig = ''
    # Disable power saving features that cause Realtek choppiness
    options rtw89_pci disable_aspm=y
    options rtw89_core disable_lps_deep=y
    options btusb enable_autosuspend=0
  '';
}
