{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
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
    showmethekey
    swi-prolog
    (callPackage ../../pkgs/aescrypt.nix { })
  ];
}
