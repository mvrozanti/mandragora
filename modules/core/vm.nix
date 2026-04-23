{ pkgs, ... }:

{
  # Base Virtualization Support
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore";
    onShutdown = "shutdown";
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
      # Required for GPU passthrough permissions
      verbatimConfig = ''
        namespaces = []
        user = "m"
        group = "libvirtd"
      '';
    };
  };

  virtualisation.spiceUSBRedirection.enable = true;
  programs.virt-manager.enable = true;
  users.users.m.extraGroups = [ "libvirtd" ];

  # Windows-specific tools
  environment.systemPackages = with pkgs; [
    quickemu
    quickgui
    virtio-win
    virt-viewer
  ];

  # Note: GPU Isolation (RTX 5070 Ti) is handled in boot.nix
  # VGA: 10de:2c05, Audio: 10de:22e9
}
