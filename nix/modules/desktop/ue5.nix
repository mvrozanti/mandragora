{ pkgs, ... }:

let
  ue5 = import ../../pkgs/ue5 { inherit pkgs; };
in
{
  environment.systemPackages = [ ue5 ];
}
