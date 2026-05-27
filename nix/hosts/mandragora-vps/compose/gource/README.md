# `gource` — on-demand mandragora repo visualization

FastAPI worker that renders a [gource](https://gource.io) MP4 of the
mandragora git history. Lives on `demo.mvr.ac` as a path-route
(`/api/gource/*`), no separate caddy host. The render code can run
either on the desktop workstation (faster) or locally inside the VPS
container (slower, hard-capped).

**Current backend = VPS-only.** The desktop renderer
(`modules/services/gource-renderer.nix`) ships but is unreached:
`DESKTOP_RENDERER_URL` defaults to the empty string here so the
worker skips the proxy step and goes straight to local render. The
desktop service's gource pipeline currently fails at SDL/GLX visual
negotiation on top of `xorg.xorgserver`'s Xvfb (with mesa swrast
loaded), and that path needs more work than was useful to do in v1.
To re-enable later: confirm `gource` runs headless on a fresh Xvfb
visual chain, then set `DESKTOP_RENDERER_URL=http://100.115.80.79:9991`
in this stack's `.env`.

## How it answers a request

1. POST `/api/gource/render` → params hashed (`sha256[:24]` of
   `{date_min,date_max,length_s,width,height}`) → that's the job id.
2. If `cache/<job_id>.mp4` exists → return `state=done` immediately.
3. Otherwise enqueue. Worker picks one off the FIFO, in order:
   - Pings `${DESKTOP_RENDERER_URL}/healthz` (2 s timeout).
   - Reachable → POSTs to `…/render-sync`, streams the MP4 back into
     `cache/<job_id>.mp4`.
   - Unreachable → renders locally under hard caps (length ≤ 120 s,
     each dimension ≤ 1280 px). Pipeline:
     `xvfb-run gource … --output-ppm-stream - | ffmpeg … -c:v libx264`.
4. GET `/api/gource/status/{id}` → polled by the browser.
5. GET `/api/gource/video/{id}` → serves the cached MP4 with
   `Cache-Control: public, max-age=2592000, immutable`.

Rate limit: 10 renders/hour per `X-Forwarded-For` (cache hits don't
count).

## First-time bring-up on the VPS

```sh
ssh opc@mandragora-vps
sudo mkdir -p /home/opc/gource/cache /home/opc/gource/repo
sudo chown -R opc:opc /home/opc/gource
exit

rsync -a \
  /etc/nixos/mandragora/nix/hosts/mandragora-vps/compose/gource/ \
  opc@mandragora-vps:/home/opc/gource/

ssh opc@mandragora-vps 'cd /home/opc/gource && docker compose up -d --build'
```

`seafile-net` must already exist (it does, from the Seafile stack).

## Caddy wiring

The container exposes no caddy labels of its own. `demo.mvr.ac`'s
caddy block path-routes `/api/gource/*` to `gource-api:8080`; the
rest of the site continues to be served by the `demo` nginx.

## Environment

| var                                 | default                                        |
|-------------------------------------|------------------------------------------------|
| `DESKTOP_RENDERER_URL`              | `http://100.115.80.79:9991`                    |
| `DESKTOP_RENDERER_TIMEOUT_S`        | `2` (health + connect)                         |
| `DESKTOP_RENDERER_RENDER_TIMEOUT_S` | `600` (full MP4 stream)                        |
| `REPO_URL`                          | `https://github.com/mvrozanti/mandragora.git`  |
| `RATE_LIMIT_PER_HOUR`               | `10`                                           |
| `LOCAL_MAX_LENGTH_S`                | `120`                                          |
| `LOCAL_MAX_WIDTH` / `LOCAL_MAX_HEIGHT` | `1280` / `1280`                             |
| `LOG_LEVEL`                         | `INFO`                                         |

## Cache eviction

The cache is content-addressed and immutable for a given param set.
Re-render the same params → instant hit. Wipe everything if you ever
need to:

```sh
ssh opc@mandragora-vps 'rm -f /home/opc/gource/cache/*.mp4'
```

The pre-warm timer on the desktop drops the default-params MP4 into
this directory daily at 04:00 so a fresh page-load on `gource.html`
never has to wait for a render.
