{ config, lib, pkgs, ... }:

let
  zxDirs = import ./zx-dirs.nix;
  homeDir = config.home.homeDirectory;
  normalize = v: if builtins.isString v then { path = v; } else v;
  expandHome = p: lib.replaceStrings [ "~" ] [ homeDir ] p;
  jumpKeymap = lib.attrValues (lib.mapAttrs (k: v:
    let e = normalize v;
        path = expandHome e.path;
    in { on = [ "g" k ]; run = "cd ${path}"; desc = "cd ${e.path}"; }
  ) zxDirs);
in
{
  home.packages = with pkgs; [ yazi ];

  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";

    settings = {
      mgr = {
        ratio = [ 1 2 3 ];
        sort_by = "btime";
        sort_sensitive = false;
        sort_reverse = true;
        sort_dir_first = true;
        linemode = "size";
        show_hidden = false;
        show_symlink = true;
        scrolloff = 8;
      };
      preview = {
        image_filter = "triangle";
        image_quality = 75;
        sixel_fraction = 15;
        tab_size = 2;
        max_width = 1200;
        max_height = 1800;
      };
      opener = {
        edit = [
          { run = ''$EDITOR "$@"''; block = true; for = "unix"; }
        ];
        open = [
          { run = ''xdg-open "$@"''; desc = "xdg-open"; orphan = true; for = "unix"; }
        ];
        play = [
          { run = ''mpv "$@"''; orphan = true; for = "unix"; }
        ];
        view-image = [
          { run = ''nsxiv -ab -- "$@"''; orphan = true; for = "unix"; }
        ];
        view-pdf = [
          { run = ''zathura "$@"''; orphan = true; for = "unix"; }
        ];
        view-archive = [
          { run = ''atool --list -- "$@" | ${"$"}{PAGER:-less}''; block = true; for = "unix"; }
        ];
        office = [
          { run = ''libreoffice "$@"''; orphan = true; for = "unix"; }
        ];
      };
      open = {
        rules = [
          { mime = "text/*"; use = [ "edit" ]; }
          { mime = "image/*"; use = [ "view-image" ]; }
          { mime = "video/*"; use = [ "play" ]; }
          { mime = "audio/*"; use = [ "play" ]; }
          { mime = "application/pdf"; use = [ "view-pdf" ]; }
          { mime = "application/epub+zip"; use = [ "view-pdf" ]; }
          { mime = "application/zip"; use = [ "view-archive" ]; }
          { mime = "application/x-tar"; use = [ "view-archive" ]; }
          { mime = "application/x-7z-compressed"; use = [ "view-archive" ]; }
          { mime = "application/x-rar"; use = [ "view-archive" ]; }
          { mime = "application/vnd.openxmlformats-officedocument.*"; use = [ "office" ]; }
          { mime = "application/msword"; use = [ "office" ]; }
          { mime = "application/vnd.ms-excel"; use = [ "office" ]; }
          { mime = "application/vnd.ms-powerpoint"; use = [ "office" ]; }
          { mime = "application/vnd.oasis.opendocument.*"; use = [ "office" ]; }
          { name = "*"; use = [ "open" ]; }
        ];
      };
    };

    keymap = {
      mgr.prepend_keymap = jumpKeymap ++ [
        { on = "a"; run = "rename --cursor=before_ext"; desc = "Rename"; }
        { on = [ "c" "w" ]; run = "rename --cursor=before_ext"; desc = "Rename"; }
        { on = "A"; run = "rename --cursor=end"; desc = "Rename (end)"; }
        { on = "I"; run = ''shell --block 'file "$0" | less' ''; desc = "File info"; }
        { on = "i"; run = ''shell --orphan 'nsxiv -ab -- "$(dirname "$0")"' ''; desc = "nsxiv on dir"; }
        { on = "P"; run = ''shell 'printf "%s" "$0" | wl-copy' ''; desc = "Yank path"; }
        { on = "N"; run = ''shell 'basename "$0" | tr -d "\n" | wl-copy' ''; desc = "Yank name"; }
        { on = "<C-n>"; run = ''shell 'basename "$0" | tr -d "\n" | wl-copy' ''; desc = "Yank name"; }
        { on = "B"; run = ''shell --block 'ic "$0"' ''; desc = "Yank bytes"; }
        { on = ";"; run = "hidden toggle"; desc = "Toggle hidden"; }
        { on = "D"; run = ''shell --confirm 'trash-put -- "$@"' ''; desc = "Trash"; }
        { on = [ "o" "z" ]; run = "sort none"; desc = "Sort random"; }
        { on = [ "o" "s" ]; run = "sort size --reverse"; desc = "Sort size desc"; }
        { on = [ "o" "S" ]; run = "sort size"; desc = "Sort size asc"; }
        { on = [ "o" "m" ]; run = "sort mtime --reverse"; desc = "Sort mtime desc"; }
        { on = [ "o" "M" ]; run = "sort mtime"; desc = "Sort mtime asc"; }
        { on = [ "o" "c" ]; run = "sort btime"; desc = "Sort btime asc"; }
        { on = [ "o" "C" ]; run = "sort btime --reverse"; desc = "Sort btime desc"; }
        { on = "e"; run = "open --interactive"; desc = "Open interactive"; }
        { on = [ "b" "w" ]; run = ''shell --orphan 'setbg "$0"' ''; desc = "Set wallpaper"; }
        { on = [ "p" "B" ]; run = ''shell 'wl-paste -t image/png > "$(date +%s).png"' ''; desc = "Paste PNG"; }
        { on = [ "p" "b" ]; run = ''shell 'wl-paste -t image/jpeg > "$(date +%s).jpg"' ''; desc = "Paste JPEG"; }
        { on = "M"; run = "create --dir"; desc = "mkdir"; }
        { on = "U"; run = ''shell --block 'unp -U "$0"' ''; desc = "Unzip"; }
        { on = "H"; run = "back"; desc = "History back"; }
        { on = "L"; run = "forward"; desc = "History forward"; }
        { on = "<PageDown>"; run = "arrow 50%"; desc = "Half page down"; }
        { on = "<PageUp>"; run = "arrow -50%"; desc = "Half page up"; }
        { on = "<C-f>"; run = "arrow 50%"; desc = "Half page down"; }
        { on = "<C-b>"; run = "arrow -50%"; desc = "Half page up"; }
      ];
    };
  };
}
