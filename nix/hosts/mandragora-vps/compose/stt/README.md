# `stt` — speech-to-text edge proxy

VPS-side caddy reverse-proxy for `https://stt.mvr.ac`. Real engine
(faster-whisper large-v3) lives on the desktop as a systemd user
service `stt-core`, bound to the tailscale IP on port 8091.

## Why a proxy container

Per the decouple-UI-from-core directive: STT is a desktop GPU service
exposed over tailscale; the VPS only terminates TLS, gates with
Authelia, and proxies. The `stt-proxy` container is a label-only
anchor for caddy-docker-proxy — it doesn't serve traffic itself.

## Topology

```
browser → stt.mvr.ac (caddy on VPS) → forward_auth(authelia)
       → reverse_proxy → 100.115.80.79:8091  (desktop, stt-core)
       → faster-whisper large-v3 on RTX 5070 Ti (gpu-locked)
```

## API (on `stt-core`, also reachable through `https://stt.mvr.ac`)

| method | path           | body / response                                   |
|--------|----------------|---------------------------------------------------|
| GET    | `/healthz`     | `{ok, model, device, model_loaded}`               |
| GET    | `/status`      | `{model_loaded, gpu_lock_holder, config}`         |
| POST   | `/warmup`      | preload model into VRAM (acquires gpu_lock)       |
| POST   | `/transcribe`  | multipart `audio`, optional `language`, `task`    |
| GET    | `/`            | minimal web UI (record + upload + transcribe)     |

## Layout on VPS

```
/home/opc/stt/
└── docker-compose.yml         ← repo copy (only file needed)
```

## `.env`

```
MVR_AC=mvr.ac
STT_UPSTREAM=100.115.80.79:8091
```

## Bring-up

```
rsync -av --delete \
  nix/hosts/mandragora-vps/compose/stt/ \
  opc@mandragora-vps:/home/opc/stt/
ssh opc@mandragora-vps 'cd /home/opc/stt && docker compose up -d'
```

## Followups

- `stt.mvr.ac` must be added to `authelia/config/configuration.yml`
  access_control rules (two_factor) and authelia restarted, otherwise
  default deny gives 403.
- Refactor `.local/share/stt-via-telegram/` to be a thin HTTP client
  against `stt-core` instead of loading faster-whisper itself, so the
  GPU model lives in exactly one process.
