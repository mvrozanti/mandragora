{ pkgs, ... }:
{
  services.udev.extraRules =
    builtins.readFile ../../snippets/gamepad-touchpad.rules
    + builtins.replaceStrings [ "@COREUTILS@" ] [ "${pkgs.coreutils}" ] (
      builtins.readFile ../../snippets/ds4-lightbar.rules
    );

  services.pipewire.wireplumber.extraConfig."13-gamepad-audio-last" = {
    "monitor.alsa.rules" = [
      {
        matches = [ { "node.name" = "~alsa_(input|output).usb-Sony_.*Wireless_Controller.*"; } ];
        actions.update-props = {
          "priority.session" = -1;
          "priority.driver" = 100;
        };
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    dualsensectl
    evtest
  ];
}
