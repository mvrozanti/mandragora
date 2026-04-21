{ pkgs, lib, ... }:

let
  # zX directory shortcuts: edit ./zx-dirs.nix — it's the single source
  # of truth shared with modules/user/zsh.nix. Do not add z<letter> bindings here.
  zxDirs = import ./zx-dirs.nix;
  normalize = v: if builtins.isString v then { path = v; lfPrefix = "z"; } else { lfPrefix = "z"; } // v;
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

    ldflags = [ "-s" "-w" "-X main.gVersion=${version}" ];

    doCheck = false;
  };

  preview = pkgs.writeShellScriptBin "lf-preview" (builtins.readFile ../../.config/lf/preview);
  cleaner = pkgs.writeShellScriptBin "lf-cleaner" (builtins.readFile ../../.config/lf/cleaner);
  opener = pkgs.writeShellScriptBin "lf-opener" (builtins.readFile ../../.config/lf/opener);

  # Wrapper that starts an ueberzugpp daemon, runs lf, and tears it down on exit.
  # Exports UEBERZUG_SOCKET so the previewer/cleaner can send add/remove commands.
  lfub = pkgs.writeShellScriptBin "lfub" ''
    #!${pkgs.bash}/bin/bash
    LOG=/tmp/lf-cleaner.log
    export UB_PID_FILE="/tmp/.$(uuidgen).ueberzug-pid"
    : > "$UB_PID_FILE"
    cleanup() {
      if [ -n "''${UB_PID:-}" ] && [ -S "''${UEBERZUG_SOCKET:-}" ]; then
        ${pkgs.ueberzugpp}/bin/ueberzugpp cmd -s "$UEBERZUG_SOCKET" -a exit 2>/dev/null
      fi
      rm -f "$UB_PID_FILE" 2>/dev/null
    }
    trap cleanup HUP INT QUIT TERM PWR EXIT

    printf '[%s] lfub launch (WAYLAND_DISPLAY=%s DISPLAY=%s)\n' "$(date +%H:%M:%S.%N)" "''${WAYLAND_DISPLAY:-unset}" "''${DISPLAY:-unset}" >> "$LOG"

    # Start the ueberzugpp daemon; --no-stdin daemonizes and writes the pid
    # to --pid-file. Errors from the startup itself are captured below.
    ${pkgs.ueberzugpp}/bin/ueberzugpp layer \
      --no-stdin \
      --use-escape-codes \
      --output wayland \
      --pid-file "$UB_PID_FILE" \
      >>"$LOG" 2>&1

    UB_PID=$(cat "$UB_PID_FILE" 2>/dev/null)
    if [ -z "$UB_PID" ]; then
      printf '[%s] lfub: ueberzugpp failed to start (output=wayland)\n' "$(date +%H:%M:%S.%N)" >> "$LOG"
    else
      export UB_PID
      export UEBERZUG_SOCKET="/tmp/ueberzugpp-$UB_PID.socket"
      printf '[%s] lfub: ueberzugpp pid=%s socket=%s\n' "$(date +%H:%M:%S.%N)" "$UB_PID" "$UEBERZUG_SOCKET" >> "$LOG"
    fi

    ${lf-ub}/bin/lf "$@"
  '';
in
{
  home.packages = [ lfub ];

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
        zoxide add \"$PWD\"
        echo \"$PWD\" > /tmp/lf_current_dir
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
      "i" = "%{{ sxiv -ab -- $(dirname \"$f\") }}";
      
      "P" = "yank-path";
      "<c-n>" = "yank-name";
      "B" = "yank-bytes";
      
      "|" = ":filter";
      ";" = "set hidden!";
      
      "D" = ''%echo "$fx" | xargs -d '\n' -r ${pkgs.trash-cli}/bin/trash-put --'';
      "<C-t>" = "tab-new";
      "<C-w>" = "tab-close";
      "gn" = "tab-new";
      "gt" = "cd /mnt/toshiba";
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
      
      "Z" = ''%{{
        result=\"$(zoxide query -i)\"
        lf -remote \"send $id cd \\"$result\\"\"
      }}'';
    };

    extraConfig = ''
      set previewer ${preview}/bin/lf-preview
      set cleaner ${cleaner}/bin/lf-cleaner
    '';
  };
}
