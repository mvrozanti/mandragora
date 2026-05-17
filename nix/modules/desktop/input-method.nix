{ pkgs, ... }:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = [ ];
      settings = {
        globalOptions = {
          Hotkey = {
            TriggerKeys = "";
            EnumerateForwardKeys = "";
            EnumerateBackwardKeys = "";
          };
          Behavior = {
            ShareInputState = "All";
            ShowInputMethodInformation = "False";
            PreloadInputMethod = "True";
          };
        };
        inputMethod = {
          GroupOrder."0" = "Default";
          "Groups/0" = {
            Name = "Default";
            "Default Layout" = "us-intl";
            DefaultIM = "keyboard-us-intl";
          };
          "Groups/0/Items/0" = {
            Name = "keyboard-us-intl";
            Layout = "";
          };
        };
      };
    };
  };
}
