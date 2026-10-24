_: {
  nixpkgs.overlays = [
    (final: prev: {
      autoclaude = prev.callPackage ./autoclaude/default.nix { };
      axon = prev.callPackage ./axon/default.nix { };
      cc-lens = prev.callPackage ./cc-lens/default.nix { };
      cc-pocket-bridge = prev.callPackage ./cc-pocket-bridge/default.nix { };
      claude-code = prev.callPackage ./claude-code/default.nix { };
      electrum = prev.electrum.overrideAttrs (old: rec {
        version = "4.8.3";
        src = prev.fetchurl {
          url = "https://download.electrum.org/${version}/Electrum-${version}.tar.gz";
          hash = "sha256-30H6guV59yCjhZv/neCd2Yu5MHmwH6KXO3P9vb/ecog=";
        };
        postPatch = "";
        pythonRelaxDeps = old.pythonRelaxDeps ++ [ "certifi" ];
      });
      materia-theme-transparent = prev.callPackage ./materia-theme-transparent/default.nix { };
      rtk = prev.callPackage ./rtk/default.nix { };
      du-exporter = prev.callPackage ./du-exporter/default.nix { };
      mutt-oauth2 = prev.callPackage ./mutt-oauth2/default.nix { };
      mail-menu = final.callPackage ./mail-menu/default.nix { };
      ebpf-network-config = prev.callPackage ./ebpf-network-config/default.nix { };
      sddm-mandragora = prev.callPackage ./sddm-mandragora/default.nix { };
      yt-cast-mpv = final.callPackage ./yt-cast-mpv/default.nix { };
      nerd-fonts = prev.nerd-fonts // {
        iosevka = prev.callPackage ./iosevka-nerd-font-nvidia/default.nix {
          iosevkaNerd = prev.nerd-fonts.iosevka;
        };
      };
    })
  ];
}
