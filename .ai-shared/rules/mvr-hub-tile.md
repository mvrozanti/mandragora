# mvr.ac hub tile required for every subdomain

Every new public subdomain under `*.mvr.ac` must have a tile entry on
`hub.mvr.ac`. The hub is the single discoverable index for the user's
services — a subdomain that exists but isn't on the hub is invisible
in practice. Applies to **all agents** working on `mvr.ac`
infrastructure (Claude, Gemini, local LLMs, anything else).

## Where the hub lives

- Source: `/etc/nixos/mandragora/nix/hosts/mandragora-vps/compose/hub/static/index.html`
- Live: `opc@mandragora-vps:/home/opc/hub/static/index.html` (bind-mounted into the `hub` nginx container; no restart needed for content changes)
- Caddy labels for hub vhosts: same stack, `docker-compose.yml`

## Tile shape

Mirror existing entries; the structure inside `<div class="grid">` is:

```html
<a class="tile" href="https://<sub>.mvr.ac" target="_blank">
  <div class="tag"><short-category></div><div class="name"><display-name></div>
  <div class="desc"><one-line-purpose></div>
</a>
```

Choose `<tag>` from the existing vocabulary when possible (cloud, cal,
share, music, light, gpu, graph, hook, watch, www, …) and only invent
a new tag if none fits.

## Workflow

1. Stand up the subdomain (compose stack + Caddy labels + DNS, etc.).
2. **In the same commit**, edit `hub/static/index.html` to add the tile.
3. Deploy:
   - For compose-only changes: `rsync` the file to
     `opc@mandragora-vps:/home/opc/hub/static/`. nginx serves directly.
   - For nixos-managed changes: `mandragora-switch`.
4. Verify the tile is visible at `https://hub.mvr.ac/` (after auth).

## Automation

`mandragora-audit` check `05-hub-tile` cross-references every
`https://<sub>.mvr.ac` caddy host declared under
`nix/hosts/mandragora-vps/compose/` against the tiles in
`hub/static/index.html`. The check runs from both the pre-commit hook
and `mandragora-switch`, so a stack that adds a public subdomain
without a matching tile fails the audit before it can be committed.
Intentional exemptions (e.g. `hub` itself, `auth` for the Authelia
SSO landing) live in
`.local/share/mandragora-audit/allowlists/hub-tile.txt`.

## Done-criterion

A new-subdomain task is **not** done until the hub tile exists on
`hub.mvr.ac`. The audit enforces this automatically; "missing hub
tile" remains a blocker, not a polish item.

## Why this is a rule

Surfaced on 2026-05-20 after `rule110.mvr.ac` shipped without a hub
tile. The user considers process-level invisibility (no hub entry) a
process bug, not a stylistic miss. Codifying it here so subsequent
agents do not re-litigate.
