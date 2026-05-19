{ pkgs, ... }:

let
  ue5 = import ../../pkgs/ue5.nix { inherit pkgs; };
in
{
  environment.systemPackages = [ ue5 ];
}
