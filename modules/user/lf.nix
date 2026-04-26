{ pkgs, lib, ... }:

let
  # zX directory shortcuts: edit ./zx-dirs.nix — it's the single source
  # of truth shared with modules/user/zsh.nix. Do not add z<letter> bindings here.
  zxDirs = import ./zx-dirs.nix;
  normalize = v: if builtins.isString v then { path = v; lfPrefix = "g"; } else { lfPrefix = "g"; } // v;
  zxBindings = lib.mapAttrs' (k: v:
    let e = normalize v; in lib.nameValuePair "${e.lfPrefix}${k}" "cd ${e.path}"
  ) zxDirs;

  lf-ub = pkgs.buildGoModule rec {
    pname = "lf-ub";
    version = "master";

    src = pkgs.fetchFromGitHub {
      owner = "mvrozanti";
      repo = "lf";
      rev = "master";
      sha256 = "10d08b87gvizsyzy8pq0bdc06lmkk78p8609563bdl7xy5njcyyb";
    };

    vendorHash = "sha256-U2D+VAAj26s4Dz1JU4hv/xoZaVfOMIcVBWKLNUhlYxA=";

    patches = [ ./lf-autodirsize.patch ];

    ldflags = [ "-s" "-w" "-X main.gVersion=${version}" ];

    doCheck = false;
  };

  preview = pkgs.writeShellScriptBin "lf-preview" (builtins.readFile ../../.config/lf/preview);
  cleaner = pkgs.writeShellScriptBin "lf-cleaner" (builtins.readFile ../../.config/lf/cleaner);
  opener = pkgs.writeShellScriptBin "lf-opener" (builtins.readFile ../../.config/lf/opener);
in
{
  programs.lf = {
    enable = true;
    package = lf-ub;
    
    settings = {
      preview = true;
      drawbox = false;
      icons = true;
      ignorecase = true;
      dirfirst = true;
      scrolloff = 8;
      ratios = "1:2:3";
      sortby = "ctime";
      reverse = true;
      info = "size";
      dircounts = false;
      incsearch = true;
      incfilter = true;
      mouse = true;
      watch = false;
      timefmt = "2006 Jan _2 15:04:05";
    };

    commands = {
      open = "\$${opener}/bin/lf-opener \"$f\"";
      yank-path = "$printf '%s' \"$f\" | wl-copy";
      yank-name = "$printf '%s' \"$(basename \"$f\")\" | wl-copy";
      yank-bytes = "%{{ ic \"$f\" }}";
      
      sort-size = ":set sortby size; set info size";
      sort-mtime = ":set sortby time; set info size:time";
      sort-ctime = ":set sortby ctime; set info size:ctime";
      sort-atime = ":set sortby atime; set info size:atime";
      sort-name = ":set sortby name; set info size";
      sort-ext = ":set sortby ext; set info size";
      
      paste-image = "$wl-paste -t image/png > \"$(dirname $fx)/$(date +%s).png\"";
      paste-jpeg = "$wl-paste -t image/jpeg > \"$(dirname $fx)/$(date +%s).jpg\"";
      
      file-info = "$file $fx | less";
      
      mkdir = ''%{{
        echo ":!mkdir "
        read dir
        [ -n "$dir" ] && mkdir -p "$dir"
        lf -remote "send $id reload"
      }}'';
      
      unzip = "%{{ unp -U \"$fx\" }}";

      on-select = "redraw";

      on-cd = ''&{{
        history_file="/tmp/lf-history-$id"
        index_file="/tmp/lf-history-index-$id"
        nav_flag="/tmp/lf-history-nav-$id"
        if [ -f "$nav_flag" ]; then
          rm -f "$nav_flag"
        else
          mapfile -t history_array < "$history_file"
          current_index=$(cat "$index_file")
          if [ "$current_index" -lt "$(( ''${#history_array[@]} - 1 ))" ]; then
            history_array=("''${history_array[@]:0:$((current_index + 1))}")
            printf "%s\n" "''${history_array[@]}" > "$history_file"
          fi
          echo "$PWD" >> "$history_file"
          new_index=$(( ''${#history_array[@]} ))
          echo "$new_index" > "$index_file"
        fi
        zoxide add "$PWD"
        echo "$PWD" > /tmp/lf_current_dir
      }}'';

      history-back = ''%{{
        history_file="/tmp/lf-history-$id"
        index_file="/tmp/lf-history-index-$id"
        nav_flag="/tmp/lf-history-nav-$id"
        [ -f "$history_file" ] || exit 0
        mapfile -t history_array < "$history_file"
        current_index=$(cat "$index_file")
        if [ "$current_index" -gt 0 ]; then
          new_index=$((current_index - 1))
          echo "$new_index" > "$index_file"
          touch "$nav_flag"
          target_dir="''${history_array[$new_index]}"
          lf -remote "send $id cd \"$target_dir\""
        fi
      }}'';

      history-forward = ''%{{
        history_file="/tmp/lf-history-$id"
        index_file="/tmp/lf-history-index-$id"
        nav_flag="/tmp/lf-history-nav-$id"
        [ -f "$history_file" ] || exit 0
        mapfile -t history_array < "$history_file"
        current_index=$(cat "$index_file")
        max_index=$(( ''${#history_array[@]} - 1 ))
        if [ "$current_index" -lt "$max_index" ]; then
          new_index=$((current_index + 1))
          echo "$new_index" > "$index_file"
          touch "$nav_flag"
          target_dir="''${history_array[$new_index]}"
          lf -remote "send $id cd \"$target_dir\""
        fi
      }}'';
    };

    keybindings = zxBindings // {
      k = "up";
      j = "down";
      h = "updir";
      l = "open";
      "<enter>" = "open";

      "<pagedown>" = "down 50%";
      "<pageup>" = "up 50%";
      "<C-f>" = "down 50%";
      "<C-b>" = "up 50%";
      
      "a" = "rename";
      "cw" = "rename";
      "A" = ":rename";
      "I" = "file-info";
      "i" = "%{{ nsxiv -ab -- $(dirname \"$f\") }}";
      
      "P" = "yank-path";
      "N" = "yank-name";
      "<c-n>" = "yank-name";
      "B" = "yank-bytes";
      
      "|" = ":filter";
      ";" = "set hidden!";
      
      "D" = ''%echo "$fx" | xargs -d '\n' -r ${pkgs.trash-cli}/bin/trash-put --'';
      "gt" = "cd /mnt/toshiba";
      
      "oz" = ":set sortby random; set reverse false";
      "os" = "sort-size; set reverse true";
      "oS" = "sort-size; set reverse false";
      "om" = "sort-mtime; set reverse true";
      "oM" = "sort-mtime; set reverse false";
      "oc" = "sort-ctime; set reverse false";
      "oC" = "sort-ctime; set reverse true";
      
      "e" = "$$EDITOR \"$fx\"";
      "bw" = "$setbg \"$fx\" &";
      "pB" = "paste-image";
      "pb" = "paste-jpeg";
      "M" = "mkdir";
      "U" = "unzip";
      "H" = "history-back";
      "L" = "history-forward";
    };

    extraConfig = ''
      set previewer ${preview}/bin/lf-preview
      set cleaner ${cleaner}/bin/lf-cleaner
      ''${{
        [ ! -f "/tmp/lf-history-$id" ] && echo "$PWD" > "/tmp/lf-history-$id"
        [ ! -f "/tmp/lf-history-index-$id" ] && echo "0" > "/tmp/lf-history-index-$id"
      }}
      cmd zoxide-jump ''${{
        result=$(zoxide query -i)
        [ -n "$result" ] && lf -remote "send $id cd \"$result\""
      }}
      map z zoxide-jump
    '';
  };

  xdg.configFile."lf/icons".source = ../../.config/lf/icons;
}
