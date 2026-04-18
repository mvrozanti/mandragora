{ config, pkgs, lib, ... }:

{
  isoImage.isoBaseName = "mandragora-nixos";
  nixpkgs.config.allowUnfree = true;
  networking.hostName = "mandragora-usb";

  # ---- Packages ----
  environment.systemPackages = with pkgs; [
    # monitoring
    htop btop fastfetch
    # hw diagnostics
    lm_sensors smartmontools nvme-cli dmidecode pciutils usbutils
    # gpu
    mesa-utils vulkan-tools
    # rgb
    openrgb
    # network
    nmap iperf3
    # ai prereq
    nodejs
    # editor + multiplexer
    neovim tmux
    # shell + file manager + wifi
    zsh lf impala
    # shell productivity
    fzf tree pv bat ripgrep trash-cli
    # diagnostics + recovery
    testdisk ddrescue mtr
    # file listing
    eza
  ];

  # ---- Root user shell ----
  users.users.root.shell = pkgs.zsh;

  # ---- Networking ----
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;

  # ---- Auto-mount Ventoy exFAT partition ----
  fileSystems."/mnt/ventoy" = {
    device = "/dev/disk/by-label/Ventoy";
    fsType = "exfat";
    options = [ "nofail" "x-systemd.automount" "x-systemd.device-timeout=5s" ];
  };

  # ---- Dotfiles ----
  environment.etc = {
    "skel/.bash_aliases".source = ./root-dotfiles/.bash_aliases;
    "skel/.zshrc".source = ./root-dotfiles/.zshrc;
    "skel/.tmux.conf".source = ./root-dotfiles/.tmux.conf;
    "skel/.config/nvim".source = ./root-dotfiles/.config/nvim;
  };

  # ---- Shell ----
  programs.bash = {
    interactiveShellInit = ''
      export PS1='[MANDRAGORA] \u@\h \w \$ '
      export EDITOR='nvim'
      export VISUAL='nvim'
      export BROWSER='firefox'
      stty -ixon

      # provision dotfiles for root (one-time, idempotent)
      for f in .bash_aliases .zshrc .tmux.conf; do
        if [[ ! -f ~/$f && -f /etc/skel/$f ]]; then
          cp /etc/skel/$f ~/$f 2>/dev/null || true
        fi
      done
      if [[ ! -d ~/.config/nvim && -d /etc/skel/.config/nvim ]]; then
        cp -r /etc/skel/.config/nvim ~/.config/nvim 2>/dev/null || true
      fi

      # source bash_aliases (bash uses these)
      if [[ -f ~/.bash_aliases ]]; then
        source ~/.bash_aliases
      fi

      alias diag='/mnt/ventoy/toolbox/hw-diag.sh'
      alias gpucheck='/mnt/ventoy/toolbox/gpu-stress.sh'
      alias ventoy='cd /mnt/ventoy'

      # tmux auto-start (skip if already inside tmux or SSH)
      if [[ -z "$TMUX" && -z "$SSH_CONNECTION" && -t 0 ]]; then
        exec tmux
      fi

      # one-time AI tools install (persists via persistence image)
      if command -v npm &>/dev/null && ! command -v claude &>/dev/null; then
        if ping -c1 -W3 nixos.org &>/dev/null 2>&1; then
          echo "[*] Installing AI tools..."
          npm install -g @anthropic-ai/claude-code @google/gemini-cli @qwen-code/qwen-code 2>/dev/null || true
        fi
      fi

      echo ""
      echo "══════════════════════════════════════════"
      echo "  MANDRAGORA BOOTSTRAP USB  (NixOS)"
      echo "══════════════════════════════════════════"
      echo "  claude | gemini | qwen | diag | gpucheck"
      echo "  nvim | tmux | sensors | nmtui | htop | btop"
      echo ""
    '';
  };
}
