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
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)
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
          requires_ack INTEGER NOT NULL DEFAULT 0,
          reminder_interval INTEGER NOT NULL DEFAULT 3600,
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
          acked_at TEXT,
          last_reminder_at TEXT,
          UNIQUE (watcher_id, external_id)
        );
        CREATE INDEX IF NOT EXISTS events_watcher_id_desc
          ON events(watcher_id, id DESC);
        CREATE INDEX IF NOT EXISTS events_received_desc
          ON events(received_at DESC);
        """
    )
    for stmt in (
        "ALTER TABLE watchers ADD COLUMN requires_ack INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE watchers ADD COLUMN reminder_interval INTEGER NOT NULL DEFAULT 3600",
        "ALTER TABLE watchers ADD COLUMN ai_spec TEXT",
        "ALTER TABLE events ADD COLUMN acked_at TEXT",
        "ALTER TABLE events ADD COLUMN last_reminder_at TEXT",
        "ALTER TABLE events ADD COLUMN ai_verdict TEXT",
        "ALTER TABLE events ADD COLUMN ai_reason TEXT",
        "ALTER TABLE events ADD COLUMN ai_judged_at TEXT",
    ):
        try:
            c.execute(stmt)
        except sqlite3.OperationalError:
            pass
    c.execute("CREATE INDEX IF NOT EXISTS events_unacked ON events(acked_at, last_reminder_at)")
    c.execute("CREATE INDEX IF NOT EXISTS events_ai_verdict ON events(ai_verdict, ai_judged_at)")
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


def watcher_dict(row: sqlite3.Row, event_count: int = 0, unacked: int = 0) -> dict:
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
        "requires_ack": bool(row["requires_ack"]),
        "reminder_interval": int(row["reminder_interval"]),
        "ai_spec": row["ai_spec"] if "ai_spec" in row.keys() else None,
        "event_count": event_count,
        "unacked_count": unacked,
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
        "acked_at": row["acked_at"] if "acked_at" in row.keys() else None,
        "last_reminder_at": row["last_reminder_at"] if "last_reminder_at" in row.keys() else None,
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
        SELECT w.*,
          (SELECT COUNT(*) FROM events e WHERE e.watcher_id = w.id) AS n,
          (SELECT COUNT(*) FROM events e WHERE e.watcher_id = w.id AND e.acked_at IS NULL) AS un
        FROM watchers w
        ORDER BY w.created_at DESC
        """
    ).fetchall()
    out = [watcher_dict(r, r["n"], r["un"]) for r in rows]
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
    requires_ack = 1 if payload.get("requires_ack") else 0
    reminder_interval = int(payload.get("reminder_interval") or 3600)
    if reminder_interval < 60:
        reminder_interval = 60
    ai_spec = payload.get("ai_spec")
    if ai_spec is not None:
        ai_spec = str(ai_spec)[:4000] or None
    c = conn()
    try:
        c.execute(
            "INSERT INTO watchers (kind, target, name, created_at, requires_ack, reminder_interval, ai_spec) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (kind, target, name, now_iso(), requires_ack, reminder_interval, ai_spec),
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


@app.patch("/api/watchers/{wid}")
async def patch_watcher(wid: int, payload: dict) -> dict:
    fields = []
    params: list = []
    if "requires_ack" in payload:
        fields.append("requires_ack = ?")
        params.append(1 if payload["requires_ack"] else 0)
    if "reminder_interval" in payload:
        ri = int(payload["reminder_interval"])
        if ri < 60:
            ri = 60
        fields.append("reminder_interval = ?")
        params.append(ri)
    if "name" in payload:
        fields.append("name = ?")
        params.append(str(payload["name"])[:200])
    if "ai_spec" in payload:
        spec = payload["ai_spec"]
        if spec in (None, ""):
            fields.append("ai_spec = NULL")
        else:
            fields.append("ai_spec = ?")
            params.append(str(spec)[:4000])
    if not fields:
        raise HTTPException(400, "nothing to update")
    params.append(wid)
    c = conn()
    cur = c.execute(f"UPDATE watchers SET {', '.join(fields)} WHERE id = ?", params)
    if cur.rowcount == 0:
        c.close()
        raise HTTPException(404, "watcher not found")
    row = c.execute("SELECT * FROM watchers WHERE id = ?", (wid,)).fetchone()
    n = c.execute("SELECT COUNT(*) AS c FROM events WHERE watcher_id = ?", (wid,)).fetchone()["c"]
    un = c.execute("SELECT COUNT(*) AS c FROM events WHERE watcher_id = ? AND acked_at IS NULL", (wid,)).fetchone()["c"]
    c.close()
    return watcher_dict(row, n, un)


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
    unacked: int = 0,
    verdict: str | None = None,
) -> list[dict]:
    c = conn()
    q = """
        SELECT e.*, w.name AS w_name, w.kind AS w_kind, w.target AS w_target, w.requires_ack AS w_req, w.ai_spec AS w_spec
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
    if unacked:
        where.append("e.acked_at IS NULL")
    if verdict:
        if verdict.lower() == "pending":
            where.append("e.ai_verdict IS NULL AND w.ai_spec IS NOT NULL")
        else:
            where.append("e.ai_verdict = ?")
            params.append(verdict.upper())
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
            "watcher_requires_ack": bool(r["w_req"]),
            "watcher_has_ai": bool(r["w_spec"]),
            "external_id": r["external_id"],
            "title": r["title"],
            "summary": r["summary"],
            "link": r["link"],
            "occurred_at": r["occurred_at"],
            "received_at": r["received_at"],
            "acked_at": r["acked_at"],
            "last_reminder_at": r["last_reminder_at"],
            "ai_verdict": r["ai_verdict"],
            "ai_reason": r["ai_reason"],
            "ai_judged_at": r["ai_judged_at"],
        })
    c.close()
    return out


@app.get("/ack/{eid}", response_class=HTMLResponse)
async def ack_via_url(eid: int) -> HTMLResponse:
    c = conn()
    cur = c.execute(
        "UPDATE events SET acked_at = ? WHERE id = ? AND acked_at IS NULL",
        (now_iso(), eid),
    )
    row = c.execute("SELECT * FROM events WHERE id = ?", (eid,)).fetchone()
    c.close()
    if not row:
        return HTMLResponse(f"<pre>event {eid} not found</pre>", status_code=404)
    state = "acked" if cur.rowcount > 0 else "already acked"
    title = (row["title"] or "")[:200]
    body = f"""<!DOCTYPE html><html><head><meta charset=utf-8><title>ack {eid}</title>
<style>body{{background:#050805;color:#b8ffc4;font-family:monospace;padding:2rem;text-align:center;}}
a{{color:#00ff66;}}h1{{color:#00ff66;font-weight:normal;}}</style></head>
<body><h1>{state}</h1><p>event {eid}: {title}</p>
<p><a href="{PUBLIC_BASE}/">← back to watch</a></p></body></html>"""
    return HTMLResponse(body)


@app.post("/api/events/{eid}/ack")
async def ack_event(eid: int) -> dict:
    c = conn()
    cur = c.execute(
        "UPDATE events SET acked_at = ? WHERE id = ? AND acked_at IS NULL",
        (now_iso(), eid),
    )
    exists = c.execute("SELECT id FROM events WHERE id = ?", (eid,)).fetchone()
    c.close()
    if not exists:
        raise HTTPException(404, "event not found")
    return {"ok": True, "acked": cur.rowcount > 0}


@app.post("/api/watchers/{wid}/ack-all")
async def ack_all(wid: int) -> dict:
    c = conn()
    cur = c.execute(
        "UPDATE events SET acked_at = ? WHERE watcher_id = ? AND acked_at IS NULL",
        (now_iso(), wid),
    )
    c.close()
    return {"ok": True, "acked": cur.rowcount}


@app.post("/api/events/{eid}/judge")
async def rejudge_event(eid: int) -> dict:
    import judge
    c = conn()
    row = c.execute(
        """
        SELECT e.*, w.ai_spec AS w_spec, w.kind AS w_kind, w.target AS w_target, w.name AS w_name
        FROM events e JOIN watchers w ON w.id = e.watcher_id WHERE e.id = ?
        """,
        (eid,),
    ).fetchone()
    if not row:
        c.close()
        raise HTTPException(404, "event not found")
    if not row["w_spec"]:
        c.close()
        raise HTTPException(400, "watcher has no ai_spec")
    try:
        verdict, reason = await judge.judge_event(row["w_spec"], dict(row))
    except judge.QuotaExceeded as exc:
        c.close()
        raise HTTPException(429, f"gemini quota exceeded: {exc}")
    except Exception as exc:
        c.close()
        raise HTTPException(502, f"judge failed: {exc}")
    c.execute(
        "UPDATE events SET ai_verdict = ?, ai_reason = ?, ai_judged_at = ? WHERE id = ?",
        (verdict, reason[:500], now_iso(), eid),
    )
    c.close()
    return {"ok": True, "verdict": verdict, "reason": reason}
