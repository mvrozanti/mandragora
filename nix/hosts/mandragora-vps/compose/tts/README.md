# `tts` — text-to-speech

FastAPI core wrapping [piper](https://github.com/rhasspy/piper) CPU TTS.
Served at `https://tts.mvr.ac`, Authelia-gated. Web UI + REST API; the
Telegram adapter is a separate process that calls the same API.

## Why a core service, not a bot

Per the decouple-UI-from-core directive: every capability exposes a
core HTTP API consumable by multiple frontends. Web hub tile + Telegram
bot are parallel UIs against `/synthesize`. New frontends (CLI, MCP,
mobile) plug in without touching the engine.

## API

| method | path           | body / response                                   |
|--------|----------------|---------------------------------------------------|
| GET    | `/healthz`     | `{ok, voices}`                                    |
| GET    | `/voices`      | `{voices, default}`                               |
| POST   | `/synthesize`  | `{text, voice?}` → `audio/wav`                    |
| GET    | `/`            | minimal web UI                                    |

Bundled voices (downloaded at image build time, ~120 MB total):
- `en_US-lessac-medium`
- `pt_BR-faber-medium`

Add more by editing the loop in `app/Dockerfile`; voices live at
[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices).

## Layout on VPS

```
/home/opc/tts/
├── docker-compose.yml         ← repo copy
├── app/                       ← repo copy (Dockerfile, main.py, static/)
├── .env                       ← root-owned, optional
└── models/                    ← optional bind-mount for extra voices
```

## `.env`

```
MVR_AC=mvr.ac
TTS_DEFAULT_VOICE=en_US-lessac-medium
```

## Bring-up

```
rsync -av --delete \
  nix/hosts/mandragora-vps/compose/tts/ \
  opc@mandragora-vps:/home/opc/tts/
ssh opc@mandragora-vps 'cd /home/opc/tts && docker compose up -d --build'
```
