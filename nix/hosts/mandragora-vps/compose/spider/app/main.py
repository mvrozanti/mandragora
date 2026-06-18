import asyncio
import json
import os

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from crawler import Spider, Options, EXTRACTORS

STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")

app = FastAPI(title="spider")


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


@app.get("/api/crawl")
async def crawl(request: Request):
    q = request.query_params
    opts = _parse_opts(q)

    if not opts.start_url:
        return JSONResponse({"error": "url required"}, status_code=400)
    if not opts.start_url.startswith(("http://", "https://")):
        opts.start_url = "https://" + opts.start_url

    async def gen():
        try:
            spider = Spider(opts)
        except Exception as e:
            yield f"event: error\ndata: {json.dumps({'error': str(e)})}\n\n"
            return
        yield f"event: meta\ndata: {json.dumps({'start': spider.start, 'host': spider.start_host})}\n\n"
        try:
            async for ev in spider.run():
                if await request.is_disconnected():
                    break
                yield f"event: {ev['type']}\ndata: {json.dumps(ev)}\n\n"
        except Exception as e:
            yield f"event: error\ndata: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        gen(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.get("/")
async def index():
    return FileResponse(os.path.join(STATIC_DIR, "index.html"))


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
