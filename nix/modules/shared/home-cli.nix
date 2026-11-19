{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../user/zsh.nix
    ../user/tmux.nix
    ../user/yazi.nix
    ../user/skills.nix
    ../user/claude-find.nix
  ];

  home.packages =
    with pkgs;
    [
      ripgrep
      ruby
      silver-searcher-ng
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
      (pkgs.writeShellScriptBin "claude-spin" (builtins.readFile ../../../.local/bin/claude-spin.sh))
      (pkgs.writeShellScriptBin "claude-spin-daemon" (
        builtins.readFile ../../../.local/bin/claude-spin-daemon.sh
      ))

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
    ]
    ++ lib.optional stdenv.hostPlatform.isLinux chromium
    ++ [
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
  home.file.".claude/hooks/rtk-rewrite.sh".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/hooks/rtk-rewrite.sh";
  home.file.".claude/hooks/chat-mode.sh".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/hooks/chat-mode.sh";
  home.file.".claude/hooks/pgrep-self-match-guard.py".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/hooks/pgrep-self-match-guard.py";
  home.file.".claude/hooks/tmux-state.sh".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/hooks/tmux-state.sh";
  home.file.".local/share/claude-progressbar".source = inputs.claude-progressbar;
}
