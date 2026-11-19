{ lib, ... }:

{
  options.mandragora.profile = lib.mkOption {
    type = lib.types.enum [
      "desktop"
      "live"
      "wsl"
      "macos"
    ];
    default = "desktop";
    description = ''
      Which kind of mandragora system this is. Shared modules use this
      to gate desktop-only or live-only behavior.
    '';
  };
}
