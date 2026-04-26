{ pkgs, ... }: {
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.callPackage ./claude-code/default.nix { };
      rtk = prev.callPackage ./rtk/default.nix { };
      du-exporter = prev.callPackage ./du-exporter/default.nix { };
      ebpf-network-config = prev.callPackage ./ebpf-network-config/default.nix { };
      claude-sidebar = prev.callPackage ./claude-sidebar/default.nix { };
    })
  ];
}
