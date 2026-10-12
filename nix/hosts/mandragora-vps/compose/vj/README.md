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

The Deck: one square clip at a time, an 8-bar window of a track from
`~/Music` rendered by generative-art-playground with a candidate
gesture mapping, rated by swipe in four directions. Ratings land in
SQLite on the desktop; a worker inside `vj-web` keeps six clips ready,
rendering under `gpu-lock`. When the desktop sleeps the vhost is down,
and when the GPU is held the page says who holds it.
