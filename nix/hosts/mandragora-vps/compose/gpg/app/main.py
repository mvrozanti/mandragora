import hashlib
import os
import re
import sqlite3
import time
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse, Response
from fastapi.staticfiles import StaticFiles

DATA_DIR = Path(os.environ.get("GPG_DATA_DIR", "/data"))
DB_PATH = DATA_DIR / "inbox.db"
STATIC_DIR = Path(__file__).parent / "static"
PUBKEY_PATH = STATIC_DIR / "pubkey.asc"
INDEX_PATH = STATIC_DIR / "index.html"

MAX_MSG_BYTES = int(os.environ.get("GPG_MAX_MSG_BYTES", str(64 * 1024)))
MAX_MESSAGES = int(os.environ.get("GPG_MAX_MESSAGES", "5000"))
MAX_TOTAL_BYTES = int(os.environ.get("GPG_MAX_TOTAL_BYTES", str(256 * 1024 * 1024)))
RATE_PER_MIN = int(os.environ.get("GPG_RATE_PER_MIN", "3"))
RATE_PER_DAY = int(os.environ.get("GPG_RATE_PER_DAY", "50"))
IP_SALT = os.environ.get("GPG_IP_SALT", "mandragora-gpg")

PUBKEY = PUBKEY_PATH.read_text(encoding="utf-8")

ARMOR_RE = re.compile(r"-----BEGIN PGP MESSAGE-----[\s\S]+?-----END PGP MESSAGE-----")

_hits: dict[str, deque] = defaultdict(deque)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def conn() -> sqlite3.Connection:
    c = sqlite3.connect(DB_PATH, isolation_level=None)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    return c


def init_db() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    c = conn()
    c.executescript(
        """
        CREATE TABLE IF NOT EXISTS messages (
          id INTEGER PRIMARY KEY,
          received_at TEXT NOT NULL,
          from_name TEXT,
          size INTEGER NOT NULL,
          ip_hash TEXT,
          armored TEXT NOT NULL,
          read_at TEXT
        );
        """
    )
    c.close()


def client_ip(request: Request) -> str:
    xff = request.headers.get("x-forwarded-for", "")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "0.0.0.0"


def rate_ok(ip: str) -> bool:
    now = time.time()
    dq = _hits[ip]
    while dq and now - dq[0] > 86400:
        dq.popleft()
    last_min = sum(1 for t in dq if now - t <= 60)
    if last_min >= RATE_PER_MIN or len(dq) >= RATE_PER_DAY:
        return False
    dq.append(now)
    if len(_hits) > 10000:
        for k in [k for k, v in _hits.items() if not v or now - v[-1] > 86400][:5000]:
            _hits.pop(k, None)
    return True


def stored_totals(c: sqlite3.Connection) -> tuple[int, int]:
    row = c.execute("SELECT COUNT(*) n, COALESCE(SUM(size), 0) b FROM messages").fetchone()
    return row["n"], row["b"]


def prune(c: sqlite3.Connection) -> None:
    n, b = stored_totals(c)
    while n > MAX_MESSAGES or b > MAX_TOTAL_BYTES:
        old = c.execute("SELECT id, size FROM messages ORDER BY id ASC LIMIT 1").fetchone()
        if not old:
            break
        c.execute("DELETE FROM messages WHERE id = ?", (old["id"],))
        n -= 1
        b -= old["size"]


def require_auth(request: Request) -> str:
    user = request.headers.get("remote-user") or request.headers.get("remote-email")
    if not user:
        raise HTTPException(status_code=401, detail="authelia session required")
    return user


app = FastAPI(title="gpg.mvr.ac", docs_url=None, redoc_url=None, openapi_url=None)
init_db()
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

_SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
}


@app.get("/health", include_in_schema=False)
@app.get("/healthz", include_in_schema=False)
def health() -> PlainTextResponse:
    return PlainTextResponse("ok\n")


@app.get("/pubkey.asc", include_in_schema=False)
def pubkey_asc() -> PlainTextResponse:
    return PlainTextResponse(PUBKEY, media_type="text/plain; charset=utf-8")


@app.get("/", include_in_schema=False)
def root(request: Request):
    accept = request.headers.get("accept", "")
    if "text/html" in accept:
        html = INDEX_PATH.read_text(encoding="utf-8")
        return HTMLResponse(html, headers=_SECURITY_HEADERS)
    return PlainTextResponse(PUBKEY, media_type="text/plain; charset=utf-8")


@app.post("/inbox", include_in_schema=False)
async def inbox(request: Request):
    ip = client_ip(request)
    if not rate_ok(ip):
        raise HTTPException(status_code=429, detail="rate limit exceeded, try later")

    clen = request.headers.get("content-length")
    if clen and clen.isdigit() and int(clen) > MAX_MSG_BYTES * 2:
        raise HTTPException(status_code=413, detail=f"message too large (max {MAX_MSG_BYTES} bytes)")

    raw = await request.body()
    if len(raw) > MAX_MSG_BYTES:
        raise HTTPException(status_code=413, detail=f"message too large (max {MAX_MSG_BYTES} bytes)")

    ctype = request.headers.get("content-type", "")
    from_name = ""
    if ctype.startswith("application/json"):
        import json

        try:
            payload = json.loads(raw.decode("utf-8"))
        except Exception:
            raise HTTPException(status_code=400, detail="invalid json")
        armored = str(payload.get("ciphertext") or "")
        from_name = str(payload.get("from") or "")[:64]
    else:
        armored = raw.decode("utf-8", "replace")

    m = ARMOR_RE.search(armored)
    if not m:
        raise HTTPException(status_code=400, detail="body must contain an ASCII-armored PGP MESSAGE")
    armored = m.group(0)
    if len(armored) > MAX_MSG_BYTES:
        raise HTTPException(status_code=413, detail="message too large")

    from_name = re.sub(r"[\x00-\x1f\x7f]", "", from_name).strip()

    c = conn()
    n, b = stored_totals(c)
    if b + len(armored) > MAX_TOTAL_BYTES and n > 0:
        prune(c)
    ip_hash = hashlib.sha256((IP_SALT + ip).encode()).hexdigest()[:16]
    c.execute(
        "INSERT INTO messages (received_at, from_name, size, ip_hash, armored) VALUES (?, ?, ?, ?, ?)",
        (now_iso(), from_name, len(armored), ip_hash, armored),
    )
    prune(c)
    c.close()
    return JSONResponse({"ok": True}, headers=_SECURITY_HEADERS)


@app.get("/api/messages", include_in_schema=False)
def list_messages(request: Request):
    require_auth(request)
    c = conn()
    rows = c.execute(
        "SELECT id, received_at, from_name, size, read_at FROM messages ORDER BY id DESC"
    ).fetchall()
    unread = c.execute("SELECT COUNT(*) n FROM messages WHERE read_at IS NULL").fetchone()["n"]
    c.close()
    return JSONResponse(
        {
            "unread": unread,
            "messages": [dict(r) for r in rows],
        },
        headers=_SECURITY_HEADERS,
    )


@app.get("/api/messages/{mid}", include_in_schema=False)
def get_message(mid: int, request: Request):
    require_auth(request)
    c = conn()
    row = c.execute("SELECT * FROM messages WHERE id = ?", (mid,)).fetchone()
    c.close()
    if not row:
        raise HTTPException(status_code=404, detail="not found")
    return JSONResponse(dict(row), headers=_SECURITY_HEADERS)


@app.post("/api/messages/{mid}/read", include_in_schema=False)
def mark_read(mid: int, request: Request):
    require_auth(request)
    c = conn()
    c.execute("UPDATE messages SET read_at = ? WHERE id = ? AND read_at IS NULL", (now_iso(), mid))
    c.close()
    return JSONResponse({"ok": True}, headers=_SECURITY_HEADERS)


@app.delete("/api/messages/{mid}", include_in_schema=False)
def delete_message(mid: int, request: Request):
    require_auth(request)
    c = conn()
    cur = c.execute("DELETE FROM messages WHERE id = ?", (mid,))
    c.close()
    if not cur.rowcount:
        raise HTTPException(status_code=404, detail="not found")
    return JSONResponse({"ok": True}, headers=_SECURITY_HEADERS)
