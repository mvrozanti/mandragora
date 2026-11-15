_:

{
  programs.vicinae = {
    enable = true;
    systemd.enable = true;
    enableFirefoxIntegration = false;
    settings = builtins.fromJSON (builtins.readFile ../../../.config/vicinae/settings.json);
  };
}
