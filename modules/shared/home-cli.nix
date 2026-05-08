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

    aerc
    notmuch
    msmtp
    isync
    khal

    crush

    cargo
    rustc
    cmake
    gnumake
    kubectl
    mediainfo
  ];

  home.file.".config/aerc" = {
    source = ../../.config/aerc;
    recursive = true;
  };
  home.file.".config/khal" = {
    source = ../../.config/khal;
    recursive = true;
  };
  home.file.".config/notmuch/default/config".text = ''
    [database]
    path=${config.home.homeDirectory}/.local/share/mail

    [user]
    name=Marcelo Vironda Rozanti
    primary_email=mvrozanti@hotmail.com

    [new]
    tags=unread;inbox;
    ignore=

    [search]
    exclude_tags=deleted;spam;

    [maildir]
    synchronize_flags=true
  '';

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
      user.name = "mvrozanti";
      user.email = "mvrozanti@hotmail.com";
      push.autoSetupRemote = true;
      safe.directory = [
        "/etc/nixos/mandragora"
        "/persistent/mandragora"
      ];
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

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
