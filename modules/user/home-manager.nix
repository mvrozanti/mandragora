{ config, pkgs, inputs, ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    users.m = import ./home.nix;
    extraSpecialArgs = { inherit inputs; };
  };
}
