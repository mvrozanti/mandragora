#Single source of truth for zX directory shortcuts.
#Consumed by modules/user/zsh.nix (shellAliases) and modules/user/lf.nix (keybindings).
#Format: <letter> = <path>;  OR  <letter> = { path = ...; lfPrefix = "g"; zshPrefix = "z"; };
#Default prefix is "z" on both sides. Override per-key when a key collides
#(e.g. lf's `/` is native search, so `"/"` uses lfPrefix = "g").
{
  h = "~";
  m = "/etc/nixos/mandragora";
  p = "~/projects";
  c = "~/.config";
  t = "~/.local/share/Trash";
  "/" = { path = "/"; lfPrefix = "g"; };
  d = "~/Downloads";
  D = "~/Documents";
  M = "~/Music";
  P = "~/Pictures";
  V = "~/Videos";
  G = "~/Games";
}
