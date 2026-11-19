{ lib, pkgs, ... }:

{
  environment.systemPackages =
    with pkgs;
    [
      git
      glab
      lazygit
      vim
      wget
      curl
      htop
      btop
      tree
      fastfetch
      cbonsai
      figlet
      hyperfine
      jq
      fx
      sops
      age
      openssh
      openssl
      less
      file
      unzip
      rtk
      claude-code
      python3Packages.docx2txt
    ]
    ++ lib.optional stdenv.hostPlatform.isLinux showmethekey
    ++ [
      swi-prolog
      (callPackage ../../pkgs/aescrypt.nix { })
    ];
}
