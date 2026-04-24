{ pkgs, ... }:

{
  virtualisation.libvirtd.enable = false;

  programs.virt-manager.enable = false;

  # Windows-specific tools (kept available, virtualization disabled for now)
  environment.systemPackages = with pkgs; [
    quickemu
    quickgui
  ];
}
