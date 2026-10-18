# cv.mvr.ac

Public static download page for Marcelo Vironda Rozanti's CV — four versions
(en/pt × default / ats), built from
[github.com/mvrozanti/cv](https://github.com/mvrozanti/cv).

- `docker-compose.yml` — `nginx:alpine` serving `./static` behind caddy at
  `cv.mvr.ac` (public, `seafile-net` + `tailnet-fwd` for the palette bridge).
- `nginx.conf` — serves the static root and proxies `GET /api/theme` to
  `host.docker.internal:6684/api/theme?colors=1` (public surface: drops the
  wallpaper path), degrading to `204` when the desktop palette is offline.
  The retired `impact` and `original` PDF names 301 to `default`, so links
  already handed out keep resolving.
- `static/index.html` + `static/cv.css` — the download page, consuming the
  canonical `--mv-*` tokens via `static/theme.css` and `static/theme.js`.
- PDFs are **not tracked** (`static/.gitignore`). `deploy.sh` builds them from
  the cv repo (`$CV_REPO`, default `~/Projects/cv`), renames them, stages them
  into `static/`, and rsyncs to the VPS.

## Deploy

    ./deploy.sh        # build CVs, stage PDFs, rsync static + compose, docker compose up -d

Override `CV_REPO`, `REMOTE`, or `REMOTE_DIR` via env if needed.

The hub tile lives in `../hub/static/index.html` (`https://cv.mvr.ac`) and is
required by audit check `05-hub-tile`. After editing it, rsync the hub static:

    rsync ../hub/static/index.html opc@100.84.78.83:/home/opc/hub/static/
