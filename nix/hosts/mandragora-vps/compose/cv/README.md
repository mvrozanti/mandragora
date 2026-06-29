# cv.mvr.ac

Public static download page for Marcelo Vironda Rozanti's CV — six versions
(en/pt × original / impact / ats), built from
[github.com/mvrozanti/cv](https://github.com/mvrozanti/cv).

- `docker-compose.yml` — `nginx:alpine` serving `./static` behind caddy at
  `cv.mvr.ac` (public, `seafile-net`).
- `static/index.html` — the download page (tracked).
- PDFs are **not tracked** (`static/.gitignore`). `deploy.sh` builds them from
  the cv repo (`$CV_REPO`, default `~/Projects/cv`), renames them, stages them
  into `static/`, and rsyncs to the VPS.

## Deploy

    ./deploy.sh        # build CVs, stage PDFs, rsync static + compose, docker compose up -d

Override `CV_REPO`, `REMOTE`, or `REMOTE_DIR` via env if needed.

The hub tile lives in `../hub/static/index.html` (`https://cv.mvr.ac`) and is
required by audit check `05-hub-tile`. After editing it, rsync the hub static:

    rsync ../hub/static/index.html opc@100.84.78.83:/home/opc/hub/static/
