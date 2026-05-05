{ pkgs, ... }:

{
  networking.wireless.iwd.enable = true;

  environment.systemPackages = [ pkgs.impala ];
}
