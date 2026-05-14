{ ... }:

{
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1038", ATTR{idProduct}=="1824", TEST=="power/control", ATTR{power/control}="on"
  '';
}
