{ pkgs, ... }:

let
  onboardingCompletedForEveryVersion = {
    version = 2147483647;
    completedAt = "2026-11-15T00:00:00Z";
  };
in
{
  programs.vicinae = {
    enable = true;
    systemd.enable = true;
    enableFirefoxIntegration = false;
    settings = builtins.fromJSON (builtins.readFile ../../../.config/vicinae/settings.json);
  };

  xdg.stateFile."vicinae/onboarding.json".text = builtins.toJSON onboardingCompletedForEveryVersion;

  xdg.dataFile."vicinae/scripts/claude".source = ../../../.local/share/vicinae/scripts/claude;
  xdg.dataFile."vicinae/scripts/deepseek".source = ../../../.local/share/vicinae/scripts/deepseek;

  home.packages =
    map (name: pkgs.writeShellScriptBin name (builtins.readFile ../../../.local/bin/${name}.sh)) [
      "ide-picker"
      "tool-picker"
      "db-picker"
      "wallpaper-picker"
    ]
    ++ [
      (pkgs.writeShellScriptBin "claude-tmux-prompt" (
        builtins.readFile ../../../.local/bin/claude-tmux-prompt.sh
      ))
    ];
}
