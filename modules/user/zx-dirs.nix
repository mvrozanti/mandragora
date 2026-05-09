#Single source of truth for zX directory shortcuts.
#Consumed by modules/user/zsh.nix (shellAliases) and modules/user/lf.nix (keybindings).
#Format: <letter> = <path>;  OR  <letter> = { path = ...; lfPrefix = "g"; zshPrefix = "z"; };
#Default prefix: "g" in lf, "z" in zsh. Override per-key when a key collides
#(e.g. lf's `/` is native search, so `"/"` uses lfPrefix = "g" — same as default).
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
}
