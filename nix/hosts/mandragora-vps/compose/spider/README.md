# `spider` — site crawler + text filter

FastAPI app served at `https://spider.mvr.ac` (Authelia-gated). Crawls a
website from a start URL and streams results live over SSE.

## Features

- **Text filter** — return only pages whose visible text (or raw HTML)
  matches all given terms. Plain substrings or regex, case toggle.
- **Match context** — each hit shows the matched term + surrounding snippet.
- **Scope control** — same host, same registrable domain, or any host.
- **Depth + page caps** — bounded BFS (depth ≤ 8, pages ≤ 2000).
- **robots.txt** — respected by default, per-host cached.
- **Extractors** — pull emails, phone numbers, or a custom-regex set from
  every crawled page.
- **Broken-link check** — HEAD/GET every discovered link, report ≥400 / dead.
- **Live progress** — SSE stream; matches/all/broken tabs; JSON + CSV export.

## Safety

Server-side crawl runs from the VPS IP, so it's gated behind Authelia
(no anonymous access) and every fetch target is SSRF-guarded: hostnames
resolving to private / loopback / link-local / reserved IPs are rejected,
including across redirects and on broken-link probes.

## Layout

```
app/
  main.py       FastAPI: /api/crawl (SSE), /healthz, static
  crawler.py    async BFS spider, SSRF guard, matchers, extractors
  static/index.html   single-page UI
```

## Deploy

```bash
ssh opc@mandragora-vps 'sudo mkdir -p /home/opc/spider && sudo chown -R opc:opc /home/opc/spider'
rsync -a /etc/nixos/mandragora/nix/hosts/mandragora-vps/compose/spider/ \
  opc@mandragora-vps:/home/opc/spider/
ssh opc@mandragora-vps 'cd /home/opc/spider && docker compose up -d --build'
```

caddy-docker-proxy picks up the labels automatically; no rebuild needed.
