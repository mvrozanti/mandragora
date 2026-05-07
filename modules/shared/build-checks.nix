{ self, nixpkgs, system }:

let
  pkgs = nixpkgs.legacyPackages.${system};

  usbClosureInfo = pkgs.closureInfo {
    rootPaths = [ self.nixosConfigurations.mandragora-usb.config.system.build.toplevel ];
  };

  closureSizeGuard = pkgs.runCommand "usb-closure-size-guard" { } ''
    size_bytes=$(${pkgs.findutils}/bin/xargs ${pkgs.coreutils}/bin/du -bs \
      < ${usbClosureInfo}/store-paths \
      | ${pkgs.gawk}/bin/awk '{s+=$1} END {print s}')
    size_kb=$(( size_bytes / 1024 ))
    size_gib=$(echo "scale=2; $size_kb / 1024 / 1024" | ${pkgs.bc}/bin/bc)
    echo "USB host closure: $size_gib GiB"
    limit_kb=$(( 6 * 1024 * 1024 ))
    if (( size_kb > limit_kb )); then
      echo "FAIL: closure exceeds 6 GiB ceiling ($size_gib GiB)" >&2
      exit 1
    fi
    touch $out
  '';

  sopsKeyGuard = pkgs.runCommand "usb-sops-key-encrypted-guard" { } ''
    key=${self}/secrets/usb-key.age
    if ! [ -f "$key" ]; then
      echo "FAIL: secrets/usb-key.age missing" >&2; exit 1
    fi
    first=$(head -1 "$key")
    case "$first" in
      "-----BEGIN AGE ENCRYPTED FILE-----") ;;
      "age-encryption.org/v1") ;;
      *)
        echo "FAIL: secrets/usb-key.age is not age-encrypted (first line: '$first')" >&2
        exit 1
        ;;
    esac
    if ${pkgs.gnugrep}/bin/grep -q '^AGE-SECRET-KEY-' "$key"; then
      echo "FAIL: secrets/usb-key.age contains a raw private key" >&2
      exit 1
    fi
    touch $out
  '';

  profileEvalGuard = pkgs.runCommand "profile-eval-guard" { } ''
    desktop=${self.nixosConfigurations.mandragora-desktop.config.system.build.toplevel}
    usb=${self.nixosConfigurations.mandragora-usb.config.system.build.toplevel}
    [ -e "$desktop" ] && [ -e "$usb" ] || { echo "FAIL: one or both hosts didn't build" >&2; exit 1; }
    touch $out
  '';

  hyprlandConfigGuard = pkgs.runCommand "hyprland-config-guard" {
    nativeBuildInputs = [ pkgs.hyprland ];
  } ''
    if [ -f /etc/hyprland.conf ]; then
      ${pkgs.hyprland}/bin/Hyprland --config /etc/hyprland.conf --check-config 2>&1 || {
        echo "FAIL: hyprland config errors" >&2; exit 1; }
    fi
    touch $out
  '';
in
{
  inherit closureSizeGuard sopsKeyGuard profileEvalGuard hyprlandConfigGuard;
}
