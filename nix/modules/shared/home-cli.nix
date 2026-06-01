{ config, lib, pkgs, inputs, ... }:

# Shared CLI baseline imported by every mandragora host.
# Add things here when they should be on BOTH desktop and WSL.
# Add to hosts/<host>/default.nix or modules/user/home.nix only when
# host-specific (e.g. desktop GUI deps, WSL-only path tweaks).
{
  imports = [
    ../user/zsh.nix
    ../user/tmux.nix
    ../user/yazi.nix
  ];

  home.packages = with pkgs; [
    ripgrep
    silver-searcher
    fd
    fzf
    jq
    bat
    eza
    htop
    btop
    tree
    file
    unzip
    atool
    tokei
    shellcheck
    neovim
    (python3.withPackages (ps: with ps; [ pynvim grip psutil ]))
    trash-cli
    gnupg

    cargo
    rustc
    cmake
    gnumake
    gcc
    kubectl
    mediainfo
    nodejs
    yarn
    forge-cli
    autoclaude
    chafa
    graphviz
    erdtree
    asciinema
    inputs.bruno-tama.packages.${pkgs.system}.default

    (pkgs.writeShellScriptBin "mandragora-pkg-diff" (builtins.readFile ../../../.local/bin/mandragora-pkg-diff.sh))
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.git = {
    enable = true;
    signing.format = null;
    settings = {
      push.autoSetupRemote = true;
      safe.directory = [
        "/etc/nixos/mandragora"
        "/persistent/mandragora"
      ];
    };
  };

  programs.gh.enable = true;
  programs.go.enable = true;

  home.file.".XCompose".source = ../../../.XCompose;
  home.file.".config/nvim" = {
    source = ../../../.config/nvim;
    recursive = true;
  };
}
