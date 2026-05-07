{ config, lib, pkgs, ... }:

{
  imports = [
    ../../pkgs/overlays.nix
  ];

  mandragora.profile = "wsl";

  wsl = {
    enable = true;
    defaultUser = "m";
    startMenuLaunchers = true;
    wslConf = {
      automount.root = "/mnt";
      interop.enabled = true;
      interop.appendWindowsPath = true;
      network.generateResolvConf = true;
    };
  };

  networking.hostName = "mandragora-wsl";
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nixpkgs.config.allowUnfree = true;

  users.users.m = {
    isNormalUser = true;
    description = "Mandragora Primary User";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    git
    wget
    curl
    htop
    btop
    tree
    jq
    fastfetch
    rtk
    tmux
    fzf
    ripgrep
    fd
    bat
    eza
    zoxide
    gh
  ];

  programs.zsh.enable = true;
  programs.git.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.m = { ... }: {
    home.stateVersion = "24.05";
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        ll = "eza -la --icons";
        ls = "eza --icons";
        cat = "bat -p";
        gs = "git status";
        gd = "git diff";
        nrs = "sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-wsl";
      };
      initContent = ''
        export PS1='%F{cyan}mandragora-wsl%f:%F{green}%~%f%# '
        eval "$(zoxide init zsh)"
      '';
    };
  };

  system.stateVersion = "24.05";
}
