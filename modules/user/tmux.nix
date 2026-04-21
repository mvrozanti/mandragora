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
      tmux-powerline
    ];

    extraConfig = builtins.readFile ../../.config/tmux/tmux.conf;
  };

  xdg.configFile."tmux-powerline/config.sh".text = ''
    # Managed by Nix. Session on the left; nothing on the right.

    export TMUX_POWERLINE_THEME='default'

    # Gruvbox dark: bg0=235, fg=223, yellow=214
    export TMUX_POWERLINE_DEFAULT_BACKGROUND_COLOR='235'
    export TMUX_POWERLINE_DEFAULT_FOREGROUND_COLOR='223'

    export TMUX_POWERLINE_LEFT_STATUS_SEGMENTS=(
      "tmux_session_info 214 235"
    )

    export TMUX_POWERLINE_RIGHT_STATUS_SEGMENTS=()
  '';
}
