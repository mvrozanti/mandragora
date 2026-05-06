{ pkgs, ... }:

{
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore";
    onShutdown = "shutdown";
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  programs.virt-manager.enable = true;

  users.users.m.extraGroups = [ "libvirtd" "kvm" ];

  boot.kernelModules = [ "kvm-amd" ];

  environment.systemPackages = with pkgs; [
    quickemu
    quickgui
    virtio-win
    spice-gtk
  ];
}
