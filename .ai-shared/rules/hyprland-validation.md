# Rule: Hyprland Configuration Validation

When modifying the Hyprland configuration (`hyprland.conf`), a
successful `mandragora-switch` or NixOS rebuild does **not** mean the
configuration is syntactically valid. Hyprland silently drops unknown
fields (e.g. `match:initialTitle` instead of snake_case
`match:initial_title`) and keeps running, while a red error window
pops up in the user's session.

**Automation (preferred path):**
`mandragora-audit` check `04-hyprland-config` runs `hyprctl
configerrors` whenever staged or tracked changes touch
`.config/hypr/*.conf`. It fires from both the pre-commit hook and the
pre-stage phase of `mandragora-switch`, so the normal edit → switch
flow can no longer ship a silently-broken Hyprland config. The check
skips automatically on non-desktop hosts or when no Hyprland instance
is running (so the audit still passes on the VPS).

**Manual fallback:**
Only required if you bypass both the pre-commit hook and
`mandragora-switch` (rare). In that case, run:

```bash
hyprctl configerrors
```

"Switch successful" only means the derivations built. `hyprctl reload
ok` only means the file parsed *enough* to load. Neither implies
unknown-field detection.
