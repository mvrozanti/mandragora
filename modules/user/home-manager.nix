{ config, pkgs, inputs, ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.m = import ./home.nix;
    extraSpecialArgs = { inherit inputs; };
  };
}
