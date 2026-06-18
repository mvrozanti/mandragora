import hashlib
import json
import os
import tempfile
import time
from urllib.parse import urldefrag

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from crawler import Spider, Options, EXTRACTORS

STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")
CACHE_DIR = os.environ.get("SPIDER_CACHE_DIR", "/data/cache")
os.makedirs(CACHE_DIR, exist_ok=True)

app = FastAPI(title="spider")


def _normalize(opts: Options) -> Options:
    if opts.start_url and not opts.start_url.startswith(("http://", "https://")):
        opts.start_url = "https://" + opts.start_url
    opts.clamp()
    return opts


def _cache_key(opts: Options) -> str:
    payload = {
        "url": urldefrag(opts.start_url)[0],
        "terms": opts.terms,
        "regex": opts.use_regex,
        "ci": opts.case_insensitive,
        "match_html": opts.match_html,
        "scope": opts.scope,
        "depth": opts.max_depth,
        "max_pages": opts.max_pages,
        "robots": opts.respect_robots,
        "extractors": sorted(opts.extractors),
        "custom_regex": opts.custom_regex,
        "check_broken": opts.check_broken,
    }
    raw = json.dumps(payload, sort_keys=True).encode()
    return hashlib.sha256(raw).hexdigest()[:32]


def _cache_path(key: str) -> str:
    return os.path.join(CACHE_DIR, key + ".json")


def _cache_load(key: str):
    try:
        with open(_cache_path(key)) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def _cache_store(key: str, record: dict):
    fd, tmp = tempfile.mkstemp(dir=CACHE_DIR, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(record, f)
        os.replace(tmp, _cache_path(key))
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass


@app.get("/healthz")
async def healthz():
    return {"ok": True}


def _parse_opts(q) -> Options:
    def b(name, default=False):
        v = q.get(name)
        if v is None:
            return default
        return str(v).lower() in ("1", "true", "yes", "on")

    terms_raw = q.get("terms", "") or ""
    terms = [t for t in (s.strip() for s in terms_raw.replace("\r", "").split("\n")) if t]
    if not terms and terms_raw.strip():
        terms = [terms_raw.strip()]

    extractors = [e for e in (q.get("extractors", "") or "").split(",") if e in EXTRACTORS]

    return Options(
        start_url=(q.get("url") or "").strip(),
        terms=terms,
        use_regex=b("regex"),
        case_insensitive=b("ci", True),
        match_html=b("match_html"),
        scope=q.get("scope", "host"),
        max_depth=int(q.get("depth", 2) or 2),
        max_pages=int(q.get("max_pages", 200) or 200),
        concurrency=int(q.get("concurrency", 6) or 6),
        respect_robots=b("robots", True),
        extractors=extractors,
        custom_regex=q.get("custom_regex", "") or "",
        check_broken=b("check_broken"),
    )


def _b(q, name, default=False):
    v = q.get(name)
    if v is None:
        return default
    return str(v).lower() in ("1", "true", "yes", "on")


@app.get("/api/cache/check")
async def cache_check(request: Request):
    opts = _normalize(_parse_opts(request.query_params))
    if not opts.start_url:
        return JSONResponse({"error": "url required"}, status_code=400)
    rec = _cache_load(_cache_key(opts))
    if not rec:
        return {"cached": False}
    return {
        "cached": True,
        "created": rec.get("created"),
        "url": rec.get("url"),
        "pages": rec.get("stats", {}).get("pages_crawled", 0),
        "matches": rec.get("stats", {}).get("matches", 0),
        "broken": rec.get("stats", {}).get("broken", 0),
    }


def _sse(ev_type: str, payload: dict) -> str:
    return f"event: {ev_type}\ndata: {json.dumps(payload)}\n\n"


@app.get("/api/crawl")
async def crawl(request: Request):
    q = request.query_params
    opts = _normalize(_parse_opts(q))

    if not opts.start_url:
        return JSONResponse({"error": "url required"}, status_code=400)

    key = _cache_key(opts)
    use_cache = _b(q, "use_cache")

    async def replay():
        rec = _cache_load(key)
        if not rec:
            yield _sse("error", {"error": "cache miss"})
            return
        yield _sse("meta", {**rec.get("meta", {}), "cached": True, "created": rec.get("created")})
        for ev in rec.get("events", []):
            if await request.is_disconnected():
                return
            yield _sse(ev["type"], ev)
        yield _sse("done", {"type": "done", "stats": rec.get("stats", {}), "cached": True})

    async def fresh():
        try:
            spider = Spider(opts)
        except Exception as e:
            yield _sse("error", {"error": str(e)})
            return
        meta = {"start": spider.start, "host": spider.start_host}
        yield _sse("meta", meta)
        events = []
        completed = False
        try:
            async for ev in spider.run():
                if await request.is_disconnected():
                    spider.request_stop()
                    break
                if ev["type"] == "done":
                    completed = True
                    yield _sse("done", ev)
                    _cache_store(key, {
                        "key": key,
                        "created": int(time.time()),
                        "url": spider.start,
                        "meta": meta,
                        "stats": ev.get("stats", {}),
                        "events": events,
                    })
                else:
                    events.append(ev)
                    yield _sse(ev["type"], ev)
        except Exception as e:
            yield _sse("error", {"error": str(e)})
        finally:
            spider.request_stop()

    gen = replay() if use_cache and _cache_load(key) else fresh()
    return StreamingResponse(
        gen,
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.get("/")
async def index():
    return FileResponse(os.path.join(STATIC_DIR, "index.html"))


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
