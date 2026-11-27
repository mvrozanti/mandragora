{
  pkgs,
  inputs,
  ...
}:

let
  sudoUser = builtins.getEnv "SUDO_USER";
  user = if sudoUser != "" && sudoUser != "root" then sudoUser else "m";
  personal = builtins.getEnv "MANDRAGORA_PERSONAL" == "1";
  script =
    name: file: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile file;
    };
  capsLock = 30064771129;
  escape = 30064771113;
in
{
  imports = [ ../../pkgs/overlays.nix ];

  mandragora.profile = "macos";

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "@admin" ];
  };
  nix.optimise.automatic = true;
  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 0;
      Hour = 4;
      Minute = 0;
    };
    options = "--delete-older-than 14d";
  };

  system.primaryUser = user;
  users.users.${user}.home = "/Users/${user}";

  system.defaults = {
    NSGlobalDomain = {
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      ApplePressAndHoldEnabled = false;
      AppleShowAllExtensions = true;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
    };
    finder = {
      AppleShowAllFiles = true;
      ShowPathbar = true;
      FXPreferredViewStyle = "Nlsv";
    };
    dock = {
      autohide = false;
      mru-spaces = false;
    };
    trackpad.Clicking = true;
  };

  system.keyboard = {
    enableKeyMapping = true;
    userKeyMapping = [
      {
        HIDKeyboardModifierMappingSrc = capsLock;
        HIDKeyboardModifierMappingDst = escape;
      }
      {
        HIDKeyboardModifierMappingSrc = escape;
        HIDKeyboardModifierMappingDst = capsLock;
      }
    ];
  };

  fonts.packages = [
    pkgs.nerd-fonts.iosevka
    pkgs.nerd-fonts.terminess-ttf
  ];

  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    casks = [ "firefox" ];
  };

  environment.systemPackages = [
    (script "mandragora-macos-switch" ../../../.local/bin/mandragora-macos-switch.sh [ pkgs.git ])
    (script "wl-copy" ../../../.local/bin/macos-wl-copy.sh [ ])
    (script "wl-paste" ../../../.local/bin/macos-wl-paste.sh [ pkgs.pngpaste ])
    (script "xdg-open" ../../../.local/bin/macos-xdg-open.sh [ ])
    (script "notify-send" ../../../.local/bin/macos-notify-send.sh [ ])
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "pre-mandragora";
    extraSpecialArgs = { inherit inputs; };
    users.${user} =
      { lib, ... }:
      {
        imports = [
          ../../modules/shared/home-cli.nix
          ../../modules/user/terminal.nix
          ./home.nix
        ]
        ++ lib.optional personal ../../modules/shared/home-personal.nix;
        home.username = user;
        home.homeDirectory = "/Users/${user}";
        home.stateVersion = "26.11";
        programs.zsh.shellAliases = {
          nrs = lib.mkForce "mandragora-macos-switch";
          nrc = lib.mkForce "mandragora-macos-switch";
        };
      };
  };

  system.stateVersion = 6;
}
