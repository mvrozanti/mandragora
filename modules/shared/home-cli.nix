{ config, lib, pkgs, ... }:

{
  imports = [
    ../user/zsh.nix
    ../user/tmux.nix
    ../user/lf.nix
    ../user/skills.nix
  ];

  home.packages = with pkgs; [
    ripgrep
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

    crush

    cargo
    rustc
    cmake
    gnumake
    kubectl
    mediainfo
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

  programs.go = {
    enable = true;
    env = {
      GOPATH = ".local/share/go";
      GOBIN = ".local/share/go/bin";
    };
  };

  home.file.".XCompose".source = ../../.XCompose;
  home.file.".config/nvim" = {
    source = ../../.config/nvim;
    recursive = true;
  };
}
