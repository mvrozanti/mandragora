{ config, pkgs, lib, ... }:

{
  isoImage.isoBaseName = lib.mkForce "mandragora-nixos";
  nixpkgs.config.allowUnfree = true;
  networking.hostName = "mandragora-usb";

  # ---- Flakes + nix-command enabled globally ----
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ---- FHS compat for non-NixOS binaries (Claude Code's native binary) ----
  programs.nix-ld.enable = true;

  # ---- Packages ----
  environment.systemPackages = with pkgs; [
    # monitoring
    htop btop fastfetch
    # hw diagnostics
    lm_sensors smartmontools nvme-cli dmidecode pciutils usbutils
    # gpu
    mesa-demos vulkan-tools
    # rgb
    openrgb
    # network
    nmap iperf3
    # ai prereq
    nodejs
    # secrets
    sops age
    # editor + multiplexer
    neovim tmux
    # shell + file manager + wifi
    zsh lf impala
    # shell productivity
    fzf tree pv bat ripgrep trash-cli eza
    # diagnostics + recovery
    testdisk ddrescue mtr
    # partitioning
    parted btrfs-progs dosfstools
    # git
    git
  ];

  # ---- Both root and nixos user get zsh ----
  users.users.root.shell = pkgs.zsh;
  users.users.nixos.shell = lib.mkForce pkgs.zsh;

  # ---- Zsh ----
  programs.zsh.enable = true;

  # ---- exFAT support (needed to mount Ventoy data partition) ----
  boot.supportedFilesystems = [ "exfat" ];

  # ---- Networking ----
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;

  # ---- Mount Ventoy exFAT partition (retry until USB is enumerated) ----
  systemd.services.mount-ventoy = {
    description = "Mount Ventoy USB data partition";
    wantedBy = [ "multi-user.target" ];
    before = [ "mount-persist.service" "getty@tty1.service" ];
    path = with pkgs; [ util-linux exfatprogs coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "mount-ventoy" ''
        mkdir -p /mnt/ventoy
        echo "[ventoy] Starting — PATH=$PATH"

        DEV=""
        N=0
        while [ $N -lt 15 ]; do
          if [ -e /dev/disk/by-label/Ventoy ]; then
            DEV="/dev/disk/by-label/Ventoy"
            break
          fi
          N=$((N + 1))
          sleep 1
        done

        if [ -z "$DEV" ]; then
          for d in /dev/sd?1 /dev/sd?2 /dev/sd?3; do
            if [ -b "$d" ]; then
              TYPE=$(blkid -o value -s TYPE "$d" 2>/dev/null || true)
              if [ "$TYPE" = "exfat" ]; then
                DEV="$d"
                break
              fi
            fi
          done
        fi

        if [ -z "$DEV" ]; then
          echo "[ventoy] No Ventoy partition found"
          lsblk -f 2>&1 || true
          exit 1
        fi

        echo "[ventoy] Found $DEV, attempting mount..."
        if mount "$DEV" /mnt/ventoy -o rw 2>&1; then
          echo "[ventoy] Mounted $DEV at /mnt/ventoy"
          exit 0
        fi

        echo "[ventoy] Direct mount failed (blockdev locked by Ventoy device mapper)"
        echo "[ventoy] Bypassing via loop+offset on whole disk..."

        REAL_DEV=$(readlink -f "$DEV")
        DISK_DEV="$REAL_DEV"
        while [ "''${DISK_DEV%[0-9]}" != "$DISK_DEV" ]; do DISK_DEV="''${DISK_DEV%[0-9]}"; done
        PART_NAME=$(basename "$REAL_DEV")
        DISK_NAME=$(basename "$DISK_DEV")

        START=$(cat /sys/block/$DISK_NAME/$PART_NAME/start 2>/dev/null || true)
        SIZE=$(cat /sys/block/$DISK_NAME/$PART_NAME/size 2>/dev/null || true)

        if [ -n "$START" ] && [ -n "$SIZE" ]; then
          OFFSET=$((START * 512))
          SIZELIMIT=$((SIZE * 512))
          echo "[ventoy] Partition $PART_NAME: start=$START size=$SIZE offset=$OFFSET sizelimit=$SIZELIMIT"
          LOOP=$(losetup --find --show --offset "$OFFSET" --sizelimit "$SIZELIMIT" "$DISK_DEV" 2>&1) || true
          if [ -b "$LOOP" ]; then
            echo "[ventoy] Created loop device $LOOP"
            if mount "$LOOP" /mnt/ventoy -o rw 2>&1; then
              echo "[ventoy] Mounted via loop+offset ($LOOP)"
              exit 0
            fi
            echo "[ventoy] Loop mount also failed"
            losetup -d "$LOOP" 2>/dev/null || true
          else
            echo "[ventoy] losetup failed: $LOOP"
          fi
        else
          echo "[ventoy] Could not read partition geometry from /sys/block/$DISK_NAME/$PART_NAME/"
        fi

        echo "[ventoy] All mount attempts failed"
        lsblk -f 2>&1 || true
        exit 1
      '';
    };
  };

  # ---- Dotfiles staged in /etc/skel (copied to ~ by provision-dotfiles service) ----
  environment.etc = {
    "skel/.bash_aliases".source = ./root-dotfiles/.bash_aliases;
    "skel/.zshrc".source = ./root-dotfiles/.zshrc;
    "skel/.tmux.conf".source = ./root-dotfiles/.tmux.conf;
    "skel/.config/nvim".source = ./root-dotfiles/.config/nvim;
    "skel/README.md".source = ./root-dotfiles/README.md;
    "skel/.claude_env".source = ./root-dotfiles/.claude_env;
  };

  # ---- Provision dotfiles from /etc/skel to user homes (runs before login) ----
  systemd.services.provision-dotfiles = {
    description = "Copy dotfiles from /etc/skel to user homes";
    wantedBy = [ "multi-user.target" ];
    before = [ "getty@tty1.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "provision-dotfiles" ''
        log() { echo "[dotfiles] $1"; }
        for UHOME in /home/nixos /root; do
          [ -d "$UHOME" ] || continue
          log "Provisioning $UHOME..."
          for f in .bash_aliases .zshrc .tmux.conf .claude_env README.md; do
            if [ ! -f "$UHOME/$f" ] && [ -f "/etc/skel/$f" ]; then
              cp "/etc/skel/$f" "$UHOME/$f" && log "  copied $f" || log "  FAILED to copy $f"
            fi
          done
          if [ ! -d "$UHOME/.config/nvim" ] && [ -d "/etc/skel/.config/nvim" ]; then
            mkdir -p "$UHOME/.config"
            cp -r "/etc/skel/.config/nvim" "$UHOME/.config/nvim" && log "  copied .config/nvim" || log "  FAILED .config/nvim"
          fi
        done
        chown -R nixos:users /home/nixos 2>/dev/null || true
        log "Done. /etc/skel contents:" && ls -la /etc/skel/
        log "/home/nixos contents:" && ls -la /home/nixos/
      '';
    };
  };

  # ---- Persistent state via ext4 image on USB ----
  systemd.services.mount-persist = {
    description = "Mount persistent ext4 image from USB";
    wantedBy = [ "multi-user.target" ];
    after = [ "mount-ventoy.service" ];
    wants = [ "mount-ventoy.service" ];
    before = [ "getty@tty1.service" ];
    path = [ pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "mount-persist" ''
        IMG="/mnt/ventoy/persistence/nixos_persistence.dat"
        MNT="/persist"
        if [ ! -f "$IMG" ]; then
          echo "[persist] No persist image at $IMG — /mnt/ventoy mounted: $(mountpoint -q /mnt/ventoy 2>/dev/null && echo yes || echo NO)"
          echo "[persist] /mnt/ventoy contents:" && ls /mnt/ventoy/ 2>&1 || true
          exit 0
        fi
        mkdir -p "$MNT"
        LOOP=$(losetup --find --show "$IMG") || { echo "[persist] losetup failed for $IMG"; exit 1; }
        if ! mount "$LOOP" "$MNT"; then
          echo "[persist] mount failed for $LOOP"
          losetup -d "$LOOP" 2>/dev/null || true
          exit 1
        fi
        echo "[persist] Mounted $IMG at $MNT via $LOOP"
        mkdir -p "$MNT"/{npm-global/bin,claude,ssh,zsh-history}
        chown -R nixos:users "$MNT"
        chmod 755 "$MNT" "$MNT"/npm-global "$MNT"/npm-global/bin "$MNT"/zsh-history
        chmod 700 "$MNT"/claude "$MNT"/ssh

        NHOME="/home/nixos"
        [ -d "$NHOME" ] || exit 0
        ln -sfn /mnt/ventoy/docs/mandragora-nixos "$NHOME/mandragora-nixos"
        ln -sfn "$MNT/npm-global" "$NHOME/.npm-global"
        mkdir -p "$NHOME/.claude"
        [ -f "$MNT/claude/.credentials.json" ] && \
          ln -sfn "$MNT/claude/.credentials.json" "$NHOME/.claude/.credentials.json"
        if [ -d "$MNT/ssh" ] && ls "$MNT/ssh"/id_* &>/dev/null; then
          mkdir -p "$NHOME/.ssh"
          ln -sfn "$MNT/ssh"/* "$NHOME/.ssh/"
          chmod 700 "$NHOME/.ssh"
        fi
        chown -R nixos:users "$NHOME/.npm-global" "$NHOME/.claude" "$NHOME/.ssh" 2>/dev/null || true

        ln -sfn "$MNT/npm-global" /root/.npm-global
        mkdir -p /root/.claude
        [ -f "$MNT/claude/.credentials.json" ] && \
          ln -sfn "$MNT/claude/.credentials.json" /root/.claude/.credentials.json
        if [ -d "$MNT/ssh" ] && ls "$MNT/ssh"/id_* &>/dev/null; then
          mkdir -p /root/.ssh
          ln -sfn "$MNT/ssh"/* /root/.ssh/
          chmod 700 /root/.ssh
        fi
      '';
    };
  };

  # ---- AI tools install (after persist is mounted) ----
  systemd.services.mandragora-ai-tools = {
    description = "Install AI coding tools via npm";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "mount-persist.service" ];
    wants = [ "network-online.target" "mount-persist.service" ];
    path = [ pkgs.nodejs ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "nixos";
      Group = "users";
      TimeoutStartSec = "15min";
      Environment = "HOME=/home/nixos npm_config_prefix=/persist/npm-global";
      ExecStart = pkgs.writeShellScript "install-ai-tools" ''
        [ -d /persist/npm-global ] || exit 0
        echo "[ai-tools] Installing/updating claude, gemini, qwen..."
        npm install -g @anthropic-ai/claude-code @google/gemini-cli @qwen-code/qwen-code 2>&1 || echo "[ai-tools] Install failed — connect to WiFi (nmtui) then: npm install -g @anthropic-ai/claude-code"
        echo "[ai-tools] claude version: $(claude --version 2>/dev/null || echo not installed)"
        if [ -f /persist/claude/.credentials.json ]; then
          mkdir -p ~/.claude
          ln -sfn /persist/claude/.credentials.json ~/.claude/.credentials.json
          echo "[ai-tools] Credential symlink restored"
        fi
      '';
    };
  };

  # ---- Shell init (bash) ----
  programs.bash.interactiveShellInit = ''
    export EDITOR='nvim'
    export VISUAL='nvim'
    export PATH="/persist/npm-global/bin:$HOME/.npm-global/bin:$PATH"
    export npm_config_prefix="/persist/npm-global"
    [ -d /persist/zsh-history ] && export HISTFILE="/persist/zsh-history/.bash_history"

    [ -f /persist/claude/oauth_token ] && export CLAUDE_CODE_OAUTH_TOKEN=$(cat /persist/claude/oauth_token)
    if [ -f /persist/claude/.credentials.json ]; then
      mkdir -p ~/.claude
      ln -sfn /persist/claude/.credentials.json ~/.claude/.credentials.json
    fi
    if [ -d /persist/ssh ] && ls /persist/ssh/id_* &>/dev/null; then
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      ln -sfn /persist/ssh/* ~/.ssh/ 2>/dev/null || true
    fi

    for f in .bash_aliases .tmux.conf .zshrc README.md; do
      if [ ! -f ~/"$f" ] && [ -f "/etc/skel/$f" ]; then
        cp "/etc/skel/$f" ~/"$f" || echo "[!] Failed to copy $f from /etc/skel"
      fi
    done
    if [ ! -d ~/.config/nvim ] && [ -d /etc/skel/.config/nvim ]; then
      mkdir -p ~/.config
      cp -r /etc/skel/.config/nvim ~/.config/nvim || echo "[!] Failed to copy .config/nvim"
    fi

    [ -f ~/.claude_env ] && source ~/.claude_env
    [ -f ~/.bash_aliases ] && source ~/.bash_aliases
    hash -r 2>/dev/null || true

    alias diag='/mnt/ventoy/toolbox/hw-diag.sh'
    alias gpucheck='/mnt/ventoy/toolbox/gpu-stress.sh'
    alias ventoy='cd /mnt/ventoy'
    alias repo='cd /mnt/ventoy/docs/mandragora-nixos'

    mandragora-debug() {
      local OUT="/tmp/mandragora-debug.log"
      {
        echo "========================================"
        echo "  MANDRAGORA DEBUG DUMP — $(date)"
        echo "========================================"
        echo ""
        echo "=== SHELL ==="
        echo "SHELL=$SHELL  USER=$(whoami)  HOME=$HOME"
        echo "PATH=$PATH"
        echo ""
        echo "=== BLOCK DEVICES ==="
        lsblk -f 2>&1 || true
        echo ""
        echo "=== MOUNTS ==="
        mount 2>&1 | grep -E "ventoy|persist|loop|nix" || echo "(no relevant mounts)"
        echo "Loop devices:" && losetup -a 2>&1 || echo "(none)"
        echo ""
        echo "/mnt/ventoy: $(mountpoint -q /mnt/ventoy 2>/dev/null && echo MOUNTED || echo NOT_MOUNTED)"
        ls /mnt/ventoy/ 2>&1 || true
        echo "/persist: $(mountpoint -q /persist 2>/dev/null && echo MOUNTED || echo NOT_MOUNTED)"
        ls /persist/ 2>&1 || true
        echo ""
        echo "=== OAUTH TOKEN ==="
        echo "env var: ''${CLAUDE_CODE_OAUTH_TOKEN:+SET (''${#CLAUDE_CODE_OAUTH_TOKEN} chars)}''${CLAUDE_CODE_OAUTH_TOKEN:-(NOT SET)}"
        echo "file:" && ls -la /persist/claude/oauth_token 2>&1 || echo "  (missing)"
        echo ""
        echo "=== CREDENTIALS ==="
        echo "~/.claude/:" && ls -la ~/.claude/ 2>&1 || echo "  (missing)"
        echo "/persist/claude/:" && ls -la /persist/claude/ 2>&1 || echo "  (missing)"
        [ -L ~/.claude/.credentials.json ] && echo "symlink: $(readlink ~/.claude/.credentials.json)" || echo "symlink: (none)"
        echo ""
        echo "=== SSH ==="
        echo "~/.ssh/:" && ls -la ~/.ssh/ 2>&1 || echo "  (missing)"
        echo "/persist/ssh/:" && ls -la /persist/ssh/ 2>&1 || echo "  (missing)"
        echo ""
        echo "=== AI TOOLS ==="
        echo "/persist/npm-global/bin/:" && ls -la /persist/npm-global/bin/ 2>&1 || echo "  (missing)"
        hash -r 2>/dev/null || true
        echo "claude: $(command -v claude 2>/dev/null || echo NOT_FOUND)"
        echo "gemini: $(command -v gemini 2>/dev/null || echo NOT_FOUND)"
        echo "npm prefix: $(npm config get prefix 2>/dev/null || echo unavailable)"
        echo ""
        echo "=== DOTFILES ==="
        for f in .zshrc .tmux.conf .bash_aliases README.md; do
          echo "~/$f: $([ -f ~/$f ] && echo OK || echo MISSING)  /etc/skel/$f: $([ -f /etc/skel/$f ] && echo OK || echo MISSING)"
        done
        echo ""
        echo "=== SYSTEMD SERVICES ==="
        for svc in mount-ventoy mount-persist provision-dotfiles mandragora-ai-tools; do
          RESULT=$(systemctl show -p Result $svc 2>/dev/null | cut -d= -f2)
          echo "$svc: $RESULT"
          [ "$RESULT" != "success" ] && journalctl -u $svc --no-pager 2>&1 | tail -10
        done
        echo ""
        echo "=== DMESG (usb/exfat/ventoy/loop) ==="
        dmesg 2>&1 | grep -iE "usb|exfat|ventoy|sdf|loop" | tail -15 || echo "(nothing)"
        echo ""
        echo "========================================"
      } 2>&1 | tee "$OUT"
      cp "$OUT" /mnt/ventoy/mandragora-debug.log 2>/dev/null && echo ">>> Saved to USB: /mnt/ventoy/mandragora-debug.log" || true
      echo ">>> Saved to: $OUT"
    }

    echo ""
    echo "══════════════════════════════════════════"
    echo "  MANDRAGORA BOOTSTRAP USB  (NixOS)"
    echo "══════════════════════════════════════════"
    echo "  cat ~/README.md   full install guide"
    echo "  nmtui             connect to WiFi"
    echo "  mandragora-debug  diagnose boot issues"
    echo ""
  '';

  # ---- Shell init (zsh) ----
  programs.zsh.interactiveShellInit = ''
    [ ! -f ~/.zshrc ] && [ -f /etc/skel/.zshrc ] && cp /etc/skel/.zshrc ~/.zshrc
    export PATH="/persist/npm-global/bin:$HOME/.npm-global/bin:$PATH"
    export npm_config_prefix="/persist/npm-global"
    [ -d /persist/zsh-history ] && export HISTFILE="/persist/zsh-history/.zsh_history"

    [ -f /persist/claude/oauth_token ] && export CLAUDE_CODE_OAUTH_TOKEN=$(cat /persist/claude/oauth_token)
    if [ -f /persist/claude/.credentials.json ]; then
      mkdir -p ~/.claude
      ln -sfn /persist/claude/.credentials.json ~/.claude/.credentials.json
    fi
    if [ -d /persist/ssh ] && ls /persist/ssh/id_* &>/dev/null; then
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      ln -sfn /persist/ssh/* ~/.ssh/ 2>/dev/null || true
    fi

    for f in .bash_aliases .tmux.conf README.md; do
      if [ ! -f ~/"$f" ] && [ -f "/etc/skel/$f" ]; then
        cp "/etc/skel/$f" ~/"$f" || echo "[!] Failed to copy $f from /etc/skel"
      fi
    done
    if [ ! -d ~/.config/nvim ] && [ -d /etc/skel/.config/nvim ]; then
      mkdir -p ~/.config
      cp -r /etc/skel/.config/nvim ~/.config/nvim || echo "[!] Failed to copy .config/nvim"
    fi

    [ -f ~/.claude_env ] && source ~/.claude_env
    [ -f ~/.bash_aliases ] && source ~/.bash_aliases
    rehash 2>/dev/null || true

    alias diag='/mnt/ventoy/toolbox/hw-diag.sh'
    alias gpucheck='/mnt/ventoy/toolbox/gpu-stress.sh'
    alias ventoy='cd /mnt/ventoy'
    alias repo='cd /mnt/ventoy/docs/mandragora-nixos'

    mandragora-debug() {
      local OUT="/tmp/mandragora-debug.log"
      {
        echo "========================================"
        echo "  MANDRAGORA DEBUG DUMP — $(date)"
        echo "========================================"

        echo ""
        echo "=== SHELL ==="
        echo "SHELL=$SHELL  USER=$(whoami)  HOME=$HOME"
        echo "PATH=$PATH"

        echo ""
        echo "=== BLOCK DEVICES ==="
        lsblk -f 2>&1 || true

        echo ""
        echo "=== MOUNTS ==="
        mount 2>&1 | grep -E "ventoy|persist|loop|nix" || echo "(no relevant mounts)"
        echo "Loop devices:" && losetup -a 2>&1 || echo "(none)"

        echo ""
        echo "/mnt/ventoy: $(mountpoint -q /mnt/ventoy 2>/dev/null && echo MOUNTED || echo NOT_MOUNTED)"
        ls /mnt/ventoy/ 2>&1 || true
        echo "/persist: $(mountpoint -q /persist 2>/dev/null && echo MOUNTED || echo NOT_MOUNTED)"
        ls /persist/ 2>&1 || true

        echo ""
        echo "=== OAUTH TOKEN ==="
        echo "env var: ''${CLAUDE_CODE_OAUTH_TOKEN:+SET (''${#CLAUDE_CODE_OAUTH_TOKEN} chars)}''${CLAUDE_CODE_OAUTH_TOKEN:-(NOT SET)}"
        echo "file:" && ls -la /persist/claude/oauth_token 2>&1 || echo "  (missing)"

        echo ""
        echo "=== CREDENTIALS ==="
        echo "~/.claude/:" && ls -la ~/.claude/ 2>&1 || echo "  (missing)"
        echo "/persist/claude/:" && ls -la /persist/claude/ 2>&1 || echo "  (missing)"
        [ -L ~/.claude/.credentials.json ] && echo "symlink: $(readlink ~/.claude/.credentials.json)" || echo "symlink: (none)"

        echo ""
        echo "=== SSH ==="
        echo "~/.ssh/:" && ls -la ~/.ssh/ 2>&1 || echo "  (missing)"
        echo "/persist/ssh/:" && ls -la /persist/ssh/ 2>&1 || echo "  (missing)"

        echo ""
        echo "=== AI TOOLS ==="
        echo "/persist/npm-global/bin/:" && ls -la /persist/npm-global/bin/ 2>&1 || echo "  (missing)"
        rehash 2>/dev/null || true
        echo "claude: $(command -v claude 2>/dev/null || echo NOT_FOUND)"
        echo "gemini: $(command -v gemini 2>/dev/null || echo NOT_FOUND)"
        echo "npm prefix: $(npm config get prefix 2>/dev/null || echo unavailable)"

        echo ""
        echo "=== DOTFILES ==="
        for f in .zshrc .tmux.conf .bash_aliases README.md; do
          echo "~/$f: $([ -f ~/$f ] && echo OK || echo MISSING)  /etc/skel/$f: $([ -f /etc/skel/$f ] && echo OK || echo MISSING)"
        done

        echo ""
        echo "=== SYSTEMD SERVICES ==="
        for svc in mount-ventoy mount-persist provision-dotfiles mandragora-ai-tools; do
          RESULT=$(systemctl show -p Result $svc 2>/dev/null | cut -d= -f2)
          echo "$svc: $RESULT"
          [ "$RESULT" != "success" ] && journalctl -u $svc --no-pager 2>&1 | tail -10
        done

        echo ""
        echo "=== DMESG (usb/exfat/ventoy/loop) ==="
        dmesg 2>&1 | grep -iE "usb|exfat|ventoy|sdf|loop" | tail -15 || echo "(nothing)"

        echo ""
        echo "========================================"
      } 2>&1 | tee "$OUT"
      cp "$OUT" /mnt/ventoy/mandragora-debug.log 2>/dev/null && echo ">>> Saved to USB: /mnt/ventoy/mandragora-debug.log" || true
      echo ">>> Saved to: $OUT"
    }

    if [[ -z "$_MOTD_SHOWN" ]] && [[ -t 0 ]]; then
      export _MOTD_SHOWN=1
      echo ""
      echo "══════════════════════════════════════════"
      echo "  MANDRAGORA BOOTSTRAP USB  (NixOS)"
      echo "══════════════════════════════════════════"
      echo "  cat ~/README.md   full install guide"
      echo "  nmtui             connect to WiFi"
      echo "  claude | gemini   AI assistants"
      echo "  mandragora-debug  diagnose boot issues"
      echo "  repo              cd to flake on USB"
      echo ""
    fi
  '';
}
