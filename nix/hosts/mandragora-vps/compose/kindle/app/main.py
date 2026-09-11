import asyncio
import mimetypes
import os
import smtplib
from email.message import EmailMessage
from email.utils import formataddr
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles


STATIC_DIR = Path(__file__).parent / "static"

KINDLE_EMAIL = os.environ.get("KINDLE_EMAIL", "").strip()
SMTP_HOST = os.environ.get("SMTP_HOST", "").strip()
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_SECURITY = os.environ.get("SMTP_SECURITY", "starttls").strip().lower()
SMTP_USER = os.environ.get("SMTP_USER", "").strip()
SMTP_PASS = os.environ.get("SMTP_PASS", "")
FROM_ADDR = (os.environ.get("FROM_ADDR") or SMTP_USER).strip()
FROM_NAME = os.environ.get("FROM_NAME", "").strip()
MAX_UPLOAD_MB = int(os.environ.get("MAX_UPLOAD_MB", "25"))


app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def configured() -> bool:
    return bool(KINDLE_EMAIL and SMTP_HOST and SMTP_USER and SMTP_PASS)


def classify(filename: str) -> tuple[str, str]:
    guessed = mimetypes.guess_type(filename)[0]
    if guessed and "/" in guessed:
        maintype, subtype = guessed.split("/", 1)
        return maintype, subtype
    return "application", "octet-stream"


def send_one(filename: str, data: bytes, subject: str) -> None:
    maintype, subtype = classify(filename)
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = formataddr((FROM_NAME, FROM_ADDR)) if FROM_NAME else FROM_ADDR
    msg["To"] = KINDLE_EMAIL
    msg.add_attachment(data, maintype=maintype, subtype=subtype, filename=filename)

    if SMTP_SECURITY == "ssl":
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=30) as client:
            client.login(SMTP_USER, SMTP_PASS)
            client.send_message(msg)
    elif SMTP_SECURITY == "none":
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as client:
            if SMTP_USER:
                client.login(SMTP_USER, SMTP_PASS)
            client.send_message(msg)
    else:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as client:
            client.starttls()
            client.login(SMTP_USER, SMTP_PASS)
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
