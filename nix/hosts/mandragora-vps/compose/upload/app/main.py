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

DATA_DIR = Path(os.environ.get("UPLOAD_DATA_DIR", "/data"))
UPLOADS_DIR = DATA_DIR / "uploads"
STATIC_DIR = Path(__file__).resolve().parent / "static"
PUBLIC_BASE = os.environ.get("UPLOAD_PUBLIC_BASE", "https://upload.mvr.ac").rstrip("/")
INBOX_URL = os.environ.get("UPLOAD_INBOX_URL", "").strip()
THEME_URL = os.environ.get("UPLOAD_THEME_URL", "http://host.docker.internal:6684/api/theme?colors=1")
MAX_UPLOAD_MB = int(os.environ.get("UPLOAD_MAX_MB", "2048"))
MAX_UPLOAD_BYTES = MAX_UPLOAD_MB * 1024 * 1024
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


def load_uploads() -> list[dict]:
    items: list[dict] = []
    if not UPLOADS_DIR.is_dir():
        return items
    for slot in UPLOADS_DIR.iterdir():
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


async def notify(meta: dict) -> None:
    if not INBOX_URL:
        return
    sender = meta.get("sender") or ""
    title = f"{sender}: {meta['name']}" if sender else f"new file: {meta['name']}"
    text = meta.get("message") or f"{meta['name']} · {human_size(meta['size'])}"
    payload = {
        "source": "upload",
        "title": title,
        "text": text,
        "level": "info",
        "link": f"{PUBLIC_BASE}/files",
    }
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            await client.post(INBOX_URL, json=payload)
    except Exception:
        pass


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


@app.get("/files")
async def files_page() -> FileResponse:
    return FileResponse(STATIC_DIR / "files.html")


@app.get("/files/api")
async def files_api() -> JSONResponse:
    return JSONResponse({"items": load_uploads()})


@app.post("/api/upload")
async def upload(file: UploadFile = File(...), name: str = Form(""), message: str = Form("")):
    sender = name.strip()[:NAME_MAX]
    note = message.strip()[:MESSAGE_MAX]
    stored_name = sanitize_name(file.filename)
    upload_id = uuid.uuid4().hex
    slot = UPLOADS_DIR / upload_id
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
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="file too large")
                out.write(chunk)
    except Exception:
        shutil.rmtree(slot, ignore_errors=True)
        raise
    meta = {
        "id": upload_id,
        "ts": now_iso(),
        "name": stored_name,
        "sender": sender,
        "message": note,
        "size": size,
        "mime": file.content_type or "application/octet-stream",
    }
    (slot / "meta.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    await notify(meta)
    return {"ok": True, "id": upload_id, "name": stored_name, "size": size}


@app.get("/files/{upload_id}/download")
async def download(upload_id: str) -> FileResponse:
    if not ID_RE.match(upload_id):
        raise HTTPException(status_code=404, detail="not found")
    slot = UPLOADS_DIR / upload_id
    meta_path = slot / "meta.json"
    file_path = slot / "file"
    if not meta_path.is_file() or not file_path.is_file():
        raise HTTPException(status_code=404, detail="not found")
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(
        file_path,
        filename=meta.get("name") or "file",
        media_type=meta.get("mime") or "application/octet-stream",
    )


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
