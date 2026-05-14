{ ... }:
{
  programs.ydotool.enable = true;
  environment.variables.YDOTOOL_SOCKET = "/run/ydotoold/socket";
}
