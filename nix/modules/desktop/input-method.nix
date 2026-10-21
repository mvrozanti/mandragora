_:

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
          # Completion toggle key fix
          GroupOrder."0" = "Default";
          "Groups/0" = {
            Name = "Default";
            "Default Layout" = "us-altgr-intl";
            DefaultIM = "keyboard-us-altgr-intl";
          };
          "Groups/0/Items/0" = {
            Name = "keyboard-us-altgr-intl";
            Layout = "";
          };
        };
        addons.spell = {
          globalSection = {
            "Completion Toggle Key" = "";
          };
        };
      };
    };
  };
}
