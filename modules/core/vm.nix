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

  systemd.tmpfiles.rules = [
    "d /var/lib/libvirt/images 0770 root qemu-libvirtd - -"
  ];

  systemd.services.libvirt-default-net-autostart = {
    description = "Autostart libvirt default NAT network";
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    path = [ pkgs.libvirt ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      virsh net-autostart default || true
      virsh net-start default 2>/dev/null || true
    '';
  };

  environment.systemPackages = with pkgs; [
    quickemu
    quickgui
    virtio-win
    spice-gtk
    virt-viewer
  ];
}
