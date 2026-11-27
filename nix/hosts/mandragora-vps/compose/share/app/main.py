import json
import os
import re
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

DATA_DIR = Path(os.environ.get("SHARE_DATA_DIR", "/data"))
INBOX_DIR = DATA_DIR / "inbox"
DROPS_DIR = DATA_DIR / "drops"
STATIC_DIR = Path(__file__).resolve().parent / "static"
PUBLIC_BASE = os.environ.get("SHARE_PUBLIC_BASE", "https://share.mvr.ac").rstrip("/")
INBOX_URL = os.environ.get("SHARE_INBOX_URL", "").strip()
THEME_URL = os.environ.get("SHARE_THEME_URL", "http://host.docker.internal:6684/api/theme?colors=1")
MAX_MB = int(os.environ.get("SHARE_MAX_MB", "2048"))
MAX_BYTES = MAX_MB * 1024 * 1024
NAME_MAX = 120
MESSAGE_MAX = 4000
ID_RE = re.compile(r"^[0-9a-f]{32}$")

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sanitize_name(raw: str | None) -> str:
    base = os.path.basename((raw or "").replace("\\", "/")).strip()
    base = re.sub(r"[^\w.\- ]", "_", base, flags=re.UNICODE).strip(" .")
    return (base or "file")[:NAME_MAX]


def human_size(n: int) -> str:
    size = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def list_meta(base: Path) -> list[dict]:
    items: list[dict] = []
    if not base.is_dir():
        return items
    for slot in base.iterdir():
        meta_path = slot / "meta.json"
        if not meta_path.is_file():
            continue
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(meta, dict) and meta.get("id"):
            items.append(meta)
    items.sort(key=lambda m: m.get("ts", ""), reverse=True)
    return items


async def store_file(base: Path, key: str, file: UploadFile, extra: dict) -> dict:
    stored_name = sanitize_name(file.filename)
    slot = base / key
    slot.mkdir(parents=True, exist_ok=True)
    target = slot / "file"
    size = 0
    try:
        with target.open("wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > MAX_BYTES:
                    raise HTTPException(status_code=413, detail="file too large")
                out.write(chunk)
    except Exception:
        shutil.rmtree(slot, ignore_errors=True)
        raise
    meta = {
        "id": key,
        "ts": now_iso(),
        "name": stored_name,
        "size": size,
        "mime": file.content_type or "application/octet-stream",
        **extra,
    }
    (slot / "meta.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    return meta


async def notify(meta: dict) -> None:
    if not INBOX_URL:
        return
    sender = meta.get("sender") or ""
    title = f"{sender}: {meta['name']}" if sender else f"new file: {meta['name']}"
    text = meta.get("message") or f"{meta['name']} · {human_size(meta['size'])}"
    payload = {
        "source": "share",
        "title": title,
        "text": text,
        "level": "info",
        "link": f"{PUBLIC_BASE}/inbox",
    }
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            await client.post(INBOX_URL, json=payload)
    except Exception:
        pass


def resolve_meta(base: Path, key: str) -> dict:
    if not ID_RE.match(key):
        raise HTTPException(status_code=404, detail="not found")
    meta_path = base / key / "meta.json"
    file_path = base / key / "file"
    if not meta_path.is_file() or not file_path.is_file():
        raise HTTPException(status_code=404, detail="not found")
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise HTTPException(status_code=404, detail="not found")
    return meta


@app.get("/healthz")
async def healthz() -> Response:
    return Response(b"ok", media_type="text/plain")


@app.get("/api/theme")
async def theme() -> Response:
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            r = await client.get(THEME_URL)
        if r.status_code != 200:
            return Response(status_code=204)
        return Response(content=r.content, media_type="application/json")
    except Exception:
        return Response(status_code=204)


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/inbox")
async def inbox_page() -> FileResponse:
    return FileResponse(STATIC_DIR / "inbox.html")


@app.get("/drop")
async def drop_page() -> FileResponse:
    return FileResponse(STATIC_DIR / "drop.html")


@app.get("/inbox/api")
async def inbox_api() -> JSONResponse:
    return JSONResponse({"items": list_meta(INBOX_DIR)})


@app.get("/drops/api")
async def drops_api() -> JSONResponse:
    return JSONResponse({"items": list_meta(DROPS_DIR)})


@app.post("/api/upload")
async def upload(file: UploadFile = File(...), name: str = Form(""), message: str = Form("")):
    sender = name.strip()[:NAME_MAX]
    note = message.strip()[:MESSAGE_MAX]
    meta = await store_file(INBOX_DIR, uuid.uuid4().hex, file, {"sender": sender, "message": note})
    await notify(meta)
    return {"ok": True, "id": meta["id"], "name": meta["name"], "size": meta["size"]}


@app.post("/api/drop")
async def drop(file: UploadFile = File(...), message: str = Form("")):
    note = message.strip()[:MESSAGE_MAX]
    meta = await store_file(DROPS_DIR, uuid.uuid4().hex, file, {"message": note})
    return {"ok": True, "token": meta["id"], "url": f"{PUBLIC_BASE}/d/{meta['id']}"}


@app.get("/d/{token}")
async def public_download(token: str) -> FileResponse:
    meta = resolve_meta(DROPS_DIR, token)
    return FileResponse(
        DROPS_DIR / token / "file",
        filename=meta.get("name") or "file",
        media_type=meta.get("mime") or "application/octet-stream",
    )


@app.get("/inbox/{upload_id}/download")
async def inbox_download(upload_id: str) -> FileResponse:
    meta = resolve_meta(INBOX_DIR, upload_id)
    return FileResponse(
        INBOX_DIR / upload_id / "file",
        filename=meta.get("name") or "file",
        media_type=meta.get("mime") or "application/octet-stream",
    )


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
