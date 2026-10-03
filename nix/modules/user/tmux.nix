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
      {
        plugin = jump;
        extraConfig =
          builtins.readFile ../../../.config/tmux/jump-plugin.conf
          + "\nbind-key -T root M-f if-shell -F '#{==:#{pane_current_command},nvim}' 'send-keys M-f' 'run-shell -b ${pkgs.tmuxPlugins.jump}/share/tmux-plugins/jump/scripts/tmux-jump.sh'";
      }
    ];

    extraConfig = builtins.readFile ../../../.config/tmux/tmux.conf;
  };
}
