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
      hypr-live-instance = final.writeShellApplication {
        name = "hypr-live-instance";
        runtimeInputs = [
          final.coreutils
          final.hyprland
        ];
        text = builtins.readFile ../../.local/bin/hypr-live-instance.sh;
      };
      hyprland = prev.hyprland.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (prev.fetchurl {
            url = "https://github.com/hyprwm/Hyprland/commit/d8504461f0e9f95a5df9a0cdc0723d0ca6332888.patch";
            hash = "sha256-cZ8LzzU7fUzV7C2VOqFUOs4IOuqDHFtBQmGGgbTRjhw=";
          })
        ];
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
