# `mandragora-vps` compose stacks

Snapshot of the docker-compose stacks running on `mandragora-vps`
(Oracle Linux 8.10 aarch64), captured 2026-05-08. The repo holds the
canonical text; the VPS-side files under `/home/opc/` are the live
copies. Today they are kept in sync by hand. Future phases of the hub
project will switch to a pull-from-git workflow; until then, edits to
either side must be mirrored.

## Stacks tracked

| Path | Stack | Live location on VPS |
|---|---|---|
| `seafile/seafile-server.yml` + `caddy.yml` + `seadoc.yml` | Seafile + seadoc + per-stack Caddy | `/home/opc/seafile/` |
| `crypto-fetcher/docker-compose.yml` | Binance fetcher + redis | `/home/opc/crypto-experiments/crypto-fetcher/` |
| `hub/docker-compose.yml` (+ `config/`) | Homepage dashboard + apex→hub 302 | `/home/opc/hub/` |

The Seafile project is invoked with all three YAMLs explicitly:
```
docker compose -f seafile-server.yml -f caddy.yml -f seadoc.yml up -d
```
(verified via `com.docker.compose.project.config_files` labels on the
running containers). A stale `/home/opc/seafile/docker-compose.yml`
exists in the live tree but is not loaded — it predates the 11 → 12
upgrade and references `seafile-mc:12.0.14`. Not tracked here.

## Stacks deliberately not tracked

- **Hummingbot** at `/home/opc/high-frequency-trading-experiments/`:
  the live `docker-compose.yml` carries literal `JUPYTER_TOKEN` and
  `CONFIG_PASSWORD` values inline, so committing as-is would leak
  them. Out of scope for the hub project per user decision; revisit
  when those values are extracted to a `.env`.

## Secret handling

Every secret-bearing value in the tracked YAMLs is a `${VAR}`
reference resolved at runtime from an `.env` file colocated with the
compose project (e.g. `/home/opc/seafile/.env`). The `.env` files are
**root-owned**, **not** in this repo, and are excluded by the
`.gitignore` here. Never read or paste their contents.

The `INIT_SEAFILE_ADMIN_PASSWORD=${INIT_SEAFILE_ADMIN_PASSWORD:-asecret}`
default in `seafile/seafile-server.yml` is the upstream Seafile
template's own placeholder; the real value is in `.env` and overrides
it.

## Why not under `/etc/nixos/` proper

`mandragora-vps` runs Oracle Linux, not NixOS — see this directory's
parent `INVENTORY.md`. Nix manages userspace via home-manager;
container stacks remain plain docker-compose. This `compose/` subtree
is documentation + future deploy source, not a Nix module.
