# `nb/` — open-notebook (Authelia-gated)

Stack for `nb.mvr.ac`. NotebookLM-style research notebook
([lfnovo/open-notebook](https://github.com/lfnovo/open-notebook)) with
a SurrealDB sidecar.

## Containers

| Container | Image | Port | Persistence |
|---|---|---|---|
| `nb` | `lfnovo/open_notebook:v1-latest` | `8502` (UI, in-container) | bind `./notebook_data` → `/app/data` |
| `nb-surrealdb` | `surrealdb/surrealdb:v2` | `8000` (in `nb-net`) | bind `./surreal_data` → `/mydata` |

`nb` is on two networks: `nb-net` (private, reaches surrealdb) and
`seafile-net` (so the VPS-side caddy can proxy 8502).

## Auth

Single-factor Authelia (password + TOTP) via Caddy `forward_auth`.
Open Notebook has no built-in auth.

## Live location

`/home/opc/nb/`

```
cd /home/opc/nb && sudo docker compose up -d
```

## Env

`.env` (root-owned, gitignored) holds:
- `NB_ENCRYPTION_KEY` — encrypts API keys stored in surrealdb
- `NB_SURREAL_PASSWORD` — root password for surrealdb
- optional `MVR_AC`, `NB_IMAGE`, `NB_SURREALDB_IMAGE`, `NB_DATA_VOLUME`, `NB_SURREAL_VOLUME`

## Verification

- `curl -sI https://nb.mvr.ac/` (from anywhere): `302 → auth.mvr.ac/?rd=…`
- After Authelia auth: `200` streamlit UI.
