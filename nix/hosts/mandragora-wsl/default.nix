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
    interop.register = true;
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
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "pt_BR.UTF-8/UTF-8"
    "C.UTF-8/UTF-8"
  ];
  i18n.extraLocaleSettings = {
    LC_CTYPE = "en_US.UTF-8";
    LC_COLLATE = "en_US.UTF-8";
    LC_MESSAGES = "en_US.UTF-8";
  };
  environment.variables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

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

  environment.systemPackages = with pkgs; let
    clipCopy = writeShellScript "mandragora-clip-copy" ''
      exec /mnt/c/Windows/System32/clip.exe
    '';
    clipPaste = writeShellScript "mandragora-clip-paste" ''
      /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command "Get-Clipboard" \
        | sed 's/\r$//'
    '';
    copyShim = name: writeShellScriptBin name "exec ${clipCopy}";
    pasteShim = name: writeShellScriptBin name "exec ${clipPaste}";
    xclipShim = writeShellScriptBin "xclip" ''
      for arg in "$@"; do
        case "$arg" in
          -o|-out|--output) exec ${clipPaste} ;;
        esac
      done
      exec ${clipCopy}
    '';
    xselShim = writeShellScriptBin "xsel" ''
      for arg in "$@"; do
        case "$arg" in
          -i|--input)  exec ${clipCopy} ;;
          -o|--output) exec ${clipPaste} ;;
        esac
      done
      exec ${clipCopy}
    '';
    xdgOpenShim = writeShellScriptBin "xdg-open" ''
      target="$1"
      case "$target" in
        http://*|https://*|mailto:*|ftp://*|file://*) ;;
        *)
          if [ -e "$target" ]; then
            target="$(wslpath -w "$target")"
          fi
          ;;
      esac
      exec /mnt/c/Windows/explorer.exe "$target"
    '';
  in [
    git
    wget
    curl
    fastfetch
    rtk
    claude-code
    xdgOpenShim
    (copyShim "wl-copy")
    (pasteShim "wl-paste")
    (copyShim "pbcopy")
    (pasteShim "pbpaste")
    (copyShim "clipcopy")
    (pasteShim "clippaste")
    xclipShim
    xselShim
  ];

  programs.zsh.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.m = { lib, pkgs, ... }: {
    imports = [ ../../modules/shared/home-cli.nix ]
      ++ lib.optional ((builtins.getEnv "MANDRAGORA_PERSONAL") == "1")
        ../../modules/shared/home-personal.nix;
    home.username = "m";
    home.homeDirectory = "/home/m";
    home.stateVersion = "24.05";
    programs.zsh.shellAliases = {
      nrs = lib.mkForce "git -C /etc/nixos/mandragora pull --rebase --autostash && sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-wsl --impure";
    };
  };

  system.stateVersion = "24.05";
}
