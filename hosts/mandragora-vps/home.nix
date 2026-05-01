{ config, pkgs, lib, ... }:

{
  home.username = "m";
  home.homeDirectory = "/home/m";
  home.stateVersion = "24.05";

  home.packages = with pkgs; [
    rsync
    htop
    btop
    tree
    jq
    ripgrep
    fd
    fastfetch
    file
    unzip
    tmux
  ];

  programs.home-manager.enable = true;

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history.size = 50000;
    shellAliases = {
      ll = "ls -alh --color=auto";
      la = "ls -A --color=auto";
      g = "git";
      d = "docker";
      dc = "docker compose";
      tsstat = "tailscale status";
      tsip = "tailscale ip -4";
    };
    initContent = ''
      export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
    '';
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Marcelo Vironda Rozanti";
      user.email = "mvrozanti@gmail.com";
      init.defaultBranch = "master";
      pull.rebase = true;
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = false;
    withPython3 = false;
  };

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    terminal = "tmux-256color";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    PAGER = "less -R";
  };
}
