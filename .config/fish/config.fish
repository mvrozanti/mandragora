set fish_greeting
set -gx LSCOLORS "Cxbgdxdxbxdgeghegeacad"
set -x EDITOR nvim
set -x GIT_EDITOR $EDITOR
set -x SUDO_EDITOR "rvim -u NONE"

switch (uname)
case Linux
    set -x OSTYPE "Linux"
case Darwin
    set -x OSTYPE "MacOS"
case FreeBSD NetBSD DragonFly
    set -x OSTYPE "FreeBSD"
case '*'
    set -x OSTYPE "unknown"
end

## ENV

# Fish 3.1+ doesn't add binaries to the path autmatically anymore
# https://github.com/fish-shell/fish-shell/issues/6594
contains /usr/local/bin $PATH
or set PATH /usr/local/bin $PATH
# On M1 Macs, homebrew installs things in /opt/homebrew
contains /opt/homebrew/bin
or set PATH /opt/homebrew/bin $PATH

if [ -f $HOME/.config/fish/env/index.fish ]
    source $HOME/.config/fish/env/index.fish
end

#
### ALIAS
#
# Main
if [ -f $HOME/.config/fish/aliases/main.fish ]
    source $HOME/.config/fish/aliases/main.fish
end

# Private aliases (e.g. with servers address...)
## aliases/private.fish will be ignored by git (.gitignore)
if [ -f $HOME/.config/fish/aliases/private.fish ]
    source $HOME/.config/fish/aliases/private.fish
end

# Git
if [ -f $HOME/.config/fish/aliases/git.fish ]
    source $HOME/.config/fish/aliases/git.fish
end

#
### GIT PROMPT CONFIGURATION
# See the file /usr/local/share/fish/functions/fish_git_prompt.fish
#
set __fish_git_prompt_showdirtystate 'yes'
set __fish_git_prompt_showstashstate 'yes'
set __fish_git_prompt_showuntrackedfiles 'yes'
set __fish_git_prompt_show_informative_status 'yes'
set __fish_git_prompt_showupstream 'yes'

set -l cl_empress '757575'
set -l cl_gainsboro 'E0E0E0'
set -l cl_dodger_blue '297EF2'
set -l cl_gorse 'FFEB3B'
set -l cl_red_orange 'F52D2D'
set __fish_git_prompt_color_branch $cl_gorse -b $cl_empress
set __fish_git_prompt_color_dirtystate $cl_dodger_blue -b $cl_gainsboro
set __fish_git_prompt_color_invalidstate $cl_red_orange -b $cl_gainsboro
set __fish_git_prompt_color_stagedstate $cl_dodger_blue -b $cl_gainsboro
set __fish_git_prompt_color_cleanstate $cl_dodger_blue -b $cl_gainsboro
set __fish_git_prompt_color_stashstate $cl_dodger_blue -b $cl_gainsboro
set __fish_git_prompt_color_upstream $cl_gainsboro -b $cl_empress
set __fish_git_prompt_color_untrackedfiles $cl_dodger_blue -b $cl_gainsboro
set __fish_git_prompt_color $cl_gainsboro -b $cl_empress

set __fish_git_prompt_char_cleanstate '  '
set __fish_git_prompt_char_dirtystate '  '
set __fish_git_prompt_char_invalidstate '  '
set __fish_git_prompt_char_stagedstate '  '
set __fish_git_prompt_char_stashstate '  '
set __fish_git_prompt_char_stateseparator ' '
set __fish_git_prompt_char_untrackedfiles '  '
set __fish_git_prompt_char_upstream_ahead '  '
set __fish_git_prompt_char_upstream_behind '  '
set __fish_git_prompt_char_upstream_diverged '  '
set __fish_git_prompt_char_upstream_equal '  '
set __fish_git_prompt_char_upstream_prefix ' '

# Prevent directories names from being shortened
set fish_prompt_pwd_dir_length 0

# https://github.com/oh-my-fish/theme-bobthefish

function bobthefish_colors -S -d 'Define a custom bobthefish color scheme'
  # Optionally include a base color scheme
  __bobthefish_colors default

  # Then override everything you want!
  # Note that these must be defined with `set -x`
  set -x color_initial_segment_exit     white red --bold
  set -x color_initial_segment_su       white green --bold
  set -x color_initial_segment_jobs     white blue --bold

  set -x color_path                     black white
  set -x color_path_basename            black white --bold
  set -x color_path_nowrite             magenta black
  set -x color_path_nowrite_basename    magenta black --bold

  set -x color_repo                     green black
  set -x color_repo_work_tree           black black --bold
  set -x color_repo_dirty               brred black
  set -x color_repo_staged              yellow black

  set -x color_vi_mode_default          brblue black --bold
  set -x color_vi_mode_insert           brgreen black --bold
  set -x color_vi_mode_visual           bryellow black --bold

  set -x color_vagrant                  brcyan black
  set -x color_k8s                      magenta white --bold
  set -x color_username                 white black --bold
  set -x color_hostname                 white black
  set -x color_rvm                      brmagenta black --bold
  set -x color_virtualfish              brblue black --bold
  set -x color_virtualgo                brblue black --bold
  set -x color_desk                     brblue black --bold
end

function fish_greeting; end
set -g theme_display_date no
bind -k nul accept-autosuggestion
bind \er ranger
