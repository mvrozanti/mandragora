{ pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    shortcut = "a";
    mouse = true;
    historyLimit = 100000;
    baseIndex = 0;
    escapeTime = 0;
    keyMode = "vi";
    terminal = "tmux-256color";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      urlview
      {
        plugin = open;
        extraConfig = builtins.readFile ../../../.config/tmux/open-plugin.conf;
      }
    ];

    extraConfig = builtins.readFile ../../../.config/tmux/tmux.conf;
  };
}
