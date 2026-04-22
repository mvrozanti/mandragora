{ pkgs, ... }: {
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.callPackage ./claude-code/default.nix { };
      rtk = prev.callPackage ./rtk/default.nix { };
      du-exporter = prev.callPackage ./du-exporter/default.nix { };
    })
  ];
}
