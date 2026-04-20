{ pkgs, ... }:

let
  preview = pkgs.writeShellScriptBin "lf-preview" (builtins.readFile ../../.config/lf/preview);
  cleaner = pkgs.writeShellScriptBin "lf-cleaner" (builtins.readFile ../../.config/lf/cleaner);
  opener = pkgs.writeShellScriptBin "lf-opener" (builtins.readFile ../../.config/lf/opener);
in
{
  programs.lf = {
    enable = true;
    
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
      incsearch = true;
      incfilter = true;
      mouse = true;
      timefmt = "2006 Jan _2 15:04:05";
    };

    commands = {
      open = "$${opener}/bin/lf-opener \"$f\"";
      yank-path = "$printf '%s' \"$f\" | wl-copy";
      yank-name = "$printf '%s' \"$(basename \"$f\")\" | wl-copy";
      yank-bytes = "%{{ ic \"$f\" }}";
      
      sort-size = ":set sortby size; set info size";
      sort-mtime = ":set sortby time; set info time";
      sort-ctime = ":set sortby ctime; set info ctime";
      sort-atime = ":set sortby atime; set info atime";
      sort-name = ":set sortby name; set info";
      sort-ext = ":set sortby ext; set info";
      
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
      
      on-cd = ''&{{
        zoxide add "$PWD"
        echo "$PWD" > /tmp/lf_current_dir
      }}'';
    };

    keybindings = {
      k = "up";
      j = "down";
      h = "updir";
      l = "open";
      "<enter>" = "open";
      
      "gh" = "cd ~";
      "gD" = "cd ~/Downloads";
      "gc" = "cd ~/.config";
      "gl" = "cd ~/.config/lf";
      "gp" = "cd ~/projects";
      "gd" = "cd ~/disk";
      
      "<pagedown>" = "down 50%";
      "<pageup>" = "up 50%";
      "<C-f>" = "down 50%";
      "<C-b>" = "up 50%";
      
      "a" = "rename";
      "cw" = "rename";
      "A" = ":rename";
      "I" = "file-info";
      "i" = "%{{ sxiv -ab -- $(dirname \"$f\") }}";
      
      "P" = "yank-path";
      "<c-n>" = "yank-name";
      "B" = "yank-bytes";
      
      "|" = ":filter";
      ";" = "set hidden!";
      
      "D" = "$${pkgs.trash-cli}/bin/trash-put \"$fx\"";
      "<C-t>" = "tab-new";
      "<C-w>" = "tab-close";
      "gn" = "tab-new";
      "gt" = "tab-next";
      "gT" = "tab-prev";
      
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
      
      "z" = ''%{{
        result="$(zoxide query -i)"
        lf -remote "send $id cd \"$result\""
      }}'';
    };

    extraConfig = ''
      set previewer ${preview}/bin/lf-preview
      set cleaner ${cleaner}/bin/lf-cleaner
    '';
  };
}
