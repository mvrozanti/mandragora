# `gokapi/` — RETIRED 2026-11-26

**Status:** dead. Replaced by the consolidated [`share/`](../share) stack,
which now serves `share.mvr.ac` for both directions: drop a file to hand out
a public link (the old gokapi "me to them"), and receive a file from anyone
into a gated inbox with a phone notification (the old `upload.mvr.ac`
"them to me"). The gokapi container is removed from the VPS; `share.mvr.ac`
is served by the `share` stack.

## Why

Gokapi did only one direction (drop → public download link) and its admin
UI had been 403 since the 2026-09 security audit dropped `share.mvr.ac`
from the Authelia two_factor list. Rather than keep two apps for two
halves of one idea, the user consolidated onto a single small stack. The
gokapi data volume held only the seed database (no uploaded files), so
nothing of value was lost.

## If the user asks to bring it back

1. Restore from git: `git show <pre-retirement-commit>:nix/hosts/mandragora-vps/compose/gokapi/…`
2. Re-add `share.mvr.ac` to the Authelia two_factor list if it was removed.
3. Point it at a host other than `share.mvr.ac`, which the `share` stack owns now.
