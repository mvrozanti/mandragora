# `vj/` — `vj.mvr.ac` reverse-proxy shim

Label-only stack. Carries the Caddy labels for `vj.mvr.ac` and forwards
TLS-terminated traffic over the tailnet to the vj rater on
mandragora-desktop (`:8100`, user unit `vj-web`, repo `~/Projects/vj`).

Generated from [`../proxy-stacks.json`](../proxy-stacks.json) by
[`../generate-proxy-stacks.py`](../generate-proxy-stacks.py) — edit the
manifest and re-run the generator, never this file. Audit check
`11-proxy-stacks` gates the drift.

```
deploy-stacks.sh vj
```

## What is behind it

The rater for the auto-VJ: each trial is an 8-bar window of a track from
`~/Music` drawn live in the browser by one of ten media, driven by a
weighted mix of ten rhythm readings taken from the `.viz` analyzer, and
judged beautiful, in sync and reflexive. Judgements land in SQLite on the
desktop; `/insight` shows what they say. When the desktop sleeps the
vhost is down.
