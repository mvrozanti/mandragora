{ config, lib, pkgs, osConfig ? null, ... }:

let
  profile = if osConfig != null && osConfig ? mandragora
            then osConfig.mandragora.profile
            else "desktop";
  isWsl = profile == "wsl";
  zxDirs = import ./zx-dirs.nix;
  homeDir = config.home.homeDirectory;
  normalize = v: if builtins.isString v then { path = v; } else v;
  expandHome = p: lib.replaceStrings [ "~" ] [ homeDir ] p;
  jumpKeymap = lib.attrValues (lib.mapAttrs (k: v:
    let e = normalize v;
        path = expandHome e.path;
    in { on = [ "g" k ]; run = "cd ${path}"; desc = "cd ${e.path}"; }
  ) zxDirs);

  yaziUnwrappedPatched = pkgs.yazi-unwrapped.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      find yazi-fm yazi-binding yazi-plugin yazi-widgets -type f -name '*.rs' \
        | xargs -r sed -i 's/BorderType::Rounded/BorderType::Plain/g'
    '';
  });

  yaziSquareBorders = pkgs.yazi.override {
    yazi-unwrapped = yaziUnwrappedPatched;
  };

  zjumpPlugin = pkgs.runCommand "zjump-yazi" {} ''
    mkdir -p $out
    cat > $out/main.lua <<'LUA'
    local M = {}
    function M:entry()
      local query, event = ya.input({
        title = "z:",
        pos = { "top-center", y = 3, w = 60 },
      })
      if event ~= 1 then return end
      query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if query == "" then return end

      local child, err = Command("sh")
        :arg("-c"):arg("zoxide query -l | fzf --filter=\"$1\" | head -n1")
        :arg("zjump"):arg(query)
        :stdin(Command.NULL):stdout(Command.PIPED):stderr(Command.PIPED)
        :spawn()
      if not child then
        ya.notify({ title = "zjump", content = "spawn failed: " .. tostring(err), level = "error", timeout = 5 })
        return
      end
      local output = child:wait_with_output()
      local target = output and output.stdout:gsub("[\r\n]+$", "") or ""
      if target == "" then
        ya.notify({ title = "zjump", content = "no match for: " .. query, level = "warn", timeout = 3 })
        return
      end
      ya.mgr_emit("cd", { target })
    end
    return M
    LUA
  '';

  smartEnterPlugin = pkgs.runCommand "smart-enter-yazi" {} ''
    mkdir -p $out
    cat > $out/main.lua <<'LUA'
    return {
      entry = function(self, job)
        local h = cx.active.current.hovered
        ya.mgr_emit(h and h.cha.is_dir and "enter" or "open", { hovered = true })
      end,
    }
    LUA
  '';

  zoxideAddPlugin = pkgs.runCommand "zoxide-add-yazi" {} ''
    mkdir -p $out
    cat > $out/main.lua <<'LUA'
    local M = {}
    function M:setup()
      ps.sub("cd", function()
        local cwd = tostring(cx.active.current.cwd)
        Command("zoxide"):arg("add"):arg(cwd)
          :stdin(Command.NULL):stdout(Command.NULL):stderr(Command.NULL):spawn()
      end)
    end
    return M
    LUA
  '';
in
{
  home.packages = [ yaziSquareBorders ];

  programs.yazi = {
    enable = true;
    package = yaziSquareBorders;
    enableZshIntegration = true;
    shellWrapperName = "y";

    plugins.no-status = {
      package = pkgs.yaziPlugins.no-status;
      setup = true;
    };
    plugins.zjump = {
      package = zjumpPlugin;
      setup = false;
    };
    plugins.smart-enter = {
      package = smartEnterPlugin;
      setup = false;
    };
    plugins.zoxide-add = {
      package = zoxideAddPlugin;
      setup = true;
    };

    settings = {
      mgr = {
        ratio = [ 1 2 3 ];
        sort_by = "mtime";
        sort_sensitive = false;
        sort_reverse = true;
        sort_dir_first = true;
        linemode = "size";
        show_hidden = false;
        show_symlink = true;
        scrolloff = 8;
        find_sensitive = false;
        mouse_events = [ "click" "scroll" "touch" "move" ];
        time_format = "%Y %b %_d %H:%M:%S";
      };
      preview = {
        image_filter = "triangle";
        image_quality = 75;
        sixel_fraction = 15;
        tab_size = 2;
        max_width = 1200;
        max_height = 1800;
      };
      plugin = lib.optionalAttrs isWsl {
        prepend_previewers = [
          { mime = "image/*"; run = "noop"; }
          { mime = "video/*"; run = "noop"; }
        ];
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

    theme = {
      mgr = {
        border_symbol = " ";
        border_style = { fg = "reset"; };
        hovered = { fg = "black"; bg = "yellow"; };
        preview_hovered = { underline = true; };
        find_keyword = { fg = "yellow"; bold = true; italic = true; underline = true; };
        find_position = { fg = "magenta"; bold = true; italic = true; };
        marker_copied = { fg = "green"; };
        marker_cut = { fg = "red"; };
        marker_marked = { fg = "cyan"; };
        marker_selected = { fg = "yellow"; };
        count_copied = { fg = "green"; };
        count_cut = { fg = "red"; };
        count_selected = { fg = "yellow"; };
      };
      status = {
        sep_left = { open = " "; close = " "; };
        sep_right = { open = " "; close = " "; };
      };
      tabs = {
        sep_inner = { open = " "; close = " "; };
        sep_outer = { open = " "; close = " "; };
      };
      mode = {
        normal_main = { };
        normal_alt = { };
        select_main = { };
        select_alt = { };
        unset_main = { };
        unset_alt = { };
      };
      indicator = {
        padding = { open = " "; close = " "; };
        parent = { underline = true; };
        current = { underline = true; };
        preview = { underline = true; };
      };
    };

    keymap = {
      mgr.prepend_keymap = jumpKeymap ++ [
        { on = "d"; run = "yank --cut"; desc = "Cut (lf style)"; }
        { on = "x"; run = "escape"; desc = "Neutralized (lf had no x)"; }
        { on = "r"; run = "escape"; desc = "Neutralized — use a/cw/A"; }
        { on = "v"; run = "escape"; desc = "Neutralized (visual mode hidden by no-status)"; }
        { on = "<Tab>"; run = "escape"; desc = "Neutralized (no tabs habit from lf)"; }
        { on = "1"; run = "escape"; desc = "Neutralized (no tab digits)"; }
        { on = "2"; run = "escape"; desc = "Neutralized (no tab digits)"; }
        { on = "3"; run = "escape"; desc = "Neutralized (no tab digits)"; }
        { on = "4"; run = "escape"; desc = "Neutralized (no tab digits)"; }
        { on = "5"; run = "escape"; desc = "Neutralized (no tab digits)"; }
        { on = "6"; run = "escape"; desc = "Neutralized (no tab digits)"; }
        { on = "7"; run = "escape"; desc = "Neutralized (no tab digits)"; }
        { on = "8"; run = "escape"; desc = "Neutralized (no tab digits)"; }
        { on = "9"; run = "escape"; desc = "Neutralized (no tab digits)"; }
        { on = "<C-r>"; run = "refresh"; desc = "Reload (lf style)"; }
        { on = "a"; run = "rename --cursor=before_ext"; desc = "Rename"; }
        { on = [ "c" "w" ]; run = "rename --cursor=before_ext"; desc = "Rename"; }
        { on = "A"; run = "rename --cursor=end"; desc = "Rename (end)"; }
        { on = "I"; run = ''shell "file %s | less" --block''; desc = "File info"; }
        { on = "i"; run = ''shell "nsxiv -ab -- $(dirname %s | head -1)" --orphan''; desc = "nsxiv on dir"; }
        { on = "P"; run = ''shell "echo -n %s | wl-copy"''; desc = "Yank path"; }
        { on = "N"; run = ''shell "basename %s | tr -d '\n' | wl-copy"''; desc = "Yank name"; }
        { on = "<C-n>"; run = ''shell "basename %s | tr -d '\n' | wl-copy"''; desc = "Yank name"; }
        { on = "B"; run = ''shell "ic %s" --block''; desc = "Yank bytes"; }
        { on = ";"; run = "hidden toggle"; desc = "Toggle hidden"; }
        { on = "|"; run = "filter"; desc = "Filter"; }
        { on = "z"; run = "plugin zjump"; desc = "Zoxide jump (fzf)"; }
        { on = "<C-l>"; run = "refresh"; desc = "Reload"; }
        { on = "<C-v>"; run = ''shell "wl-paste -t image/png > $(mktemp -p . --suffix=.png paste-XXXXXX)"''; desc = "Paste PNG from clipboard"; }
        { on = "<C-V>"; run = ''shell "wl-paste -t image/jpeg > $(mktemp -p . --suffix=.jpg paste-XXXXXX)"''; desc = "Paste JPEG from clipboard"; }
        { on = "D"; run = ''shell "trash-put -- %s"''; desc = "Trash"; }
        { on = [ "o" "z" ]; run = "sort random"; desc = "Sort random"; }
        { on = [ "o" "s" ]; run = "sort size --reverse"; desc = "Sort size desc"; }
        { on = [ "o" "S" ]; run = "sort size"; desc = "Sort size asc"; }
        { on = [ "o" "m" ]; run = "sort mtime --reverse"; desc = "Sort mtime desc"; }
        { on = [ "o" "M" ]; run = "sort mtime"; desc = "Sort mtime asc"; }
        { on = [ "o" "c" ]; run = "sort mtime"; desc = "Sort mtime asc (was lf ctime)"; }
        { on = [ "o" "C" ]; run = "sort mtime --reverse"; desc = "Sort mtime desc (was lf ctime)"; }
        { on = "e"; run = ''shell "$EDITOR %s" --block''; desc = "Edit in $EDITOR"; }
        { on = [ "b" "w" ]; run = ''shell "setbg %s" --orphan''; desc = "Set wallpaper"; }
        { on = "M"; run = "create --dir"; desc = "mkdir"; }
        { on = "U"; run = ''shell "unp -U %s" --block''; desc = "Unzip"; }
        { on = "H"; run = "back"; desc = "History back"; }
        { on = "L"; run = "forward"; desc = "History forward"; }
        { on = "<PageDown>"; run = "arrow 50%"; desc = "Half page down"; }
        { on = "<PageUp>"; run = "arrow -50%"; desc = "Half page up"; }
        { on = "<C-f>"; run = "arrow 50%"; desc = "Half page down"; }
        { on = "<C-b>"; run = "arrow -50%"; desc = "Half page up"; }
        { on = "l"; run = "open"; desc = "Enter dir or open file"; }
        { on = "<Right>"; run = "open"; desc = "Enter dir or open file"; }
      ];
    };
  };
}
