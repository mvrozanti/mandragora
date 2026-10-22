{ pkgs, ... }:
{
  home.packages = [
    pkgs.mail-menu
    pkgs.mutt-oauth2
  ];
}
