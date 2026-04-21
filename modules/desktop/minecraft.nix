{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    prismlauncher
    jdk21
    jetbrains.idea-community
  ];
}
