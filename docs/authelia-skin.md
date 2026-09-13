# Authelia Skin — Iterating on `auth.mvr.ac`

Stack and architecture:
[`nix/hosts/mandragora-vps/compose/authelia/README.md`](../nix/hosts/mandragora-vps/compose/authelia/README.md).
This page is only about how to *see* a change before it ships.

## Why a lab is needed

The screen being styled is the TOTP prompt, which is behind a
successful first factor and a registered TOTP device. You cannot get
to it with `curl`, and you should not be driving the production portal
to look at CSS.

The portal is a React SPA that renders entirely from three JSON
endpoints. Stub those and the real frontend — the exact bundle the VPS
serves — renders the 2FA screen with no authentication at all.

## The harness

Three containers: Authelia pinned to the **digest the VPS is actually
running**, the real `skin/nginx.conf` plus API stubs on `:8099`, and
the same stubs without the skin on `:8098` for before/after.

Pin the digest — `authelia/authelia:4.39` is a moving tag, and a newer
4.39.x replaced MUI with Tailwind. Skinning against the wrong build
produces a stylesheet whose `.Mui*` rules are all dead:

```bash
ssh opc@mandragora-vps \
  'sudo docker image inspect $(sudo docker inspect authelia --format "{{.Image}}") \
     --format "{{json .RepoDigests}}"'
```

The stubs, served by nginx as `location = <path> { return 200 '<json>'; }`:

| Path | Payload |
|---|---|
| `/api/configuration` | `{"status":"OK","data":{"available_methods":["totp"]}}` |
| `/api/state` | `{"status":"OK","data":{"username":"m","authentication_level":1,"factor_knowledge":true}}` |
| `/api/user/info` | `{"status":"OK","data":{"display_name":"m","emails":["m@mvr.ac"],"method":"totp","has_webauthn":false,"has_totp":true,"has_duo":false}}` |
| `/api/secondfactor/totp` | `{"status":"OK","data":{"created_at":"2026-01-01T00:00:00Z","issuer":"mvr.ac","algorithm":"SHA1","digits":6,"period":30}}` |

`authentication_level` picks the screen: `0` renders the sign-in form,
`1` renders the OTP prompt. Include the stubs from **outside**
`conf.d/` — nginx globs `conf.d/*.conf` at `http` level and a bare
`location` there is a config error.

Authelia rejects `localhost` as a session cookie domain, so the lab
config uses `skinlab.test`; nothing in the stubbed flow reads it.

Mount the worktree's `skin/static` straight into the lab nginx so a
CSS edit is live on the next reload — no copy step.

## Screenshots

Firefox's `--screenshot` fires on the load event and captures a blank
page before React paints. Use headless Chrome over CDP instead:

```bash
docker run -d --rm --name skinlab-chrome --network host chromedp/headless-shell
```

`--network host` matters: reach the lab as `http://localhost:8099` so
the `Host` header carries the port and Authelia's templated
`<base href>` matches the origin. Addressing the container by service
name yields `<base href="http://skin/">`, which trips
`base-uri 'self'` and every asset 404s into `index.html`.

Then drive it — `Emulation.setDeviceMetricsOverride`, `Page.navigate`,
wait ~3.5 s, `Page.captureScreenshot`. Feed digits with
`Input.dispatchKeyEvent` to capture the filled state, which is the one
that matters.

Shoot **320 px** as well as 390 px. 320 is where stock Authelia
overflows horizontally and clips the sixth digit box.

## Verifying after deploy

The lab cannot exercise a real login, so confirm on the VPS that the
skin is cosmetic-only:

```bash
curl -sI https://auth.mvr.ac/ | head -1
curl -s  https://auth.mvr.ac/ | grep -c 'mvr/skin.css'
curl -sI https://auth.mvr.ac/mvr/skin.css | head -1
curl -sI https://hub.mvr.ac/ | head -1
```

The last one must still be a redirect to `auth.mvr.ac` — it proves
`forward_auth` is still reaching `authelia:9091` directly rather than
through the skin.

Rollback is one file: restore `docker-compose.yml.bak.preskin` (the
`caddy:` labels back on the `authelia` service) and
`sudo docker compose up -d`.
