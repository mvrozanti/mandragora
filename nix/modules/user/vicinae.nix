_:

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
}
