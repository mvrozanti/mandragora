import asyncio
import logging
import os
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

import poller
import sources
import telegram as tg


logging.basicConfig(
    level=os.environ.get("WATCH_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)
log = logging.getLogger("watch")


DATA_DIR = Path(os.environ.get("WATCH_DATA_DIR", "/data"))
DB_PATH = DATA_DIR / "watch.db"
STATIC_DIR = Path(__file__).parent / "static"
PUBLIC_BASE = os.environ.get("WATCH_PUBLIC_BASE", "https://watch.mvr.ac")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


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
        CREATE TABLE IF NOT EXISTS watchers (
          id INTEGER PRIMARY KEY,
          kind TEXT NOT NULL,
          target TEXT NOT NULL,
          name TEXT NOT NULL,
          cursor TEXT,
          enabled INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          last_polled_at TEXT,
          last_error TEXT,
          UNIQUE (kind, target)
        );
        CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY,
          watcher_id INTEGER NOT NULL REFERENCES watchers(id) ON DELETE CASCADE,
          external_id TEXT NOT NULL,
          title TEXT NOT NULL,
          summary TEXT,
          link TEXT,
          occurred_at TEXT,
          received_at TEXT NOT NULL,
          raw TEXT,
          UNIQUE (watcher_id, external_id)
        );
        CREATE INDEX IF NOT EXISTS events_watcher_id_desc
          ON events(watcher_id, id DESC);
        CREATE INDEX IF NOT EXISTS events_received_desc
          ON events(received_at DESC);
        """
    )
    c.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    tasks = [
        asyncio.create_task(poller.run_forever(conn)),
        asyncio.create_task(tg.run_forever(conn)),
    ]
    try:
        yield
    finally:
        for t in tasks:
            t.cancel()
        for t in tasks:
            try:
                await t
            except asyncio.CancelledError:
                pass


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


def watcher_dict(row: sqlite3.Row, event_count: int = 0) -> dict:
    return {
        "id": row["id"],
        "kind": row["kind"],
        "target": row["target"],
        "name": row["name"],
        "cursor": row["cursor"],
        "enabled": bool(row["enabled"]),
        "created_at": row["created_at"],
        "last_polled_at": row["last_polled_at"],
        "last_error": row["last_error"],
        "event_count": event_count,
    }


def event_dict(row: sqlite3.Row, watcher: sqlite3.Row | None = None) -> dict:
    return {
        "id": row["id"],
        "watcher_id": row["watcher_id"],
        "watcher_name": watcher["name"] if watcher else None,
        "watcher_kind": watcher["kind"] if watcher else None,
        "watcher_target": watcher["target"] if watcher else None,
        "external_id": row["external_id"],
        "title": row["title"],
        "summary": row["summary"],
        "link": row["link"],
        "occurred_at": row["occurred_at"],
        "received_at": row["received_at"],
    }


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True}


@app.get("/", response_class=HTMLResponse)
async def index() -> HTMLResponse:
    html = (STATIC_DIR / "index.html").read_text()
    return HTMLResponse(html)


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/api/kinds")
async def list_kinds() -> dict:
    return sources.SOURCE_KINDS


@app.get("/api/watchers")
async def list_watchers() -> list[dict]:
    c = conn()
    rows = c.execute(
        """
        SELECT w.*, (SELECT COUNT(*) FROM events e WHERE e.watcher_id = w.id) AS n
        FROM watchers w
        ORDER BY w.created_at DESC
        """
    ).fetchall()
    out = [watcher_dict(r, r["n"]) for r in rows]
    c.close()
    return out


@app.post("/api/watchers")
async def create_watcher(payload: dict) -> dict:
    kind = (payload.get("kind") or "").strip()
    if kind not in sources.SOURCE_KINDS:
        raise HTTPException(400, f"unknown kind: {kind}")
    try:
        target = sources.validate_target(kind, payload.get("target") or "")
    except ValueError as e:
        raise HTTPException(400, str(e))
    name = (payload.get("name") or f"{kind}:{target}").strip()
    c = conn()
    try:
        c.execute(
            "INSERT INTO watchers (kind, target, name, created_at) VALUES (?, ?, ?, ?)",
            (kind, target, name, now_iso()),
        )
    except sqlite3.IntegrityError:
        c.close()
        raise HTTPException(409, "watcher already exists")
    row = c.execute(
        "SELECT * FROM watchers WHERE kind = ? AND target = ?",
        (kind, target),
    ).fetchone()
    c.close()
    return watcher_dict(row, 0)


@app.delete("/api/watchers/{wid}")
async def delete_watcher(wid: int) -> dict:
    c = conn()
    cur = c.execute("DELETE FROM watchers WHERE id = ?", (wid,))
    c.close()
    if cur.rowcount == 0:
        raise HTTPException(404, "watcher not found")
    return {"ok": True}


@app.post("/api/watchers/{wid}/toggle")
async def toggle_watcher(wid: int) -> dict:
    c = conn()
    r = c.execute("SELECT * FROM watchers WHERE id = ?", (wid,)).fetchone()
    if not r:
        c.close()
        raise HTTPException(404, "watcher not found")
    new_val = 0 if r["enabled"] else 1
    c.execute("UPDATE watchers SET enabled = ? WHERE id = ?", (new_val, wid))
    c.close()
    return {"ok": True, "enabled": bool(new_val)}


@app.post("/api/watchers/{wid}/poll")
async def poll_now(wid: int) -> dict:
    c = conn()
    r = c.execute("SELECT * FROM watchers WHERE id = ?", (wid,)).fetchone()
    if not r:
        c.close()
        raise HTTPException(404, "watcher not found")
    c.close()
    try:
        events, new_cursor = await sources.fetch(r["kind"], r["target"], r["cursor"])
    except Exception as exc:
        raise HTTPException(502, f"fetch failed: {exc}")
    c = conn()
    inserted = 0
    for ev in events:
        try:
            c.execute(
                """
                INSERT INTO events (watcher_id, external_id, title, summary, link, occurred_at, received_at, raw)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    wid,
                    ev.get("external_id", ""),
                    (ev.get("title") or "")[:500],
                    (ev.get("summary") or "")[:2000],
                    ev.get("link") or "",
                    ev.get("occurred_at") or now_iso(),
                    now_iso(),
                    "",
                ),
            )
            inserted += 1
        except sqlite3.IntegrityError:
            pass
    c.execute(
        "UPDATE watchers SET cursor = ?, last_polled_at = ?, last_error = NULL WHERE id = ?",
        (new_cursor, now_iso(), wid),
    )
    c.close()
    return {"ok": True, "inserted": inserted, "fetched": len(events)}


@app.get("/api/events")
async def list_events(
    limit: int = Query(100, ge=1, le=500),
    before: int | None = None,
    watcher_id: int | None = None,
) -> list[dict]:
    c = conn()
    q = """
        SELECT e.*, w.name AS w_name, w.kind AS w_kind, w.target AS w_target
        FROM events e JOIN watchers w ON w.id = e.watcher_id
    """
    where = []
    params: list = []
    if watcher_id is not None:
        where.append("e.watcher_id = ?")
        params.append(watcher_id)
    if before is not None:
        where.append("e.id < ?")
        params.append(before)
    if where:
        q += " WHERE " + " AND ".join(where)
    q += " ORDER BY e.id DESC LIMIT ?"
    params.append(limit)
    rows = c.execute(q, params).fetchall()
    out = []
    for r in rows:
        out.append({
            "id": r["id"],
            "watcher_id": r["watcher_id"],
            "watcher_name": r["w_name"],
            "watcher_kind": r["w_kind"],
            "watcher_target": r["w_target"],
            "external_id": r["external_id"],
            "title": r["title"],
            "summary": r["summary"],
            "link": r["link"],
            "occurred_at": r["occurred_at"],
            "received_at": r["received_at"],
        })
    c.close()
    return out
