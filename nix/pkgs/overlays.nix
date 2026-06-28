_: {
  nixpkgs.overlays = [
    (_final: prev: {
      autoclaude = prev.callPackage ./autoclaude/default.nix { };
      axon = prev.callPackage ./axon/default.nix { };
      claude-code = prev.callPackage ./claude-code/default.nix { };
      rtk = prev.callPackage ./rtk/default.nix { };
      du-exporter = prev.callPackage ./du-exporter/default.nix { };
      forge-cli = prev.callPackage ./forge-cli/default.nix { };
      ebpf-network-config = prev.callPackage ./ebpf-network-config/default.nix { };
      sddm-mandragora = prev.callPackage ./sddm-mandragora/default.nix { };
    })
  ];
}
