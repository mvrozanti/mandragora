{ pkgs, ... }: {
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.callPackage ./claude-code/default.nix { };
    })
  ];
}
