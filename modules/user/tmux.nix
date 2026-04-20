{ pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    shortcut = "a";
    mouse = true;
    baseIndex = 0;
    escapeTime = 0;
    keyMode = "vi";
    terminal = "xterm-kitty";
    
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      urlview
      {
        plugin = open;
        extraConfig = ''
          set -g @open 'O'
          set -g @open-editor 'o'
          set -g @open-S 'https://www.google.com/search?q='
        '';
      }
    ];

    extraConfig = builtins.readFile ../../.config/tmux/tmux.conf;
  };
}
