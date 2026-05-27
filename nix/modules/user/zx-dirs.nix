#Single source of truth for zX directory shortcuts.
#Consumed by modules/user/zsh.nix (shellAliases) and modules/user/yazi.nix (keymap).
#Format: <letter> = <path>;  OR  <letter> = { path = ...; lfPrefix = "g"; zshPrefix = "z"; };
#Default prefix: "g" in yazi, "z" in zsh. The lfPrefix field is a legacy name
#from the pre-yazi era and stays as a field key for backward compatibility.
{
  h = "~";
  s = "/mnt/sandisk";
  T = "/mnt/toshiba";

  m = "/etc/nixos/mandragora";
  p = "~/Projects";
  c = "~/.config";
  t = "~/.local/share/Trash";
  "/" = { path = "/"; lfPrefix = "g"; };
  d = "~/Downloads";
  D = "~/Documents";
  M = "~/Music";
  P = "~/Pictures";
  v = "~/Videos";
  V = "~/Documents/mandragora-desktop-obsidian-vault";
  G = "~/Games";
  w = "~/Pictures/wllpps";
  b = "/home/m/Documents/library/books";
}
