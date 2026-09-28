{ config, pkgs, ... }:

# Shared CLI baseline imported by every mandragora host.
# Add things here when they should be on BOTH desktop and WSL.
# Add to hosts/<host>/default.nix or modules/user/home.nix only when
# host-specific (e.g. desktop GUI deps, WSL-only path tweaks).
{
  imports = [
    ../user/zsh.nix
    ../user/tmux.nix
    ../user/yazi.nix
    ../user/skills.nix
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
    (python3.withPackages (
      ps: with ps; [
        pynvim
        grip
        psutil
      ]
    ))
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
    autoclaude
    chafa
    graphviz
    erdtree
    asciinema

    rust-analyzer
    pyright
    lua-language-server
    typescript-language-server
    typescript
    nixd
    chromium

    (pkgs.writeShellScriptBin "mandragora-pkg-diff" (
      builtins.readFile ../../../.local/bin/mandragora-pkg-diff.sh
    ))
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
  systemd.user.tmpfiles.rules = [
    "L+ %h/.claude/settings.json - - - - /etc/nixos/mandragora/.claude/settings.json"
  ];
  home.file.".claude/hooks/rtk-rewrite.sh".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/hooks/rtk-rewrite.sh";
  # Re-asserts chat mode on every prompt while the session's flag exists. A
  # skill is read once; this is what makes the mode unforgettable twenty
  # turns later. Silent and exit-0 when the flag is absent.
  home.file.".claude/hooks/chat-mode.sh".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/hooks/chat-mode.sh";
}
