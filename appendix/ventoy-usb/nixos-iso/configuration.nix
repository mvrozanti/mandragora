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

  # ---- Networking ----
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;

  # ---- Auto-mount Ventoy exFAT partition (read/write) ----
  fileSystems."/mnt/ventoy" = {
    device = "/dev/disk/by-label/Ventoy";
    fsType = "exfat";
    options = [ "nofail" "x-systemd.automount" "x-systemd.device-timeout=5s" "rw" ];
  };

  # ---- Dotfiles staged in /etc/skel (copied to ~ by shell init) ----
  environment.etc = {
    "skel/.bash_aliases".source = ./root-dotfiles/.bash_aliases;
    "skel/.zshrc".source = ./root-dotfiles/.zshrc;
    "skel/.tmux.conf".source = ./root-dotfiles/.tmux.conf;
    "skel/.config/nvim".source = ./root-dotfiles/.config/nvim;
    "skel/README.md".source = ./root-dotfiles/README.md;
  };

  # ---- Persistent state via ext4 image on USB ----
  systemd.services.mount-persist = {
    description = "Mount persistent ext4 image from USB";
    wantedBy = [ "multi-user.target" ];
    after = [ "mnt-ventoy.automount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "mount-persist" ''
        IMG="/mnt/ventoy/persistence/nixos_persistence.dat"
        MNT="/persist"
        [ -f "$IMG" ] || exit 0
        mkdir -p "$MNT"
        LOOP=$(losetup --find --show "$IMG") || exit 0
        mount "$LOOP" "$MNT"
        mkdir -p "$MNT"/{npm-global/bin,claude,ssh,zsh-history}
        chown -R nixos:users "$MNT"
        chmod 755 "$MNT" "$MNT"/npm-global "$MNT"/npm-global/bin "$MNT"/zsh-history
        chmod 700 "$MNT"/claude "$MNT"/ssh

        NHOME="/home/nixos"
        [ -d "$NHOME" ] || exit 0
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
      ExecStart = pkgs.writeShellScript "install-ai-tools" ''
        export HOME="/home/nixos"
        export npm_config_prefix="/persist/npm-global"
        if ! [ -x /persist/npm-global/bin/claude ]; then
          npm install -g @anthropic-ai/claude-code @google/gemini-cli @qwen-code/qwen-code 2>/dev/null || true
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

    # provision dotfiles from /etc/skel (one-time, idempotent)
    for f in .bash_aliases .tmux.conf .zshrc README.md; do
      [ ! -f ~/$f ] && [ -f /etc/skel/$f ] && cp /etc/skel/$f ~/$f 2>/dev/null || true
    done
    [ ! -d ~/.config/nvim ] && [ -d /etc/skel/.config/nvim ] && \
      mkdir -p ~/.config && cp -r /etc/skel/.config/nvim ~/.config/nvim 2>/dev/null || true

    [ -f ~/.bash_aliases ] && source ~/.bash_aliases

    alias diag='/mnt/ventoy/toolbox/hw-diag.sh'
    alias gpucheck='/mnt/ventoy/toolbox/gpu-stress.sh'
    alias ventoy='cd /mnt/ventoy'
    alias repo='cd /mnt/ventoy/docs/mandragora-nixos'

    echo ""
    echo "══════════════════════════════════════════"
    echo "  MANDRAGORA BOOTSTRAP USB  (NixOS)"
    echo "══════════════════════════════════════════"
    echo "  cat ~/README.md   full install guide"
    echo "  nmtui             connect to WiFi"
    echo ""
  '';

  # ---- Shell init (zsh) ----
  programs.zsh.interactiveShellInit = ''
    export PATH="/persist/npm-global/bin:$HOME/.npm-global/bin:$PATH"
    export npm_config_prefix="/persist/npm-global"
    [ -d /persist/zsh-history ] && export HISTFILE="/persist/zsh-history/.zsh_history"

    # provision dotfiles from /etc/skel (one-time, idempotent)
    for f in .bash_aliases .tmux.conf README.md; do
      [ ! -f ~/$f ] && [ -f /etc/skel/$f ] && cp /etc/skel/$f ~/$f 2>/dev/null || true
    done
    [ ! -d ~/.config/nvim ] && [ -d /etc/skel/.config/nvim ] && \
      mkdir -p ~/.config && cp -r /etc/skel/.config/nvim ~/.config/nvim 2>/dev/null || true

    [ -f ~/.bash_aliases ] && source ~/.bash_aliases

    alias diag='/mnt/ventoy/toolbox/hw-diag.sh'
    alias gpucheck='/mnt/ventoy/toolbox/gpu-stress.sh'
    alias ventoy='cd /mnt/ventoy'
    alias repo='cd /mnt/ventoy/docs/mandragora-nixos'

    if [[ -z "$_MOTD_SHOWN" ]] && [[ -t 0 ]]; then
      export _MOTD_SHOWN=1
      echo ""
      echo "══════════════════════════════════════════"
      echo "  MANDRAGORA BOOTSTRAP USB  (NixOS)"
      echo "══════════════════════════════════════════"
      echo "  cat ~/README.md   full install guide"
      echo "  nmtui             connect to WiFi"
      echo "  claude | gemini   AI assistants"
      echo "  diag | gpucheck   hardware diagnostics"
      echo "  repo              cd to flake on USB"
      echo ""
    fi
  '';
}
