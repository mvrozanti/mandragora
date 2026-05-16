import asyncio
import base64
import json
import os
import secrets
import sqlite3
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles


DATA_DIR = Path(os.environ.get("WEBHOOK_DATA_DIR", "/data"))
DB_PATH = DATA_DIR / "webhook.db"
STATIC_DIR = Path(__file__).parent / "static"
MAX_BODY_BYTES = int(os.environ.get("WEBHOOK_MAX_BODY", str(1 * 1024 * 1024)))
MAX_EVENTS_PER_HOOK = int(os.environ.get("WEBHOOK_MAX_EVENTS_PER_HOOK", "200"))
PUBLIC_BASE = os.environ.get("WEBHOOK_PUBLIC_BASE", "https://webhook.mvr.ac")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def conn() -> sqlite3.Connection:
    c = sqlite3.connect(DB_PATH, isolation_level=None)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA foreign_keys=ON")
    return c


def init_db() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    c = conn()
    c.executescript(
        """
        CREATE TABLE IF NOT EXISTS hooks (
          id INTEGER PRIMARY KEY,
          slug TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          description TEXT,
          created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY,
          hook_id INTEGER NOT NULL REFERENCES hooks(id) ON DELETE CASCADE,
          received_at TEXT NOT NULL,
          method TEXT NOT NULL,
          headers TEXT NOT NULL,
          query TEXT NOT NULL,
          body BLOB,
          body_size INTEGER NOT NULL,
          content_type TEXT,
          remote_ip TEXT
        );
        CREATE INDEX IF NOT EXISTS events_hook_received
          ON events(hook_id, received_at DESC);
        CREATE INDEX IF NOT EXISTS events_received
          ON events(received_at DESC);
        """
    )
    c.close()


class Broadcaster:
    def __init__(self) -> None:
        self._subs: set[asyncio.Queue] = set()
        self._lock = asyncio.Lock()

    async def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=64)
        async with self._lock:
            self._subs.add(q)
        return q

    async def unsubscribe(self, q: asyncio.Queue) -> None:
        async with self._lock:
            self._subs.discard(q)

    async def publish(self, payload: dict) -> None:
        async with self._lock:
            targets = list(self._subs)
        for q in targets:
            try:
                q.put_nowait(payload)
            except asyncio.QueueFull:
                pass


broadcaster = Broadcaster()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


def hook_row(c: sqlite3.Connection, slug: str) -> sqlite3.Row | None:
    return c.execute("SELECT * FROM hooks WHERE slug = ?", (slug,)).fetchone()


def hook_by_id(c: sqlite3.Connection, hook_id: int) -> sqlite3.Row | None:
    return c.execute("SELECT * FROM hooks WHERE id = ?", (hook_id,)).fetchone()


def public_url(slug: str) -> str:
    return f"{PUBLIC_BASE.rstrip('/')}/h/{slug}"


def hook_dict(row: sqlite3.Row, event_count: int = 0) -> dict:
    return {
        "id": row["id"],
        "slug": row["slug"],
        "name": row["name"],
        "description": row["description"] or "",
        "created_at": row["created_at"],
        "event_count": event_count,
        "url": public_url(row["slug"]),
    }


def event_summary(row: sqlite3.Row, hook: sqlite3.Row | None = None) -> dict:
    return {
        "id": row["id"],
        "hook_id": row["hook_id"],
        "hook_name": hook["name"] if hook else None,
        "hook_slug": hook["slug"] if hook else None,
        "received_at": row["received_at"],
        "method": row["method"],
        "content_type": row["content_type"],
        "body_size": row["body_size"],
        "remote_ip": row["remote_ip"],
    }


def event_full(row: sqlite3.Row, hook: sqlite3.Row | None = None) -> dict:
    body = row["body"] or b""
    decoded: dict[str, Any] = {"size": len(body)}
    try:
        decoded["text"] = body.decode("utf-8")
    except UnicodeDecodeError:
        decoded["text"] = None
        decoded["base64"] = base64.b64encode(body).decode("ascii")
    return {
        **event_summary(row, hook),
        "headers": json.loads(row["headers"]),
        "query": json.loads(row["query"]),
        "body": decoded,
    }


def prune_hook(c: sqlite3.Connection, hook_id: int) -> None:
    c.execute(
        """
        DELETE FROM events
        WHERE hook_id = ? AND id NOT IN (
          SELECT id FROM events
          WHERE hook_id = ?
          ORDER BY received_at DESC, id DESC
          LIMIT ?
        )
        """,
        (hook_id, hook_id, MAX_EVENTS_PER_HOOK),
    )


def remote_ip(request: Request) -> str:
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else ""


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True}


@app.get("/", response_class=HTMLResponse)
async def index() -> HTMLResponse:
    html = (STATIC_DIR / "index.html").read_text()
    return HTMLResponse(html)


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/api/hooks")
async def list_hooks() -> list[dict]:
    c = conn()
    rows = c.execute(
        """
        SELECT h.*, (SELECT COUNT(*) FROM events e WHERE e.hook_id = h.id) AS n
        FROM hooks h
        ORDER BY h.created_at DESC
        """
    ).fetchall()
    out = [hook_dict(r, r["n"]) for r in rows]
    c.close()
    return out


@app.post("/api/hooks")
async def create_hook(payload: dict) -> dict:
    name = (payload.get("name") or "").strip()
    if not name:
        raise HTTPException(400, "name required")
    description = (payload.get("description") or "").strip()
    slug = secrets.token_urlsafe(12)
    c = conn()
    c.execute(
        "INSERT INTO hooks (slug, name, description, created_at) VALUES (?, ?, ?, ?)",
        (slug, name, description, now_iso()),
    )
    row = hook_row(c, slug)
    c.close()
    return hook_dict(row, 0)


@app.delete("/api/hooks/{hook_id}")
async def delete_hook(hook_id: int) -> dict:
    c = conn()
    r = hook_by_id(c, hook_id)
    if not r:
        c.close()
        raise HTTPException(404, "hook not found")
    c.execute("DELETE FROM hooks WHERE id = ?", (hook_id,))
    c.close()
    return {"ok": True}


@app.get("/api/hooks/{hook_id}/events")
async def list_hook_events(
    hook_id: int,
    limit: int = Query(50, ge=1, le=500),
    before: int | None = None,
) -> list[dict]:
    c = conn()
    h = hook_by_id(c, hook_id)
    if not h:
        c.close()
        raise HTTPException(404, "hook not found")
    if before is None:
        rows = c.execute(
            "SELECT * FROM events WHERE hook_id = ? ORDER BY id DESC LIMIT ?",
            (hook_id, limit),
        ).fetchall()
    else:
        rows = c.execute(
            "SELECT * FROM events WHERE hook_id = ? AND id < ? ORDER BY id DESC LIMIT ?",
            (hook_id, before, limit),
        ).fetchall()
    out = [event_summary(r, h) for r in rows]
    c.close()
    return out


@app.get("/api/events")
async def list_all_events(
    limit: int = Query(50, ge=1, le=500),
    before: int | None = None,
) -> list[dict]:
    c = conn()
    if before is None:
        rows = c.execute(
            """
            SELECT e.*, h.name AS h_name, h.slug AS h_slug
            FROM events e JOIN hooks h ON h.id = e.hook_id
            ORDER BY e.id DESC LIMIT ?
            """,
            (limit,),
        ).fetchall()
    else:
        rows = c.execute(
            """
            SELECT e.*, h.name AS h_name, h.slug AS h_slug
            FROM events e JOIN hooks h ON h.id = e.hook_id
            WHERE e.id < ? ORDER BY e.id DESC LIMIT ?
            """,
            (before, limit),
        ).fetchall()
    out = []
    for r in rows:
        summary = {
            "id": r["id"],
            "hook_id": r["hook_id"],
            "hook_name": r["h_name"],
            "hook_slug": r["h_slug"],
            "received_at": r["received_at"],
            "method": r["method"],
            "content_type": r["content_type"],
            "body_size": r["body_size"],
            "remote_ip": r["remote_ip"],
        }
        out.append(summary)
    c.close()
    return out


@app.get("/api/events/{event_id}")
async def get_event(event_id: int) -> dict:
    c = conn()
    r = c.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
    if not r:
        c.close()
        raise HTTPException(404, "event not found")
    h = hook_by_id(c, r["hook_id"])
    out = event_full(r, h)
    c.close()
    return out


@app.delete("/api/events/{event_id}")
async def delete_event(event_id: int) -> dict:
    c = conn()
    c.execute("DELETE FROM events WHERE id = ?", (event_id,))
    c.close()
    return {"ok": True}


@app.api_route(
    "/h/{slug}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"],
)
async def ingest(slug: str, request: Request) -> Response:
    c = conn()
    h = hook_row(c, slug)
    if not h:
        c.close()
        raise HTTPException(404, "unknown hook")
    body = b""
    async for chunk in request.stream():
        body += chunk
        if len(body) > MAX_BODY_BYTES:
            body = body[:MAX_BODY_BYTES]
            break
    headers = {k.lower(): v for k, v in request.headers.items()}
    query = dict(request.query_params)
    ip = remote_ip(request)
    cur = c.execute(
        """
        INSERT INTO events
          (hook_id, received_at, method, headers, query, body, body_size, content_type, remote_ip)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            h["id"],
            now_iso(),
            request.method,
            json.dumps(headers),
            json.dumps(query),
            body,
            len(body),
            headers.get("content-type"),
            ip,
        ),
    )
    event_id = cur.lastrowid
    prune_hook(c, h["id"])
    row = c.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
    payload = event_summary(row, h)
    c.close()
    await broadcaster.publish(payload)
    return JSONResponse({"ok": True, "id": event_id})


@app.get("/internal/events")
async def sse(request: Request) -> StreamingResponse:
    q = await broadcaster.subscribe()

    async def gen():
        try:
            yield f": webhook stream {now_iso()}\n\n".encode()
            last_ping = time.monotonic()
            while True:
                if await request.is_disconnected():
                    break
                try:
                    item = await asyncio.wait_for(q.get(), timeout=15.0)
                    yield f"event: webhook\ndata: {json.dumps(item)}\n\n".encode()
                except asyncio.TimeoutError:
                    pass
                now = time.monotonic()
                if now - last_ping >= 15.0:
                    yield f": ping {now_iso()}\n\n".encode()
                    last_ping = now
        finally:
            await broadcaster.unsubscribe(q)

    return StreamingResponse(
        gen(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )
