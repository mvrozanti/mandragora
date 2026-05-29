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
    jq
    sops
    age
    openssh
    less
    file
    unzip
    rtk
    claude-code
    python3Packages.docx2txt
    showmethekey
  ];
}
