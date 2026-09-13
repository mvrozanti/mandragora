import asyncio
import json
import mimetypes
import os
import smtplib
import threading
import time
import urllib.parse
import urllib.request
from email.message import EmailMessage
from email.utils import formataddr
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import HTMLResponse, PlainTextResponse, Response
from fastapi.staticfiles import StaticFiles

import device


STATIC_DIR = Path(__file__).parent / "static"

KINDLE_EMAIL = os.environ.get("KINDLE_EMAIL", "").strip()
SMTP_HOST = os.environ.get("SMTP_HOST", "").strip()
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_SECURITY = os.environ.get("SMTP_SECURITY", "starttls").strip().lower()
SMTP_USER = os.environ.get("SMTP_USER", "").strip()
SMTP_PASS = os.environ.get("SMTP_PASS", "")
OAUTH_CLIENT_ID = os.environ.get(
    "OAUTH_CLIENT_ID", "9e5f94bc-e8a4-4e73-b8be-63364c29d753"
).strip()
OAUTH_REFRESH_TOKEN = os.environ.get("OAUTH_REFRESH_TOKEN", "").strip()
OAUTH_TOKEN_URL = os.environ.get(
    "OAUTH_TOKEN_URL", "https://login.microsoftonline.com/common/oauth2/v2.0/token"
).strip()
SMTP_AUTH = os.environ.get(
    "SMTP_AUTH", "oauth2" if OAUTH_REFRESH_TOKEN else "password"
).strip().lower()
FROM_ADDR = (os.environ.get("FROM_ADDR") or SMTP_USER).strip()
FROM_NAME = os.environ.get("FROM_NAME", "").strip()
MAX_UPLOAD_MB = int(os.environ.get("MAX_UPLOAD_MB", "25"))

_oauth_lock = threading.Lock()
_oauth_cache = {"access_token": None, "expires_at": 0.0}


app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def configured() -> bool:
    if not (KINDLE_EMAIL and SMTP_HOST and SMTP_USER):
        return False
    if SMTP_AUTH == "oauth2":
        return bool(OAUTH_CLIENT_ID and OAUTH_REFRESH_TOKEN)
    return bool(SMTP_PASS)


def classify(filename: str) -> tuple[str, str]:
    guessed = mimetypes.guess_type(filename)[0]
    if guessed and "/" in guessed:
        maintype, subtype = guessed.split("/", 1)
        return maintype, subtype
    return "application", "octet-stream"


def _oauth_access_token(force: bool = False) -> str:
    with _oauth_lock:
        now = time.time()
        if not force and _oauth_cache["access_token"] and now < _oauth_cache["expires_at"]:
            return _oauth_cache["access_token"]

        payload = urllib.parse.urlencode(
            {
                "client_id": OAUTH_CLIENT_ID,
                "refresh_token": OAUTH_REFRESH_TOKEN,
                "grant_type": "refresh_token",
            }
        ).encode()
        request = urllib.request.Request(OAUTH_TOKEN_URL, data=payload, method="POST")
        request.add_header("Content-Type", "application/x-www-form-urlencoded")
        with urllib.request.urlopen(request, timeout=30) as response:
            token = json.loads(response.read())
        if "access_token" not in token:
            error = token.get("error", "unknown error")
            description = token.get("error_description", "")
            raise RuntimeError(f"oauth2 token refresh failed: {error} {description}".strip())

        access_token = token["access_token"]
        _oauth_cache["access_token"] = access_token
        _oauth_cache["expires_at"] = now + int(token.get("expires_in", 3600)) - 60
        return access_token


def _connect_smtp() -> smtplib.SMTP:
    if SMTP_SECURITY == "ssl":
        return smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=30)
    client = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30)
    if SMTP_SECURITY != "none":
        client.starttls()
        client.ehlo()
    return client


def _authenticate(client: smtplib.SMTP) -> None:
    if SMTP_AUTH == "oauth2":
        try:
            client.auth("XOAUTH2", lambda: f"user={SMTP_USER}\x01auth=Bearer {_oauth_access_token()}\x01\x01")
        except smtplib.SMTPAuthenticationError:
            client.auth("XOAUTH2", lambda: f"user={SMTP_USER}\x01auth=Bearer {_oauth_access_token(force=True)}\x01\x01")
    elif SMTP_USER:
        client.login(SMTP_USER, SMTP_PASS)


def send_one(filename: str, data: bytes, subject: str) -> None:
    maintype, subtype = classify(filename)
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = formataddr((FROM_NAME, FROM_ADDR)) if FROM_NAME else FROM_ADDR
    msg["To"] = KINDLE_EMAIL
    msg.add_attachment(data, maintype=maintype, subtype=subtype, filename=filename)

    with _connect_smtp() as client:
        _authenticate(client)
        client.send_message(msg)


async def read_limited(upload: UploadFile, cap: int) -> bytes | None:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await upload.read(1024 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > cap:
            return None
        chunks.append(chunk)
    return b"".join(chunks)


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True, "configured": configured()}


@app.get("/", response_class=HTMLResponse)
async def index() -> HTMLResponse:
    return HTMLResponse((STATIC_DIR / "index.html").read_text())


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.post("/api/send")
async def send_files(files: list[UploadFile] = File(...), title: str = Form("")) -> dict:
    if not configured():
        raise HTTPException(503, "send-to-kindle is not configured")
    if not files:
        raise HTTPException(400, "no files")

    cap = MAX_UPLOAD_MB * 1024 * 1024
    override = title.strip()

    prepared: list[tuple[str, bytes | None, str]] = []
    for upload in files:
        filename = upload.filename or "document"
        data = await read_limited(upload, cap)
        subject = override or Path(filename).stem or "document"
        prepared.append((filename, data, subject))

    results: list[dict] = []
    for filename, data, subject in prepared:
        if data is None:
            results.append({"filename": filename, "status": "error", "error": f"exceeds {MAX_UPLOAD_MB} MB"})
            continue
        if not data:
            results.append({"filename": filename, "status": "error", "error": "empty file"})
            continue
        try:
            await asyncio.to_thread(send_one, filename, data, subject)
            results.append({"filename": filename, "status": "sent"})
        except Exception as exc:
            results.append({"filename": filename, "status": "error", "error": str(exc)})

    return {"results": results}


@app.get("/api/device")
async def device_status() -> dict:
    try:
        info = await asyncio.to_thread(device.status)
    except device.DeviceError as exc:
        return {"online": False, "error": str(exc), "screen_age": device.screen_age()}
    info["screen_age"] = device.screen_age()
    return info


@app.get("/api/screen.png")
async def device_screen(force: bool = False) -> Response:
    try:
        png, at = await asyncio.to_thread(device.screen_png, force)
    except device.DeviceError as exc:
        raise HTTPException(503, str(exc))
    return Response(
        content=png,
        media_type="image/png",
        headers={"Cache-Control": "no-store", "X-Grabbed-At": str(int(at))},
    )


@app.post("/api/print")
async def device_print(payload: dict) -> dict:
    text = str(payload.get("text") or "")
    try:
        await asyncio.to_thread(device.print_line, text)
    except device.DeviceError as exc:
        raise HTTPException(502, str(exc))
    return {"ok": True, "printed": text.strip()[:120]}


@app.get("/api/scriptlets")
async def device_scriptlets() -> list[dict]:
    try:
        return await asyncio.to_thread(device.scriptlets)
    except device.DeviceError as exc:
        raise HTTPException(503, str(exc))


@app.post("/api/scriptlets/{name}/run")
async def device_run(name: str) -> dict:
    try:
        out = await asyncio.to_thread(device.run_scriptlet, name)
    except device.DeviceError as exc:
        raise HTTPException(502, str(exc))
    return {"ok": True, "output": out}


@app.post("/api/push")
async def device_push(files: list[UploadFile] = File(...)) -> dict:
    results = []
    for upload in files:
        filename = os.path.basename(upload.filename or "")
        data = await read_limited(upload, MAX_UPLOAD_MB * 1024 * 1024)
        if data is None:
            results.append({"filename": filename, "status": "error", "error": f"exceeds {MAX_UPLOAD_MB} MB"})
            continue
        if not data:
            results.append({"filename": filename, "status": "error", "error": "empty file"})
            continue
        try:
            target = await asyncio.to_thread(device.push_document, filename, data)
            results.append({"filename": filename, "status": "pushed", "path": target})
        except device.DeviceError as exc:
            results.append({"filename": filename, "status": "error", "error": str(exc)})
    return {"results": results}


@app.get("/metrics", response_class=PlainTextResponse)
async def metrics() -> PlainTextResponse:
    body = await asyncio.to_thread(device.metrics)
    return PlainTextResponse(content=body, media_type="text/plain; version=0.0.4")


@app.get("/api/monitor")
async def monitor_get() -> dict:
    return {"enabled": device.monitor_enabled(), "poll_seconds": device.MONITOR_TTL}


@app.post("/api/monitor")
async def monitor_set(payload: dict) -> dict:
    enabled = bool(payload.get("enabled"))
    await asyncio.to_thread(device.set_monitor, enabled)
    return {"enabled": device.monitor_enabled()}
