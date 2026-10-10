{ pkgs, inputs, ... }:

{
  environment.systemPackages = [ inputs.pi.packages.${pkgs.system}.pi ];
}
