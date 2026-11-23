from __future__ import annotations

import asyncio
import base64
import json
import re
import os
import secrets
import signal
import subprocess
import textwrap
import time
import uuid
from contextlib import AsyncExitStack
from hashlib import sha1
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

from aiohttp import ClientError, ClientSession, ClientTimeout, web
from gpu_lock import GpuBusy, gpu_lock
from gpu_lock_ollama import evict_model
from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ClaudeSDKClient,
    PermissionResultAllow,
    PermissionResultDeny,
    ResultMessage,
    StreamEvent,
    SystemMessage,
    TextBlock,
    ThinkingBlock,
    ToolResultBlock,
    ToolUseBlock,
    UserMessage,
    delete_session,
    fork_session,
    get_session_info,
    get_session_messages,
    list_sessions,
    rename_session,
)
from claude_agent_sdk.types import SettingSource

HOME = Path(os.environ.get("HOME", "/home/m"))
HOST = os.environ.get("CLAUDE_BRIDGE_HOST", "0.0.0.0")
PORT = int(os.environ.get("CLAUDE_BRIDGE_PORT", "4097"))
USER = os.environ.get("CLAUDE_BRIDGE_USER", "claude")
PASSWORD_FILE = Path(os.environ.get("CLAUDE_BRIDGE_PASSWORD_FILE", "~/.local/state/claude-bridge/server-password")).expanduser()
DEEPSEEK_KEY_FILE = Path(os.environ.get("CLAUDE_BRIDGE_DEEPSEEK_KEY", "/run/secrets/deepseek/api_key"))
CLI_PATH = os.environ.get("CLAUDE_BRIDGE_CLI") or None
IDLE_SECONDS = int(os.environ.get("CLAUDE_BRIDGE_IDLE_SECONDS", "900"))
SESSIONS_INDEX = HOME / ".claude" / "sessions"
TRANSCRIPTS = HOME / ".claude" / "projects"
USER_SETTINGS = HOME / ".claude" / "settings.json"
PLANS = HOME / ".claude" / "plans"
UPLOADS = HOME / ".cache" / "claude-bridge" / "uploads"
IMAGE_TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "image/gif": ".gif"}
TMUX = os.environ.get("CLAUDE_BRIDGE_TMUX", "tmux")
FINDER = os.environ.get("CLAUDE_BRIDGE_FIND", "claude-find")
FIND_REINDEX_SECONDS = 15
MARKER = re.compile(r"⟦[nracdwu]:|⟧")
finder_state = {"indexed": 0.0}
TMUX_SOCKET = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / f"tmux-{os.getuid()}" / "default"
WATCH_SECONDS = 1.0
HOT_SECONDS = 900
RESCAN_SECONDS = 15
PROJECTS_TTL = 10
VERSION = "claude-bridge/1"
DEEPSEEK_BASE_URL = "https://api.deepseek.com/anthropic"
OLLAMA_URL = os.environ.get("CLAUDE_BRIDGE_OLLAMA_URL", "http://127.0.0.1:11434")
LOCAL_MODELS = {spec["name"]: spec for spec in json.loads(os.environ.get("CLAUDE_BRIDGE_LOCAL_MODELS") or "[]")}
LOCAL_LINGER_SECONDS = int(os.environ.get("CLAUDE_BRIDGE_LOCAL_LINGER", "60"))
LOCAL_TURN_SECONDS = 600
GPU_HOLDER = "claude-bridge"
PROVIDERS = {
    "claude": {"name": "Claude Code", "default": "default", "models": ["default", "fable", "opus", "sonnet", "haiku"]},
    "deepseek": {"name": "DeepSeek via Claude Code", "default": "deepseek-v4-pro", "models": ["deepseek-v4-pro", "deepseek-v4-flash"]},
}
if LOCAL_MODELS:
    PROVIDERS["local"] = {"name": "Local models via Claude Code", "default": next(iter(LOCAL_MODELS)), "models": list(LOCAL_MODELS)}
MODES = ("auto", "default", "acceptEdits", "plan")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
CHOICES_FILE = HOME / ".local" / "state" / "claude-bridge" / "choices.json"
CHOICES_KEPT = 400
INPUT_KEYS = ("command", "description", "file_path", "pattern", "path", "url", "query")
SETTING_SOURCES: list[SettingSource] = ["user", "project", "local"]
SCREEN_OPTION = re.compile(r"^(\s*)(?:❯\s*)?(\d)\.\s+(.*?)\s*$")
SCREEN_RULE = re.compile(r"^\s*[─━]{12,}(?: [^─━\s][^─━]* [─━]+)?\s*$")
SCREEN_DASH = re.compile(r"^\s*[╌┄▔]{12,}\s*$")
SCREEN_FOOTER = re.compile(r"Esc to cancel|Enter to select|to navigate|ctrl\+g to edit|Tab to amend")
SCREEN_TEXT = re.compile(r"type something|tell claude", re.I)
SCREEN_TABS = re.compile(r"^\s*←.*→\s*$")
SCREEN_TAB = re.compile(r"^([☐☒✔])\s+(.+)$")
SCREEN_BOX = re.compile(r"^\[([ ✔])\]\s+(.*)$")
SCREEN_ASIDE = re.compile(r"^chat about this$", re.I)
SCREEN_REVIEW = "Review your answers"
SCREEN_SUBMIT = re.compile(r"^\s*(❯)?\s*(?:Submit|Next)\s*$")
SCREEN_PICKED = re.compile(r"\s+✔$")
SCREEN_STEP_SECONDS = 0.15
SCREEN_KEYS = {"escape": "Escape", "next": "Right", "previous": "Left"}
SCREEN_EDGE = re.compile(r"^\s*[─━]{12,}")
SCREEN_EFFORT = re.compile(r"[○◐●◉◈]\s+(low|medium|high|xhigh|max) · /effort")
SCREEN_PICKED_EFFORT = re.compile(r"[○◐●◉◈]\s+(\w+) effort( \(default\))?\s+←/→")
SCREEN_MODEL = re.compile(r"\[(deepseek-v4-pro|deepseek-v4-flash|Opus|Sonnet|Haiku|Fable)\b[^\]]*\]")
SCREEN_MODES = (("auto mode on", "auto"), ("manual mode on", "default"), ("accept edits on", "acceptEdits"), ("plan mode on", "plan"))
SCREEN_PICKER = "Select model"
SCREEN_TAIL_BYTES = 262144
SCREEN_MISSES = 2
SCREEN_PIECES = re.compile(r" · |, |\s{2,}")
SCREEN_BACKGROUND = re.compile(r"^\d+ [a-z][a-z ]*[a-z]$")
BACKGROUND_SECONDS = 3
DESK_COMMANDS = {"claude": "claude", "deepseek": "deepseek"}
DESK_MODES = {"default": "manual"}
DESK_READY_SECONDS = 45
DESK_FALLBACK_SESSION = os.environ.get("CLAUDE_BRIDGE_TMUX_SESSION", "claude")
DESK_WINDOW = "#{session_name}:#{window_index} #{pane_id}"
CLOSE_SECONDS = 6
TAIL_REACH = (65536, 1048576)
COMMANDS_TTL = 300
COMMAND_ELSEWHERE = re.compile(r"sessions only\)\s*$")
tail_models: dict[Path, tuple[tuple[int, int], str | None]] = {}

PASSWORD = web.AppKey("password", object)
BRIDGE = web.AppKey("bridge", object)


def now_ms() -> int:
    return int(time.time() * 1000)


def to_ms(value) -> int:
    if value is None:
        return 0
    if isinstance(value, datetime):
        return int(value.timestamp() * 1000)
    if isinstance(value, (int, float)):
        return int(value if value > 1e11 else value * 1000)
    try:
        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return 0


def load_password() -> str | None:
    try:
        text = PASSWORD_FILE.read_text(encoding="utf-8").strip()
        if text:
            return text
    except OSError:
        pass
    try:
        PASSWORD_FILE.parent.mkdir(parents=True, exist_ok=True)
        text = secrets.token_urlsafe(24)
        tmp = PASSWORD_FILE.with_suffix(".tmp")
        with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, PASSWORD_FILE)
        return text
    except OSError:
        return None


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(block.get("text", "") for block in content if isinstance(block, dict) and block.get("type") == "text")
    return ""


def blocks_of(content) -> list[dict]:
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if isinstance(content, list):
        return [block for block in content if isinstance(block, dict)]
    return []


def summarize(tool: str, data: dict) -> str:
    for key in INPUT_KEYS:
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip().splitlines()[0][:200]
    return tool


def local_name(model: str | None) -> str | None:
    name = (model or "").removesuffix(":latest")
    return name if name in LOCAL_MODELS else None


def configured_model() -> str:
    try:
        model = json.loads(USER_SETTINGS.read_text(encoding="utf-8")).get("model")
    except (OSError, ValueError, AttributeError):
        model = None
    return model if isinstance(model, str) and model else "default"


def provider_of(model: str | None) -> str:
    if local_name(model):
        return "local"
    return "deepseek" if model and model.startswith("deepseek") else "claude"


def model_alias(provider: str, model: str | None) -> str:
    known = PROVIDERS[provider]["models"]
    if provider != "claude":
        name = local_name(model) or model or ""
        return name if name in known else PROVIDERS[provider]["default"]
    return next((alias for alias in known[1:] if model and alias in model), "default")


def read_choices() -> dict[str, dict]:
    try:
        data = json.loads(CHOICES_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def last_model(sid: str) -> str | None:
    path = next(TRANSCRIPTS.glob(f"*/{sid}.jsonl"), None)
    if path is None:
        return None
    for entry in reversed(transcript_entries(sid, path, 6)):
        if entry["info"]["role"] == "assistant" and entry["info"].get("modelID"):
            return entry["info"]["modelID"]
    return None


def assistant_model(data: bytes) -> str | None:
    for raw in reversed(data.split(b"\n")):
        if b'"assistant"' not in raw:
            continue
        try:
            record = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(record, dict) or record.get("type") != "assistant" or record.get("isSidechain"):
            continue
        model = (record.get("message") or {}).get("model")
        if isinstance(model, str) and model and model != "<synthetic>":
            return model
    return None


def tail_model(path: Path) -> str | None:
    try:
        stat = path.stat()
    except OSError:
        return None
    key = (stat.st_size, stat.st_mtime_ns)
    known = tail_models.get(path)
    if known is not None and known[0] == key:
        return known[1]
    model = None
    with path.open("rb") as handle:
        for reach in TAIL_REACH:
            handle.seek(max(0, stat.st_size - reach))
            model = assistant_model(handle.read())
            if model is not None or stat.st_size <= reach:
                break
    if model is None and known is not None:
        model = known[1]
    tail_models[path] = (key, model)
    return model


def transcript_models(sids: list[str]) -> dict[str, str]:
    paths = {path.stem: path for path in TRANSCRIPTS.glob("*/*.jsonl")}
    found = {}
    for sid in sids:
        path = paths.get(sid)
        model = tail_model(path) if path is not None else None
        if model is not None:
            found[sid] = model
    return found


def tool_part(part_id: str, message_id: str, sid: str, call_id: str, tool: str, data: dict | None, status: str = "pending") -> dict:
    data = data or {}
    return {
        "id": part_id,
        "messageID": message_id,
        "sessionID": sid,
        "type": "tool",
        "callID": call_id,
        "tool": tool,
        "state": {"status": status, "input": data, "title": summarize(tool, data)},
    }


def text_part(part_id: str, message_id: str, sid: str, kind: str, text: str) -> dict:
    return {"id": part_id, "messageID": message_id, "sessionID": sid, "type": kind, "text": text}


def entry_for(message_id: str, sid: str, role: str, model: str | None = None, created: int = 0) -> dict:
    info = {"id": message_id, "sessionID": sid, "role": role, "time": {"created": created}}
    if role == "assistant":
        info["modelID"] = model
        info["providerID"] = provider_of(model)
    return {"info": info, "parts": []}


STOPPED = "[Request interrupted by user"
TRANSCRIPT_KINDS = {"user", "assistant", "attachment", "system", "progress"}
TRANSCRIPT_CACHE = 16
transcripts: dict[Path, dict] = {}


@dataclass
class TranscriptLine:
    uuid: str
    parent: str | None
    logical: str | None
    main: bool
    visible: bool
    summary: bool
    queued: str | None
    offset: int
    length: int
    dequeued: bool = False


def queued_text(prompt) -> str:
    if isinstance(prompt, str):
        return prompt.strip()
    if isinstance(prompt, list):
        return "\n".join(block.get("text", "") for block in prompt if isinstance(block, dict) and block.get("type") == "text").strip()
    return ""


def index_line(index: dict, raw: bytes, offset: int) -> None:
    try:
        record = json.loads(raw)
    except ValueError:
        return
    if not isinstance(record, dict):
        return
    kind = record.get("type")
    uid = record.get("uuid")
    if kind not in TRANSCRIPT_KINDS or not isinstance(uid, str):
        return
    main = not record.get("isSidechain") and not record.get("teamName")
    attachment = record.get("attachment") if kind == "attachment" else None
    queued = None
    if main and isinstance(attachment, dict) and attachment.get("type") == "queued_command":
        said = queued_text(attachment.get("prompt"))
        if said and not said.startswith("<"):
            queued = said
    line = TranscriptLine(
        uuid=uid,
        parent=record.get("parentUuid"),
        logical=record.get("logicalParentUuid"),
        main=main,
        visible=main and kind in ("user", "assistant") and not record.get("isMeta"),
        summary=bool(record.get("isCompactSummary")),
        queued=queued,
        offset=offset,
        length=len(raw),
        dequeued=main and kind == "user" and record.get("promptSource") == "queued" and not record.get("isMeta"),
    )
    index["lines"].append(line)
    index["by_uuid"][uid] = line


def transcript_index(path: Path) -> dict:
    stat = path.stat()
    key = (stat.st_dev, stat.st_ino)
    index = transcripts.pop(path, None)
    if index is None or index["key"] != key or stat.st_size < index["offset"]:
        index = {"key": key, "offset": 0, "lines": [], "by_uuid": {}}
    transcripts[path] = index
    while len(transcripts) > TRANSCRIPT_CACHE:
        transcripts.pop(next(iter(transcripts)))
    if stat.st_size == index["offset"]:
        return index
    with path.open("rb") as handle:
        handle.seek(index["offset"])
        data = handle.read(stat.st_size - index["offset"])
    cursor = 0
    while True:
        stop = data.find(b"\n", cursor)
        if stop < 0:
            break
        index_line(index, data[cursor:stop], index["offset"] + cursor)
        cursor = stop + 1
    index["offset"] += cursor
    return index


def transcript_chain(index: dict) -> list[TranscriptLine]:
    lines = index["lines"]
    by_uuid = index["by_uuid"]
    newest = next((line for line in reversed(lines) if line.visible), None)

    def walk(leaf: TranscriptLine | None) -> list[TranscriptLine]:
        chain: list[TranscriptLine] = []
        seen: set[str] = set()
        current = leaf
        while current is not None and current.uuid not in seen:
            seen.add(current.uuid)
            chain.append(current)
            step = current.parent or current.logical
            current = by_uuid.get(step) if step else None
        chain.reverse()
        return chain

    chain = walk(next((line for line in reversed(lines) if line.main), None))
    if newest is not None and all(line.uuid != newest.uuid for line in chain):
        chain = walk(newest)
    return chain


def with_stray_prompts(index: dict, chain: list[TranscriptLine]) -> tuple[list[TranscriptLine], set[str]]:
    placed = {line.uuid for line in chain}
    strays: dict[str, list[TranscriptLine]] = {}
    for line in index["lines"]:
        if line.dequeued and line.uuid not in placed and line.parent in placed:
            strays.setdefault(line.parent, []).append(line)
    if not strays:
        return chain, set()
    merged: list[TranscriptLine] = []
    for line in chain:
        merged.append(line)
        merged.extend(strays.get(line.uuid, ()))
    return merged, {line.uuid for group in strays.values() for line in group}


def transcript_entries(sid: str, path: Path, limit: int) -> list[dict]:
    index = transcript_index(path)
    chain, strays = with_stray_prompts(index, transcript_chain(index))
    shown = [line for line in chain if line.visible or line.queued]
    if limit:
        shown = shown[-(limit * 8 + 50):]
    records = []
    queued_ids = set(strays)
    with path.open("rb") as handle:
        for line in shown:
            if line.queued:
                queued_ids.add(line.uuid)
                records.append(SimpleNamespace(type="user", uuid=line.uuid, message={"role": "user", "content": line.queued}))
                continue
            if line.summary:
                records.append(SimpleNamespace(type="divider", uuid=line.uuid, message={}))
                continue
            handle.seek(line.offset)
            try:
                record = json.loads(handle.read(line.length))
            except ValueError:
                continue
            records.append(SimpleNamespace(type=record.get("type"), uuid=line.uuid, message=record.get("message") or {}))
    entries = convert_records(sid, records)
    if queued_ids:
        said_later: set[str] = set()
        kept = []
        for entry in reversed(entries):
            said = "\n".join(part.get("text", "") for part in entry["parts"] if part.get("type") == "text").strip()
            if entry["info"]["id"] in queued_ids and said in said_later:
                continue
            if entry["info"]["role"] == "user":
                said_later.add(said)
            kept.append(entry)
        entries = kept[::-1]
    return entries


def session_entries(sid: str, directory: str | None, limit: int) -> list[dict]:
    path = next(TRANSCRIPTS.glob(f"*/{sid}.jsonl"), None)
    if path is not None:
        return transcript_entries(sid, path, limit)
    return convert_records(sid, get_session_messages(sid, directory))


def convert_records(sid: str, records) -> list[dict]:
    entries: list[dict] = []
    by_id: dict[str, dict] = {}
    tools: dict[str, dict] = {}
    for rec in records:
        if getattr(rec, "parent_agent_id", None) or getattr(rec, "parent_tool_use_id", None):
            continue
        message = rec.message or {}
        role = message.get("role") or rec.type
        content = message.get("content")
        if role == "assistant":
            message_id = message.get("id") or rec.uuid
            entry = by_id.get(message_id)
            if entry is None:
                entry = entry_for(message_id, sid, "assistant", message.get("model"))
                by_id[message_id] = entry
                entries.append(entry)
            for block in blocks_of(content):
                kind = block.get("type")
                index = len(entry["parts"])
                if kind == "text":
                    entry["parts"].append(text_part(f"{message_id}:{index}", message_id, sid, "text", block.get("text", "")))
                elif kind == "thinking":
                    entry["parts"].append(text_part(f"{message_id}:{index}", message_id, sid, "reasoning", block.get("thinking", "")))
                elif kind == "tool_use":
                    call_id = block.get("id") or f"{message_id}:{index}"
                    part = tool_part(call_id, message_id, sid, call_id, block.get("name", "tool"), block.get("input") if isinstance(block.get("input"), dict) else {})
                    entry["parts"].append(part)
                    tools[call_id] = part
        elif role == "divider":
            entry = entry_for(rec.uuid, sid, "system")
            entry["parts"].append(text_part(f"{rec.uuid}:0", rec.uuid, sid, "divider", "earlier context was summarized here"))
            entries.append(entry)
        elif role == "user":
            blocks = blocks_of(content)
            for block in blocks:
                if block.get("type") != "tool_result":
                    continue
                part = tools.get(block.get("tool_use_id", ""))
                if part is None:
                    continue
                output = text_of(block.get("content"))
                part["state"] = {
                    "status": "error" if block.get("is_error") else "completed",
                    "input": part["state"].get("input", {}),
                    "title": part["state"].get("title"),
                    "output": output,
                    "error": output if block.get("is_error") else None,
                }
            text = "\n".join(block.get("text", "") for block in blocks if block.get("type") == "text").strip()
            if text.startswith(STOPPED):
                entry = entry_for(rec.uuid, sid, "system")
                entry["info"]["error"] = {"name": "MessageAbortedError", "data": {"message": "stopped"}}
                entries.append(entry)
            elif text and not text.startswith("<"):
                entry = entry_for(rec.uuid, sid, "user")
                entry["parts"].append(text_part(f"{rec.uuid}:0", rec.uuid, sid, "text", text))
                entries.append(entry)
    return entries


class Bus:
    def __init__(self) -> None:
        self.queues: set[asyncio.Queue] = set()

    def emit(self, kind: str, properties: dict) -> None:
        event = {"id": "evt_" + uuid.uuid4().hex[:12], "type": kind, "properties": properties}
        for queue in list(self.queues):
            try:
                queue.put_nowait(event)
            except asyncio.QueueFull:
                self.queues.discard(queue)

    def subscribe(self) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue(maxsize=2000)
        self.queues.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        self.queues.discard(queue)

    def close(self) -> None:
        for queue in list(self.queues):
            queue.shutdown(immediate=True)
        self.queues.clear()


@dataclass
class Run:
    sid: str
    directory: str
    provider: str
    model: str
    client: ClaudeSDKClient | None = None
    reader: asyncio.Task | None = None
    busy: bool = False
    message_id: str | None = None
    message_model: str | None = None
    parts: dict[str, dict] = field(default_factory=dict)
    order: dict[str, list[str]] = field(default_factory=dict)
    tools: dict[str, str] = field(default_factory=dict)
    raw_input: dict[str, str] = field(default_factory=dict)
    idle_handle: asyncio.TimerHandle | None = None
    started: int = field(default_factory=now_ms)
    lease: AsyncExitStack | None = None
    linger: asyncio.TimerHandle | None = None


@dataclass
class Ask:
    kind: str
    payload: dict
    future: asyncio.Future


class Bridge:
    def __init__(self) -> None:
        self.bus = Bus()
        self.runs: dict[str, Run] = {}
        self.fresh: dict[str, dict] = {}
        self.asks: dict[str, Ask] = {}
        self.screens: dict[str, dict] = {}
        self.background: dict[str, list[str]] = {}
        self.misses: dict[str, int] = {}
        self.choices: dict[str, dict] = read_choices()
        self.projects_cache: tuple[float, list[dict]] = (0.0, [])
        self.made: set[str] = set()
        self.releasing: set[asyncio.Task] = set()
        self.opening: dict[str, asyncio.Task] = {}
        self.typing: dict[str, asyncio.Lock] = {}
        self.deliveries: set[asyncio.Task] = set()
        self.commands_cache: dict[str, tuple[float, list[dict]]] = {}
        self.listing: dict[str, asyncio.Lock] = {}

    def live_sessions(self) -> dict[str, dict]:
        found: dict[str, dict] = {}
        for path in SESSIONS_INDEX.glob("*.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            sid = data.get("sessionId")
            pid = data.get("pid")
            if not sid or not pid or sid in self.runs or not Path(f"/proc/{pid}").exists():
                continue
            if data.get("kind") not in (None, "interactive"):
                continue
            waiting = data.get("waitingFor") if data.get("status") == "waiting" else None
            found[sid] = {"name": data.get("name"), "status": data.get("status"), "waiting": waiting, "cwd": data.get("cwd"), "tmux": data.get("tmux"), "pid": pid, "procStart": data.get("procStart")}
        return found

    async def projects(self) -> list[dict]:
        stamp, cached = self.projects_cache
        if time.time() - stamp < PROJECTS_TTL:
            return cached
        infos = await asyncio.to_thread(list_sessions, None, 400)
        lives = list(self.live_sessions().values())
        present = await asyncio.to_thread(existing_dirs, [info.cwd for info in infos] + [live.get("cwd") for live in lives])
        grouped: dict[str, dict] = {}
        for info in infos:
            cwd = info.cwd
            if not cwd or cwd not in present:
                continue
            updated = to_ms(info.last_modified)
            project = grouped.get(cwd)
            if project is None:
                grouped[cwd] = {"id": cwd, "worktree": cwd, "name": Path(cwd).name or cwd, "time": {"created": updated, "updated": updated}, "sandboxes": []}
            elif updated > project["time"]["updated"]:
                project["time"]["updated"] = updated
        for live in lives:
            cwd = live.get("cwd")
            if not cwd or cwd not in present:
                continue
            if cwd in grouped:
                grouped[cwd]["time"]["updated"] = now_ms()
            else:
                grouped[cwd] = {"id": cwd, "worktree": cwd, "name": Path(cwd).name or cwd, "time": {"created": now_ms(), "updated": now_ms()}, "sandboxes": []}
        result = sorted(grouped.values(), key=lambda p: p["time"]["updated"], reverse=True)
        self.projects_cache = (time.time(), result)
        return result

    def session_dict(self, info, live: dict | None, model: tuple[str, str] | None = None) -> dict:
        first = (info.first_prompt or "").strip().splitlines()
        title = info.custom_title or info.summary or (first[0][:80] if first else "")
        session = {
            "id": info.session_id,
            "title": title or (live or {}).get("name") or "",
            "directory": info.cwd or "",
            "parentID": None,
            "time": {"created": to_ms(info.created_at) or to_ms(info.last_modified), "updated": to_ms(info.last_modified)},
        }
        if live:
            session["live"] = {
                "name": live.get("name"),
                "status": live.get("status"),
                "waiting": live.get("waiting"),
                "tmux": live.get("tmux"),
                "background": self.background.get(info.session_id, []),
            }
        if model is not None:
            session["providerID"], session["modelID"] = model
        return session

    async def models_of(self, sids: list[str]) -> dict[str, tuple[str, str]]:
        seen = await asyncio.to_thread(transcript_models, sids)
        result = {}
        for sid in sids:
            run, fresh, chosen = self.runs.get(sid), self.fresh.get(sid), self.choices.get(sid, {})
            if run is not None:
                result[sid] = (run.provider, run.model)
            elif sid in seen:
                result[sid] = (provider_of(seen[sid]), seen[sid])
            elif chosen.get("provider") in PROVIDERS:
                result[sid] = (chosen["provider"], chosen.get("model") or PROVIDERS[chosen["provider"]]["default"])
            elif fresh is not None:
                result[sid] = (fresh["provider"], fresh["model"])
        return result

    async def find(self, query: str, limit: int) -> list[dict]:
        infos = await asyncio.to_thread(list_sessions, None, 400)
        live = self.live_sessions()
        if not query.strip():
            shown = infos[:limit]
            models = await self.models_of([info.session_id for info in shown])
            return [self.session_dict(info, live.get(info.session_id), models.get(info.session_id)) for info in shown]
        by_id = {info.session_id: info for info in infos}
        hits = []
        for sid, snippet in await asyncio.to_thread(find_rows, query):
            if sid in by_id:
                hits.append((by_id[sid], snippet))
                if len(hits) >= limit:
                    break
        models = await self.models_of([info.session_id for info, _ in hits])
        found = []
        for info, snippet in hits:
            session = self.session_dict(info, live.get(info.session_id), models.get(info.session_id))
            session["snippet"] = MARKER.sub("", snippet)
            found.append(session)
        return found

    async def sessions(self, directory: str | None, limit: int) -> list[dict]:
        infos = await asyncio.to_thread(list_sessions, directory, limit)
        live = self.live_sessions()
        listed = {info.session_id for info in infos}
        for sid, desk in live.items():
            if sid in listed or (directory is not None and desk.get("cwd") != directory):
                continue
            info = await asyncio.to_thread(get_session_info, sid, desk.get("cwd"))
            if info is not None:
                infos.append(info)
        models = await self.models_of([info.session_id for info in infos])
        return [self.session_dict(info, live.get(info.session_id), models.get(info.session_id)) for info in infos]

    def statuses(self) -> dict[str, dict]:
        result = {sid: {"type": "busy"} for sid, run in self.runs.items() if run.busy}
        for ask in self.asks.values():
            if ask.payload.get("sessionID") in result:
                result[ask.payload["sessionID"]] = {"type": "busy", "message": "waiting"}
        for sid, live in self.live_sessions().items():
            if live.get("status") in ("busy", "waiting"):
                result[sid] = {"type": "busy", "message": live.get("status")}
        return result

    def env_for(self, provider: str, model: str) -> dict[str, str]:
        if provider == "local":
            spec = LOCAL_MODELS[model]
            return {
                "ANTHROPIC_BASE_URL": OLLAMA_URL,
                "ANTHROPIC_AUTH_TOKEN": "ollama",
                "ANTHROPIC_API_KEY": "",
                "ANTHROPIC_MODEL": model,
                "ANTHROPIC_DEFAULT_OPUS_MODEL": model,
                "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": model,
                "ANTHROPIC_SMALL_FAST_MODEL": model,
                "CLAUDE_CODE_MAX_CONTEXT_TOKENS": str(spec["num_ctx"]),
                "CLAUDE_CODE_MAX_OUTPUT_TOKENS": str(spec["num_ctx"] // 4),
            }
        if provider != "deepseek":
            return {}
        key = DEEPSEEK_KEY_FILE.read_text(encoding="utf-8").strip()
        return {
            "ANTHROPIC_BASE_URL": DEEPSEEK_BASE_URL,
            "ANTHROPIC_AUTH_TOKEN": key,
            "ANTHROPIC_API_KEY": "",
            "ANTHROPIC_MODEL": "deepseek-v4-pro",
            "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro",
            "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
            "ANTHROPIC_SMALL_FAST_MODEL": "deepseek-v4-flash",
            "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "1000000",
        }

    def model_arg(self, provider: str, model: str) -> str:
        if provider == "claude":
            return configured_model() if model in ("", "default") else model
        return model or PROVIDERS[provider]["default"]

    def choice(self, sid: str) -> dict:
        return {"mode": "auto", "effort": None} | self.choices.get(sid, {})

    def choose(self, sid: str, **changes) -> dict:
        now = self.choice(sid) | changes
        self.choices.pop(sid, None)
        self.choices[sid] = now
        while len(self.choices) > CHOICES_KEPT:
            self.choices.pop(next(iter(self.choices)))
        CHOICES_FILE.parent.mkdir(parents=True, exist_ok=True)
        spare = CHOICES_FILE.with_suffix(".tmp")
        spare.write_text(json.dumps(self.choices), encoding="utf-8")
        os.replace(spare, CHOICES_FILE)
        shown = {"providerID": now.get("provider"), "modelID": now.get("model"), "mode": now["mode"], "effort": now["effort"]}
        self.bus.emit("session.settings", {"sessionID": sid, "settings": shown})
        return now

    def desk_settings(self, sid: str, live: dict) -> dict:
        stored = self.choice(sid)
        view = {"mode": None, "effort": None, "model": None}
        try:
            pane = pane_of(int(live["pid"]))
            if pane is not None:
                view = desk_view(pane_lines(pane))
        except (RuntimeError, OSError, subprocess.SubprocessError, ValueError):
            pass
        model = view["model"] or stored.get("model")
        if model is None:
            seen = last_model(sid)
            model = model_alias(provider_of(seen), seen)
        return {"providerID": provider_of(model), "modelID": model, "mode": view["mode"] or stored["mode"], "effort": view["effort"] or stored["effort"]}

    async def settings_of(self, sid: str) -> dict:
        live = self.live_sessions().get(sid)
        if live is not None:
            return await asyncio.to_thread(self.desk_settings, sid, live)
        stored = self.choice(sid)
        provider, model = stored.get("provider"), stored.get("model")
        if provider not in PROVIDERS:
            run, fresh = self.runs.get(sid), self.fresh.get(sid)
            if run is not None:
                provider, model = run.provider, run.model
            elif fresh is not None:
                provider, model = fresh["provider"], fresh["model"]
            else:
                seen = await asyncio.to_thread(last_model, sid)
                provider = provider_of(seen)
                model = model_alias(provider, seen)
        return {"providerID": provider, "modelID": model or PROVIDERS[provider]["default"], "mode": stored["mode"], "effort": stored["effort"]}

    async def apply_effort(self, run: Run, effort: str | None) -> None:
        send = getattr(getattr(run.client, "_query", None), "_send_control_request", None)
        try:
            if send is None:
                raise RuntimeError("no control channel")
            await send({"subtype": "apply_flag_settings", "settings": {"effortLevel": effort}})
        except Exception:
            if run.busy:
                raise
            await self.stop_run(run)

    async def make_local(self, model: str) -> None:
        if model in self.made:
            return
        spec = LOCAL_MODELS[model]
        async with ClientSession(timeout=ClientTimeout(total=120)) as http:
            async with http.post(f"{OLLAMA_URL}/api/show", json={"model": model}) as shown:
                if shown.status == 200:
                    parameters = (await shown.json()).get("parameters") or ""
                    if re.search(rf"^num_ctx\s+{spec['num_ctx']}\s*$", parameters, re.M):
                        self.made.add(model)
                        return
            body = {"model": model, "from": spec["from"], "parameters": {"num_ctx": spec["num_ctx"]}, "stream": False}
            async with http.post(f"{OLLAMA_URL}/api/create", json=body) as made:
                if made.status != 200:
                    raise RuntimeError(f"ollama could not make {model} from {spec['from']}: {(await made.text())[:160]}")
        self.made.add(model)

    async def take_gpu(self, run: Run) -> None:
        for other in list(self.runs.values()):
            if other is not run and other.lease is not None and not other.busy:
                self.free_gpu(other)
        if self.releasing:
            await asyncio.gather(*self.releasing, return_exceptions=True)
        model = run.model
        lease = AsyncExitStack()
        await lease.enter_async_context(gpu_lock.acquire_async(GPU_HOLDER, LOCAL_TURN_SECONDS, on_release=lambda: evict_model(OLLAMA_URL, model)))
        run.lease = lease

    def free_gpu(self, run: Run) -> None:
        if run.linger:
            run.linger.cancel()
            run.linger = None
        lease, run.lease = run.lease, None
        if lease is None:
            return
        task = asyncio.ensure_future(lease.aclose())
        self.releasing.add(task)
        task.add_done_callback(self.releasing.discard)

    def settle_gpu(self, run: Run) -> None:
        if run.lease is None:
            return
        if run.linger:
            run.linger.cancel()
        run.linger = asyncio.get_running_loop().call_later(LOCAL_LINGER_SECONDS, lambda: None if run.busy else self.free_gpu(run))

    async def ensure_run(self, sid: str, directory: str, provider: str, model: str) -> Run:
        run = self.runs.get(sid)
        if run is not None and run.provider == provider and (provider != "local" or run.model == model or run.busy):
            if provider != "local" and run.model != model and run.client is not None:
                await run.client.set_model(self.model_arg(provider, model))
                run.model = model
            return run
        if run is not None:
            await self.stop_run(run)
        fresh = sid in self.fresh
        run = Run(sid=sid, directory=directory, provider=provider, model=model)
        choice = self.choice(sid)
        options = ClaudeAgentOptions(
            cwd=directory,
            env=self.env_for(provider, model),
            model=self.model_arg(provider, model),
            can_use_tool=self.permission_handler(sid),
            include_partial_messages=True,
            permission_mode=choice["mode"],
            setting_sources=SETTING_SOURCES,
            **({"effort": choice["effort"]} if choice["effort"] else {}),
            cli_path=CLI_PATH,
            **({"session_id": sid} if fresh else {"resume": sid}),
        )
        run.client = ClaudeSDKClient(options)
        await run.client.connect()
        self.fresh.pop(sid, None)
        self.runs[sid] = run
        run.reader = asyncio.create_task(self.read(run))
        return run

    async def commands(self, directory: str) -> list[dict]:
        stamp, cached = self.commands_cache.get(directory, (0.0, []))
        if cached and time.time() - stamp < COMMANDS_TTL:
            return cached
        async with self.listing.setdefault(directory, asyncio.Lock()):
            stamp, cached = self.commands_cache.get(directory, (0.0, []))
            if cached and time.time() - stamp < COMMANDS_TTL:
                return cached
            running = next((run.client for run in self.runs.values() if run.directory == directory and run.client is not None), None)
            info = await (running.get_server_info() if running is not None else server_info(directory))
            listed = slash_commands((info or {}).get("commands") or [])
            self.commands_cache[directory] = (time.time(), listed)
            return listed

    def open_on_desk(self, sid: str, directory: str, provider: str, model: str) -> asyncio.Task:
        task = self.opening.get(sid)
        if task is None:
            task = asyncio.ensure_future(self.bring_up(sid, directory, provider, model))
            self.opening[sid] = task
            task.add_done_callback(lambda _: self.opening.pop(sid, None))
        return task

    async def bring_up(self, sid: str, directory: str, provider: str, model: str) -> str:
        self.fresh.pop(sid, None)
        known = await asyncio.to_thread(session_cwd, sid)
        command = desk_command(sid, DESK_COMMANDS[provider], self.model_arg(provider, model), self.choice(sid), known is None)
        place, pane = await asyncio.to_thread(open_window, known or directory, command)
        deadline = time.monotonic() + DESK_READY_SECONDS
        while time.monotonic() < deadline:
            await asyncio.sleep(0.5)
            live = self.live_sessions().get(sid)
            if live is not None and live.get("status") == "idle" and await asyncio.to_thread(desk_ready, pane):
                return pane
        raise RuntimeError(f"opened in tmux window {place} on the desktop, but it was not ready within {DESK_READY_SECONDS} s; a dialog there may be waiting")

    def deliver(self, sid: str, opened: asyncio.Task, text: str) -> None:
        lock = self.typing.setdefault(sid, asyncio.Lock())

        async def run() -> None:
            async with lock:
                try:
                    pane = await opened
                    await asyncio.to_thread(type_into, pane, text)
                except Exception as err:
                    self.bus.emit("session.error", {"sessionID": sid, "error": {"name": "UnknownError", "data": {"message": str(err)[:300]}}})
                    self.bus.emit("session.status", {"sessionID": sid, "status": {"type": "idle"}})
                    self.bus.emit("session.idle", {"sessionID": sid})

        task = asyncio.ensure_future(run())
        self.deliveries.add(task)
        task.add_done_callback(self.deliveries.discard)

    def reopen(self, sid: str, opened: asyncio.Task) -> None:
        async def run() -> None:
            try:
                await opened
            except Exception as err:
                self.bus.emit("session.error", {"sessionID": sid, "error": {"name": "UnknownError", "data": {"message": str(err)[:300]}}})

        task = asyncio.ensure_future(run())
        self.deliveries.add(task)
        task.add_done_callback(self.deliveries.discard)

    async def stop_run(self, run: Run) -> None:
        if run.idle_handle:
            run.idle_handle.cancel()
        self.runs.pop(run.sid, None)
        for key, ask in list(self.asks.items()):
            if ask.payload.get("sessionID") == run.sid and not ask.future.done():
                ask.future.set_result(None)
                self.asks.pop(key, None)
        if run.reader:
            run.reader.cancel()
        if run.client:
            try:
                await run.client.disconnect()
            except Exception:
                pass
        self.free_gpu(run)
        self.set_busy(run, False)

    def set_busy(self, run: Run, busy: bool) -> None:
        run.busy = busy
        self.bus.emit("session.status", {"sessionID": run.sid, "status": {"type": "busy" if busy else "idle"}})
        if not busy:
            self.bus.emit("session.idle", {"sessionID": run.sid})

    def schedule_idle(self, run: Run) -> None:
        if run.idle_handle:
            run.idle_handle.cancel()
        loop = asyncio.get_running_loop()
        run.idle_handle = loop.call_later(IDLE_SECONDS, lambda: asyncio.ensure_future(self.stop_run(run)))

    async def read(self, run: Run) -> None:
        try:
            async for message in run.client.receive_messages():
                self.handle(run, message)
        except asyncio.CancelledError:
            raise
        except Exception as err:
            self.bus.emit("session.error", {"sessionID": run.sid, "error": {"name": "UnknownError", "data": {"message": str(err)[:300]}}})
            self.runs.pop(run.sid, None)
            self.free_gpu(run)
            self.set_busy(run, False)

    def part_id(self, run: Run, index: int) -> str:
        return f"{run.message_id}:{index}"

    def emit_part(self, run: Run, part: dict) -> None:
        self.bus.emit("message.part.updated", {"sessionID": run.sid, "part": part, "time": now_ms()})

    def start_message(self, run: Run, message_id: str, model: str | None) -> None:
        run.message_id = message_id
        run.message_model = model
        run.order.setdefault(message_id, [])
        info = entry_for(message_id, run.sid, "assistant", model, now_ms())["info"]
        self.bus.emit("message.updated", {"sessionID": run.sid, "info": info})

    def handle(self, run: Run, message) -> None:
        if isinstance(message, SystemMessage):
            mode = message.data.get("permissionMode") if isinstance(message.data, dict) else None
            if mode in MODES and mode != self.choice(run.sid)["mode"]:
                self.choose(run.sid, mode=mode)
            if message.subtype == "init":
                self.set_busy(run, True)
            return
        if isinstance(message, StreamEvent):
            self.handle_stream(run, message.event)
            return
        if isinstance(message, AssistantMessage):
            if run.message_id != message.message_id and message.message_id:
                self.start_message(run, message.message_id, message.model)
            for block in message.content:
                if isinstance(block, ToolUseBlock):
                    part_id = run.tools.get(block.id)
                    part = run.parts.get(part_id) if part_id else None
                    if part is None:
                        part = tool_part(block.id, run.message_id, run.sid, block.id, block.name, block.input)
                        self.register_part(run, block.id, part)
                        run.tools[block.id] = block.id
                    else:
                        part["state"] = {"status": "pending", "input": block.input, "title": summarize(block.name, block.input)}
                    self.emit_part(run, part)
                elif isinstance(block, (TextBlock, ThinkingBlock)) and not any(p["type"] in ("text", "reasoning") for p in self.parts_of(run, run.message_id)):
                    kind = "text" if isinstance(block, TextBlock) else "reasoning"
                    part = text_part(self.part_id(run, len(run.order.get(run.message_id, []))), run.message_id, run.sid, kind, block.text if isinstance(block, TextBlock) else block.thinking)
                    self.register_part(run, part["id"], part)
                    self.emit_part(run, part)
            return
        if isinstance(message, UserMessage):
            content = message.content if isinstance(message.content, list) else []
            for block in content:
                if isinstance(block, ToolResultBlock):
                    part_id = run.tools.get(block.tool_use_id)
                    part = run.parts.get(part_id) if part_id else None
                    if part is None:
                        continue
                    output = text_of(block.content) if not isinstance(block.content, str) else block.content
                    part["state"] = {
                        "status": "error" if block.is_error else "completed",
                        "input": part["state"].get("input", {}),
                        "title": part["state"].get("title"),
                        "output": output,
                        "error": output if block.is_error else None,
                    }
                    self.emit_part(run, part)
            return
        if isinstance(message, ResultMessage):
            if message.is_error:
                detail = message.result or "; ".join(str(e) for e in (message.errors or [])) or message.subtype
                self.bus.emit("session.error", {"sessionID": run.sid, "error": {"name": "UnknownError", "data": {"message": str(detail)[:300]}}})
            self.set_busy(run, False)
            self.schedule_idle(run)
            self.settle_gpu(run)

    def register_part(self, run: Run, part_id: str, part: dict) -> None:
        run.parts[part_id] = part
        run.order.setdefault(run.message_id, []).append(part_id)

    def parts_of(self, run: Run, message_id: str | None) -> list[dict]:
        return [run.parts[pid] for pid in run.order.get(message_id or "", []) if pid in run.parts]

    def handle_stream(self, run: Run, event: dict) -> None:
        kind = event.get("type")
        if kind == "message_start":
            message = event.get("message") or {}
            self.start_message(run, message.get("id") or "msg_" + uuid.uuid4().hex[:12], message.get("model"))
        elif kind == "content_block_start":
            block = event.get("content_block") or {}
            index = event.get("index", 0)
            block_type = block.get("type")
            if block_type == "tool_use":
                call_id = block.get("id") or self.part_id(run, index)
                part = tool_part(call_id, run.message_id, run.sid, call_id, block.get("name", "tool"), {})
                self.register_part(run, call_id, part)
                run.tools[call_id] = call_id
                run.raw_input[call_id] = ""
                run.tools[f"index:{index}"] = call_id
            elif block_type in ("text", "thinking"):
                part = text_part(self.part_id(run, index), run.message_id, run.sid, "text" if block_type == "text" else "reasoning", block.get("text") or block.get("thinking") or "")
                self.register_part(run, part["id"], part)
            else:
                return
            self.emit_part(run, part)
        elif kind == "content_block_delta":
            index = event.get("index", 0)
            delta = event.get("delta") or {}
            delta_type = delta.get("type")
            if delta_type in ("text_delta", "thinking_delta"):
                part = run.parts.get(self.part_id(run, index))
                chunk = delta.get("text") if delta_type == "text_delta" else delta.get("thinking")
                if part is None or not chunk:
                    return
                part["text"] = (part.get("text") or "") + chunk
                self.bus.emit("message.part.delta", {"sessionID": run.sid, "messageID": run.message_id, "partID": part["id"], "field": "text", "delta": chunk})
            elif delta_type == "input_json_delta":
                call_id = run.tools.get(f"index:{index}")
                if call_id:
                    run.raw_input[call_id] = run.raw_input.get(call_id, "") + (delta.get("partial_json") or "")
        elif kind == "content_block_stop":
            index = event.get("index", 0)
            call_id = run.tools.pop(f"index:{index}", None)
            if call_id and call_id in run.parts:
                raw = run.raw_input.pop(call_id, "")
                try:
                    data = json.loads(raw) if raw else {}
                except ValueError:
                    data = {}
                part = run.parts[call_id]
                if isinstance(data, dict) and data:
                    part["state"] = {"status": "pending", "input": data, "title": summarize(part["tool"], data)}
                self.emit_part(run, part)

    def live_entries(self, sid: str) -> list[dict]:
        run = self.runs.get(sid)
        if run is None:
            return []
        entries = []
        for message_id in run.order:
            entry = entry_for(message_id, sid, "assistant", run.message_model, run.started)
            entry["parts"] = self.parts_of(run, message_id)
            entries.append(entry)
        return entries

    def permission_handler(self, sid: str):
        async def can_use_tool(tool: str, data: dict, context):
            if tool == "AskUserQuestion":
                return await self.ask_question(sid, data)
            return await self.ask_permission(sid, tool, data, context)

        return can_use_tool

    async def wait(self, ask: Ask):
        sid = ask.payload["sessionID"]
        self.asks[ask.payload["id"]] = ask
        self.bus.emit("session.status", {"sessionID": sid, "status": {"type": "busy", "message": "waiting"}})
        try:
            return await ask.future
        finally:
            self.asks.pop(ask.payload["id"], None)
            run = self.runs.get(sid)
            if run is not None and run.busy and not any(a.payload.get("sessionID") == sid for a in self.asks.values()):
                self.bus.emit("session.status", {"sessionID": sid, "status": {"type": "busy"}})

    async def sync_screen(self, sid: str, live: dict | None, patient: bool = True) -> dict | None:
        payload = None
        if live is not None and live.get("status") == "waiting":
            try:
                payload = await asyncio.to_thread(screen_payload, sid, live, self.screens.get(sid))
            except (RuntimeError, OSError, subprocess.SubprocessError, ValueError):
                payload = None
            if payload is not None and not payload["options"]:
                self.misses[sid] = self.misses.get(sid, 0) + 1
                if not patient or self.misses[sid] <= SCREEN_MISSES:
                    payload = self.screens.get(sid)
            elif payload is not None:
                self.misses.pop(sid, None)
        else:
            self.misses.pop(sid, None)
        before = self.screens.get(sid)
        if payload is None:
            if before is not None:
                self.screens.pop(sid, None)
                self.bus.emit("screen.cleared", {"sessionID": sid, "requestID": before["id"]})
            return None
        if before is None or before["id"] != payload["id"]:
            self.screens[sid] = payload
            self.bus.emit("screen.asked", payload)
        return payload

    async def sync_background(self, live: dict[str, dict]) -> None:
        seen = await asyncio.to_thread(desk_backgrounds, live)
        for sid in [s for s in self.background if s not in live]:
            self.background.pop(sid)
            self.bus.emit("session.background", {"sessionID": sid, "tasks": []})
        for sid, tasks in seen.items():
            if tasks is None or tasks == self.background.get(sid, []):
                continue
            if tasks:
                self.background[sid] = tasks
            else:
                self.background.pop(sid, None)
            self.bus.emit("session.background", {"sessionID": sid, "tasks": tasks})

    async def ask_permission(self, sid: str, tool: str, data: dict, context):
        run = self.runs.get(sid)
        suggestions = list(getattr(context, "suggestions", None) or [])
        plan = plan_text(data) if tool == "ExitPlanMode" else None
        payload = {
            "id": "per_" + uuid.uuid4().hex[:16],
            "sessionID": sid,
            "permission": tool,
            "patterns": [getattr(context, "title", None) or summarize(tool, data)],
            "always": [json.dumps(s)[:120] for s in suggestions],
            "metadata": {k: v for k, v in data.items() if k in INPUT_KEYS and isinstance(v, str)} | ({"description": context.description} if getattr(context, "description", None) else {}) | ({"plan": plan} if plan else {}),
            "tool": {"messageID": run.message_id if run else "", "callID": getattr(context, "tool_use_id", None) or ""},
        }
        ask = Ask("permission", payload, asyncio.get_running_loop().create_future())
        self.bus.emit("permission.asked", payload)
        reply = await self.wait(ask)
        self.bus.emit("permission.replied", {"sessionID": sid, "requestID": payload["id"], "reply": reply or "reject"})
        if reply == "always":
            return PermissionResultAllow(updated_permissions=suggestions or None)
        if reply == "once":
            return PermissionResultAllow()
        return PermissionResultDeny(message="rejected from the phone")

    async def ask_question(self, sid: str, data: dict):
        questions = []
        for item in data.get("questions") or []:
            if not isinstance(item, dict):
                continue
            questions.append({
                "question": item.get("question", ""),
                "header": item.get("header", ""),
                "options": [{"label": o.get("label", ""), "description": o.get("description", "")} for o in item.get("options") or [] if isinstance(o, dict)],
                "multiple": bool(item.get("multiSelect")),
                "custom": False,
            })
        payload = {"id": "que_" + uuid.uuid4().hex[:16], "sessionID": sid, "questions": questions}
        ask = Ask("question", payload, asyncio.get_running_loop().create_future())
        self.bus.emit("question.asked", payload)
        answers = await self.wait(ask)
        if answers is None:
            self.bus.emit("question.rejected", {"sessionID": sid, "requestID": payload["id"]})
            return PermissionResultDeny(message="the question was skipped from the phone")
        self.bus.emit("question.replied", {"sessionID": sid, "requestID": payload["id"], "answers": answers})
        chosen = {}
        for question, picked in zip(questions, answers, strict=False):
            chosen[question["question"]] = ", ".join(picked)
        return PermissionResultAllow(updated_input={**data, "answers": chosen})

    def reply(self, ask_id: str, value) -> bool:
        ask = self.asks.get(ask_id)
        if ask is None or ask.future.done():
            return False
        ask.future.set_result(value)
        return True

    def pending(self, kind: str) -> list[dict]:
        return [ask.payload for ask in self.asks.values() if ask.kind == kind]


def json_error(message: str, status: int) -> web.Response:
    return web.json_response({"error": message}, status=status)


@web.middleware
async def auth_middleware(request: web.Request, handler):
    password = request.app[PASSWORD]
    if password is not None:
        header = request.headers.get("Authorization", "")
        ok = False
        if header.startswith("Basic "):
            try:
                user, _, given = base64.b64decode(header[6:]).decode("utf-8").partition(":")
                ok = user == USER and secrets.compare_digest(given, password)
            except (ValueError, UnicodeDecodeError):
                ok = False
        if not ok:
            return web.json_response({"error": "unauthorized"}, status=401, headers={"WWW-Authenticate": 'Basic realm="claude-bridge"'})
    return await handler(request)


def bridge_of(request: web.Request) -> Bridge:
    return request.app[BRIDGE]


async def health(request: web.Request) -> web.Response:
    return web.json_response({"healthy": True, "version": VERSION})


async def providers(request: web.Request) -> web.Response:
    return web.json_response({
        "all": [{"id": pid, "name": p["name"], "models": {m: {"id": m, "name": m} for m in p["models"]}} for pid, p in PROVIDERS.items()],
        "connected": list(PROVIDERS),
        "default": {pid: p["default"] for pid, p in PROVIDERS.items()},
    })


async def config(request: web.Request) -> web.Response:
    return web.json_response({"model": "claude/default"})


async def projects(request: web.Request) -> web.Response:
    return web.json_response(await bridge_of(request).projects())


async def sessions(request: web.Request) -> web.Response:
    directory = request.query.get("directory") or None
    limit = int(request.query.get("limit") or 30)
    return web.json_response(await bridge_of(request).sessions(directory, limit))


async def find(request: web.Request) -> web.Response:
    limit = max(1, min(int(request.query.get("limit") or 60), 200))
    try:
        return web.json_response(await bridge_of(request).find(request.query.get("q") or "", limit))
    except (OSError, subprocess.SubprocessError) as err:
        return json_error(f"search failed: {str(err)[:160]}", 503)


async def server_info(directory: str) -> dict | None:
    options = ClaudeAgentOptions(cwd=directory, setting_sources=SETTING_SOURCES, cli_path=CLI_PATH)
    async with ClaudeSDKClient(options) as client:
        return await client.get_server_info()


def slash_commands(found: list) -> list[dict]:
    listed: dict[str, dict] = {}
    for item in found:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip().lstrip("/")
        description = " ".join(str(item.get("description") or "").split())
        if not name or name.startswith("_") or name in listed or COMMAND_ELSEWHERE.search(description):
            continue
        listed[name] = {"name": name, "description": description, "argumentHint": str(item.get("argumentHint") or "").strip()}
    return list(listed.values())


async def commands(request: web.Request) -> web.Response:
    directory = request.query.get("directory") or str(HOME)
    if not await asyncio.to_thread(os.path.isdir, directory):
        return json_error(f"{directory} is not a folder on the desktop", 400)
    try:
        listed = await bridge_of(request).commands(directory)
    except Exception as err:
        return json_error(f"could not list the commands: {str(err)[:200]}", 503)
    return web.json_response(listed)


def existing_dirs(paths: list) -> set[str]:
    return {path for path in paths if path and Path(path).is_dir()}


def upload_name(raw: str) -> str:
    name = re.sub(r"[\x00-\x1f\x7f/\\]+", "_", raw).strip().lstrip(".")
    if not name:
        return ""
    path = Path(name)
    return path.stem[:100].strip() + path.suffix[:12]


async def upload(request: web.Request) -> web.Response:
    name = upload_name(request.query.get("name") or "")
    suffix = IMAGE_TYPES.get((request.content_type or "").lower())
    if not name and suffix is None:
        return json_error("only pictures can be attached without a file name", 415)
    data = await request.read()
    if not data:
        return json_error("empty upload", 400)
    stamp = f"{time.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}"
    path = UPLOADS / stamp / name if name else UPLOADS / f"{stamp}{suffix}"
    path.parent.mkdir(parents=True, exist_ok=True)
    await asyncio.to_thread(path.write_bytes, data)
    return web.json_response({"path": str(path)})


async def session_status(request: web.Request) -> web.Response:
    return web.json_response(bridge_of(request).statuses())


async def create_session(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    directory = request.query.get("directory") or str(HOME)
    try:
        body = await request.json()
    except ValueError:
        body = {}
    body = body if isinstance(body, dict) else {}
    model = body.get("model") if isinstance(body.get("model"), dict) else {}
    provider = model.get("providerID") if model.get("providerID") in PROVIDERS else "claude"
    sid = str(uuid.uuid4())
    chosen = model.get("id") or PROVIDERS[provider]["default"]
    bridge.fresh[sid] = {"directory": directory, "provider": provider, "model": chosen}
    mode = body.get("mode") if body.get("mode") in MODES else "auto"
    effort = body.get("effort") if body.get("effort") in EFFORTS else None
    bridge.choose(sid, provider=provider, model=chosen, mode=mode, effort=effort)
    stamp = now_ms()
    return web.json_response({"id": sid, "title": body.get("title") or "", "directory": directory, "parentID": None, "time": {"created": stamp, "updated": stamp}})


async def messages(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    sid = request.match_info["sid"]
    directory = request.query.get("directory") or None
    limit = int(request.query.get("limit") or 80)
    try:
        entries = await asyncio.to_thread(session_entries, sid, directory, limit)
    except Exception:
        entries = []
    if limit and len(entries) > limit:
        entries = entries[-limit:]
    known = {entry["info"]["id"] for entry in entries}
    for entry in bridge.live_entries(sid):
        if entry["info"]["id"] not in known:
            entries.append(entry)
    return web.json_response(entries)


def prompt_text(body: dict) -> str:
    parts = body.get("parts") if isinstance(body.get("parts"), list) else []
    return "\n".join(p.get("text", "") for p in parts if isinstance(p, dict) and p.get("type") == "text").strip()


async def prompt(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    sid = request.match_info["sid"]
    body = await request.json()
    text = prompt_text(body if isinstance(body, dict) else {})
    if not text:
        return json_error("text required", 400)
    live = bridge.live_sessions().get(sid)
    if live is not None:
        name = live.get("name") or "an open session"
        if live.get("status") == "waiting":
            return json_error(f"{name} is waiting for an answer on the desktop; answer that first", 409)
        try:
            pane = await asyncio.to_thread(pane_of, int(live["pid"]))
        except (RuntimeError, OSError, subprocess.SubprocessError, ValueError) as err:
            return json_error(f"running on the desktop as {name}, and tmux could not be reached: {str(err)[:120]}", 409)
        if pane is None:
            return json_error(f"running on the desktop as {name} outside tmux; send from there", 409)
        try:
            await asyncio.to_thread(type_into, pane, text)
        except (RuntimeError, OSError, subprocess.SubprocessError) as err:
            return json_error(f"could not type into {name}: {str(err)[:120]}", 503)
        bridge.bus.emit("session.status", {"sessionID": sid, "status": {"type": "busy", "message": "busy"}})
        return web.Response(status=204)
    fresh = bridge.fresh.get(sid)
    run = bridge.runs.get(sid)
    stored = bridge.choice(sid)
    directory = request.query.get("directory") or (fresh or {}).get("directory") or (run.directory if run else None) or str(HOME)
    model = body.get("model") if isinstance(body.get("model"), dict) else {}
    provider = model.get("providerID") or (fresh or {}).get("provider") or (run.provider if run else None) or stored.get("provider") or "claude"
    if provider not in PROVIDERS:
        return json_error(f"unknown provider {provider}", 400)
    chosen = model.get("modelID") or (fresh or {}).get("model") or (run.model if run and run.provider == provider else None) or (stored.get("model") if stored.get("provider") == provider else None) or PROVIDERS[provider]["default"]
    if provider == "local" and chosen not in LOCAL_MODELS:
        return json_error(f"unknown local model {chosen}", 400)
    if (stored.get("provider"), stored.get("model")) != (provider, chosen):
        bridge.choose(sid, provider=provider, model=chosen)
    if sid in bridge.opening or (provider in DESK_COMMANDS and (run is None or run.provider != provider)):
        if run is not None and sid not in bridge.opening:
            if run.busy:
                return json_error("still working on the last turn; stop it or let it finish, then switch", 409)
            await bridge.stop_run(run)
        opened = bridge.open_on_desk(sid, directory, provider, chosen)
        bridge.deliver(sid, opened, text)
        bridge.bus.emit("session.status", {"sessionID": sid, "status": {"type": "busy", "message": "busy"}})
        return web.Response(status=204)
    if provider == "local":
        try:
            await bridge.make_local(chosen)
        except (ClientError, RuntimeError, OSError, asyncio.TimeoutError) as err:
            return json_error(f"the local model is not ready: {str(err)[:200]}", 503)
    try:
        run = await bridge.ensure_run(sid, directory, provider, chosen)
    except Exception as err:
        return json_error(f"could not start claude: {str(err)[:200]}", 503)
    if run.provider == "local" and run.lease is None:
        try:
            await bridge.take_gpu(run)
        except GpuBusy as busy:
            bridge.schedule_idle(run)
            return json_error(f"the GPU is busy: {busy}", 409)
    if run.linger:
        run.linger.cancel()
        run.linger = None
    if run.idle_handle:
        run.idle_handle.cancel()
    user_id = "usr_" + uuid.uuid4().hex[:16]
    bridge.bus.emit("message.updated", {"sessionID": sid, "info": entry_for(user_id, sid, "user", created=now_ms())["info"]})
    bridge.bus.emit("message.part.updated", {"sessionID": sid, "part": text_part(f"{user_id}:0", user_id, sid, "text", text), "time": now_ms()})
    bridge.set_busy(run, True)
    try:
        await run.client.query(text)
    except Exception:
        bridge.set_busy(run, False)
        bridge.free_gpu(run)
        raise
    return web.Response(status=204)


async def abort(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    sid = request.match_info["sid"]
    live = bridge.live_sessions().get(sid)
    if live is not None:
        if live.get("status") != "busy":
            return web.json_response(False)
        try:
            pane = await asyncio.to_thread(pane_of, int(live["pid"]))
            if pane is None:
                return json_error("that session runs outside tmux; stop it there", 409)
            said = await asyncio.to_thread(last_prompt, sid)
            await asyncio.to_thread(stop_pane, pane, said)
        except (RuntimeError, OSError, subprocess.SubprocessError, ValueError) as err:
            return json_error(f"could not reach the desktop terminal: {str(err)[:120]}", 503)
        return web.json_response(True)
    run = bridge.runs.get(sid)
    if run is None or run.client is None:
        return web.json_response(False)
    await run.client.interrupt()
    return web.json_response(True)


async def close_session(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    sid = request.match_info["sid"]
    if sid in bridge.opening:
        return json_error("it is still opening on the desktop; close it once it is up", 409)
    run = bridge.runs.get(sid)
    if run is not None:
        await bridge.stop_run(run)
        return web.json_response(True)
    live = bridge.live_sessions().get(sid)
    if live is None:
        return web.json_response(False)
    try:
        await asyncio.to_thread(end_process, int(live["pid"]), live.get("procStart"))
    except (OSError, RuntimeError, ValueError) as err:
        return json_error(f"could not close it on the desktop: {str(err)[:160]}", 503)
    bridge.bus.emit("session.status", {"sessionID": sid, "status": {"type": "idle"}})
    bridge.bus.emit("session.idle", {"sessionID": sid})
    return web.json_response(True)


async def get_settings(request: web.Request) -> web.Response:
    return web.json_response(await bridge_of(request).settings_of(request.match_info["sid"]))


async def set_settings(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    sid = request.match_info["sid"]
    try:
        body = await request.json()
    except ValueError:
        body = None
    if not isinstance(body, dict):
        return json_error("a settings object is required", 400)
    changes: dict = {}
    if "mode" in body:
        if body["mode"] not in MODES:
            return json_error(f"mode must be one of {', '.join(MODES)}", 400)
        changes["mode"] = body["mode"]
    if "effort" in body:
        if body["effort"] is not None and body["effort"] not in EFFORTS:
            return json_error(f"effort must be one of {', '.join(EFFORTS)} or null", 400)
        changes["effort"] = body["effort"]
    if "providerID" in body or "modelID" in body:
        provider, model = body.get("providerID"), body.get("modelID")
        if provider not in PROVIDERS or not isinstance(model, str) or not model or (provider == "local" and model not in LOCAL_MODELS):
            return json_error("unknown model", 400)
        changes["provider"], changes["model"] = provider, model
    if not changes:
        return json_error("nothing to change", 400)
    live = bridge.live_sessions().get(sid)
    if live is not None:
        return await tune_live(bridge, sid, live, changes)
    bridge.choose(sid, **changes)
    fresh = bridge.fresh.get(sid)
    if fresh is not None and "provider" in changes:
        fresh["provider"], fresh["model"] = changes["provider"], changes["model"]
    run = bridge.runs.get(sid)
    if run is not None and run.client is not None:
        try:
            if "mode" in changes:
                await run.client.set_permission_mode(changes["mode"])
            if "effort" in changes:
                await bridge.apply_effort(run, changes["effort"])
            if run.provider != "local" and changes.get("provider") == run.provider and changes.get("model") != run.model and bridge.runs.get(sid) is run:
                await run.client.set_model(bridge.model_arg(run.provider, changes["model"]))
                run.model = changes["model"]
        except Exception as err:
            return json_error(f"saved; the running session did not take it yet: {str(err)[:120]}", 503)
    return web.json_response(await bridge.settings_of(sid))


async def switch_harness(bridge: Bridge, sid: str, live: dict, now: dict, changes: dict) -> web.Response:
    if live.get("status") in ("busy", "shell"):
        return json_error("that terminal is still working; stop it or let it finish, then switch", 409)
    try:
        await asyncio.to_thread(end_process, int(live["pid"]), live.get("procStart"))
    except (OSError, RuntimeError, ValueError) as err:
        return json_error(f"could not close the desktop terminal: {str(err)[:160]}", 503)
    kept = bridge.choose(sid, **({"provider": now["providerID"], "model": now["modelID"], "mode": now["mode"], "effort": now["effort"]} | changes))
    bridge.bus.emit("session.status", {"sessionID": sid, "status": {"type": "idle"}})
    if kept["provider"] in DESK_COMMANDS:
        bridge.reopen(sid, bridge.open_on_desk(sid, live.get("cwd") or str(HOME), kept["provider"], kept["model"]))
    return web.json_response({"providerID": kept["provider"], "modelID": kept["model"], "mode": kept["mode"], "effort": kept["effort"]})


async def tune_live(bridge: Bridge, sid: str, live: dict, changes: dict) -> web.Response:
    if live.get("status") == "waiting":
        return json_error("that terminal is waiting on an answer; answer it first", 409)
    now = await asyncio.to_thread(bridge.desk_settings, sid, live)
    if "provider" in changes:
        if changes["provider"] != now["providerID"]:
            return await switch_harness(bridge, sid, live, now, changes)
        if changes["model"] == now["modelID"]:
            changes = {key: value for key, value in changes.items() if key not in ("provider", "model")}
    try:
        pane = await asyncio.to_thread(pane_of, int(live["pid"]))
        if pane is None:
            return json_error("that session runs outside tmux; change it there", 409)
        await asyncio.to_thread(tune_desk, pane, now["providerID"], changes)
    except RuntimeError as err:
        return json_error(str(err)[:160], 409)
    except (OSError, subprocess.SubprocessError, ValueError) as err:
        return json_error(f"could not reach the desktop terminal: {str(err)[:120]}", 503)
    kept = bridge.choose(sid, **({"provider": now["providerID"], "model": now["modelID"], "mode": now["mode"], "effort": now["effort"]} | changes))
    return web.json_response({"providerID": kept["provider"], "modelID": kept["model"], "mode": kept["mode"], "effort": kept["effort"]})


async def rename(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    sid = request.match_info["sid"]
    body = await request.json()
    title = (body or {}).get("title") if isinstance(body, dict) else None
    title = " ".join(str(title).split())[:200] if title else ""
    if not title:
        return json_error("title required", 400)
    live = bridge.live_sessions().get(sid)
    typed = False
    if live is not None and live.get("status") != "waiting":
        try:
            pane = await asyncio.to_thread(pane_of, int(live["pid"]))
            if pane is not None:
                await asyncio.to_thread(type_into, pane, f"/rename {title}")
                typed = True
        except (RuntimeError, OSError, subprocess.SubprocessError, ValueError):
            typed = False
    if not typed:
        await asyncio.to_thread(rename_session, sid, title, request.query.get("directory") or None)
    bridge_of(request).bus.emit("session.updated", {"sessionID": sid, "info": {"id": sid, "title": title, "directory": request.query.get("directory") or "", "time": {"created": 0, "updated": now_ms()}}})
    return web.json_response(True)


async def remove(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    sid = request.match_info["sid"]
    if sid in bridge.runs or sid in bridge.live_sessions():
        return json_error("the session is running", 409)
    await asyncio.to_thread(delete_session, sid, request.query.get("directory") or None)
    bridge.bus.emit("session.deleted", {"sessionID": sid, "info": {"id": sid, "title": "", "directory": request.query.get("directory") or "", "time": {"created": 0, "updated": now_ms()}}})
    return web.json_response(True)


async def fork(request: web.Request) -> web.Response:
    sid = request.match_info["sid"]
    directory = request.query.get("directory") or None
    result = await asyncio.to_thread(fork_session, sid, directory)
    stamp = now_ms()
    return web.json_response({"id": result.session_id, "title": "", "directory": directory or "", "parentID": None, "time": {"created": stamp, "updated": stamp}})


async def permissions(request: web.Request) -> web.Response:
    return web.json_response(bridge_of(request).pending("permission"))


async def questions(request: web.Request) -> web.Response:
    return web.json_response(bridge_of(request).pending("question"))


async def reply_permission(request: web.Request) -> web.Response:
    body = await request.json()
    response = (body or {}).get("response") if isinstance(body, dict) else None
    if response not in ("once", "always", "reject"):
        return json_error("response must be once, always or reject", 400)
    return web.json_response(bridge_of(request).reply(request.match_info["pid"], response))


async def reply_question(request: web.Request) -> web.Response:
    body = await request.json()
    answers = (body or {}).get("answers") if isinstance(body, dict) else None
    if not isinstance(answers, list):
        return json_error("answers required", 400)
    clean = [[str(x) for x in one] if isinstance(one, list) else [str(one)] for one in answers]
    return web.json_response(bridge_of(request).reply(request.match_info["qid"], clean))


async def reject_question(request: web.Request) -> web.Response:
    return web.json_response(bridge_of(request).reply(request.match_info["qid"], None))


async def screens(request: web.Request) -> web.Response:
    return web.json_response(list(bridge_of(request).screens.values()))


async def press_screen(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    sid = request.match_info["sid"]
    body = await request.json()
    body = body if isinstance(body, dict) else {}
    key = str(body.get("key") or "")
    said = body.get("text") if isinstance(body.get("text"), str) else None
    live = bridge.live_sessions().get(sid)
    if live is None:
        return json_error("that session is no longer open on the desktop", 409)
    current = await bridge.sync_screen(sid, live, patient=False)
    if current is None:
        return json_error("nothing is waiting for an answer there any more", 409)
    if current["id"] != body.get("id"):
        return json_error("the prompt changed on the desktop; here is the new one", 409)
    if key.isdigit():
        if not any(option["key"] == key for option in current["options"]):
            return json_error("that option is gone", 409)
    elif key not in SCREEN_KEYS:
        return json_error("unknown key", 400)
    steps = screen_keys(current, key, said)
    if steps is None:
        return json_error("the desktop's cursor is not on that question's choices; answer it there", 409)
    try:
        pane = await asyncio.to_thread(pane_of, int(live["pid"]))
        if pane is None:
            return json_error("that session runs outside tmux; answer it there", 409)
        await asyncio.to_thread(press_into, pane, steps)
    except (RuntimeError, OSError, subprocess.SubprocessError, ValueError) as err:
        return json_error(f"could not reach the desktop terminal: {str(err)[:120]}", 503)
    await asyncio.sleep(0.7)
    after = await bridge.sync_screen(sid, bridge.live_sessions().get(sid), patient=False)
    return web.json_response({"screen": after})


async def events(request: web.Request) -> web.StreamResponse:
    bridge = bridge_of(request)
    response = web.StreamResponse(headers={"Content-Type": "text/event-stream", "Cache-Control": "no-store", "X-Accel-Buffering": "no"})
    await response.prepare(request)
    queue = bridge.bus.subscribe()
    try:
        await response.write(("data: " + json.dumps({"type": "server.connected", "properties": {}}) + "\n\n").encode("utf-8"))
        while True:
            try:
                event = await asyncio.wait_for(queue.get(), 15)
            except asyncio.TimeoutError:
                await response.write(b": keepalive\n\n")
                continue
            await response.write(("data: " + json.dumps(event) + "\n\n").encode("utf-8"))
    except (ConnectionResetError, asyncio.QueueShutDown, RuntimeError):
        pass
    finally:
        bridge.bus.unsubscribe(queue)
    return response


def tmux(*args: str, stdin: str | None = None) -> str:
    done = subprocess.run([TMUX, "-S", str(TMUX_SOCKET), *args], input=stdin, capture_output=True, text=True, timeout=5)
    if done.returncode != 0:
        raise RuntimeError(done.stderr.strip() or f"tmux {args[0]} failed")
    return done.stdout


def parent_of(pid: int) -> int:
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
        return int(stat[stat.rindex(")") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def tmux_panes() -> dict[int, str]:
    panes: dict[int, str] = {}
    for line in tmux("list-panes", "-a", "-F", "#{pane_id} #{pane_pid}").splitlines():
        pane, _, owner = line.partition(" ")
        if owner.isdigit():
            panes[int(owner)] = pane
    return panes


def pane_of(pid: int) -> str | None:
    return pane_among(tmux_panes(), pid)


def pane_among(panes: dict[int, str], pid: int) -> str | None:
    for _ in range(32):
        if pid in panes:
            return panes[pid]
        pid = parent_of(pid)
        if pid <= 1:
            return None
    return None


def session_cwd(sid: str) -> str | None:
    path = next(TRANSCRIPTS.glob(f"*/{sid}.jsonl"), None)
    if path is None:
        return None
    try:
        with path.open(encoding="utf-8") as lines:
            for line in lines:
                try:
                    cwd = json.loads(line).get("cwd")
                except (ValueError, AttributeError):
                    continue
                if cwd and Path(cwd).is_dir():
                    return cwd
    except OSError:
        return None
    return str(HOME)


def desk_command(sid: str, program: str, model: str | None, choice: dict, fresh: bool) -> list[str]:
    command = [program, "--session-id" if fresh else "--resume", sid, "--permission-mode", DESK_MODES.get(choice["mode"], choice["mode"])]
    if model:
        command += ["--model", model]
    if choice["effort"]:
        command += ["--effort", choice["effort"]]
    return command


def desk_session() -> str | None:
    for listing, fmt in (("list-clients", "#{client_activity} #{session_name}"), ("list-sessions", "#{session_activity} #{session_name}")):
        try:
            out = tmux(listing, "-F", fmt)
        except RuntimeError:
            return None
        rows = [line.split(" ", 1) for line in out.splitlines() if " " in line]
        if rows:
            return max(rows, key=lambda row: int(row[0]) if row[0].isdigit() else 0)[1]
    return None


def open_window(directory: str, command: list[str]) -> tuple[str, str]:
    session = desk_session()
    if session is not None:
        out = tmux("new-window", "-d", "-t", f"{session}:", "-c", directory, "-P", "-F", DESK_WINDOW, *command)
    else:
        started = subprocess.run(
            ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app.slice",
             TMUX, "-S", str(TMUX_SOCKET), "new-session", "-d", "-s", DESK_FALLBACK_SESSION, "-c", directory, "-P", "-F", DESK_WINDOW, *command],
            capture_output=True, text=True, timeout=10,
        )
        if started.returncode != 0:
            raise RuntimeError(started.stderr.strip() or "tmux new-session failed")
        out = started.stdout
    place, _, pane = out.strip().splitlines()[-1].partition(" ")
    return place, pane


def desk_ready(pane: str) -> bool:
    lines = pane_lines(pane)
    rules = [at for at, line in enumerate(lines) if SCREEN_RULE.match(line)]
    return len(rules) >= 2 and lines[rules[-2] + 1].lstrip().startswith("❯")


def started_at(pid: int) -> str | None:
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
        return stat[stat.rindex(")") + 2:].split()[19]
    except (OSError, ValueError, IndexError):
        return None


def end_process(pid: int, started: str | None) -> None:
    now = started_at(pid)
    if now is None:
        return
    if started is not None and str(started) != now:
        raise RuntimeError(f"process {pid} is no longer that session")
    os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + CLOSE_SECONDS
    while time.monotonic() < deadline:
        time.sleep(0.2)
        if started_at(pid) != now:
            return
    os.kill(pid, signal.SIGKILL)


def type_into(pane: str, text: str) -> None:
    tmux("load-buffer", "-b", "phone-bridge", "-", stdin=text)
    tmux("paste-buffer", "-p", "-d", "-b", "phone-bridge", "-t", pane)
    time.sleep(0.2)
    tmux("send-keys", "-t", pane, "Enter")


def last_prompt(sid: str) -> str | None:
    path = next(TRANSCRIPTS.glob(f"*/{sid}.jsonl"), None)
    if path is None:
        return None
    for entry in reversed(transcript_entries(sid, path, 4)):
        if entry["info"]["role"] == "user":
            return "\n".join(part.get("text", "") for part in entry["parts"])
    return None


def holds(pane: str, said: str) -> bool:
    screen = tmux("capture-pane", "-p", "-J", "-t", pane).splitlines()
    rules = [at for at, line in enumerate(screen) if SCREEN_RULE.match(line)]
    if len(rules) < 2:
        return False
    box = " ".join(line.strip().removeprefix("❯").strip() for line in screen[rules[-2] + 1:rules[-1]])
    head = " ".join(said.split())[:30]
    return bool(head) and " ".join(box.split()).startswith(head)


def stop_pane(pane: str, said: str | None) -> None:
    tmux("send-keys", "-t", pane, "Escape")
    if not said:
        return
    for _ in range(6):
        time.sleep(0.25)
        if holds(pane, said):
            tmux("send-keys", "-t", pane, "C-c")
            return


def pane_lines(pane: str) -> list[str]:
    return tmux("capture-pane", "-p", "-J", "-t", pane).splitlines()


def desk_mode(lines: list[str]) -> str | None:
    for line in reversed(lines[-8:]):
        for words, mode in SCREEN_MODES:
            if words in line:
                return mode
    return None


def desk_background(lines: list[str]) -> list[str] | None:
    for line in reversed(lines[-8:]):
        if any(words in line for words, _ in SCREEN_MODES):
            return [piece for piece in SCREEN_PIECES.split(line.strip()) if SCREEN_BACKGROUND.match(piece)]
    return None


def desk_backgrounds(live: dict[str, dict]) -> dict[str, list[str] | None]:
    try:
        panes = tmux_panes()
    except (RuntimeError, OSError, subprocess.SubprocessError):
        return {}
    found: dict[str, list[str] | None] = {}
    for sid, info in live.items():
        try:
            pane = pane_among(panes, int(info["pid"]))
            found[sid] = desk_background(pane_lines(pane)) if pane else []
        except (RuntimeError, OSError, subprocess.SubprocessError, ValueError):
            found[sid] = None
    return found


def desk_view(lines: list[str]) -> dict:
    edges = [at for at, line in enumerate(lines) if SCREEN_EDGE.match(line)]
    below = lines[edges[-1] + 1:] if edges else []
    seen = next((found.group(1) for line in below if (found := SCREEN_MODEL.search(line))), None)
    near = lines[max(edges[-2] - 1, 0):edges[-2] + 1] if len(edges) >= 2 else []
    effort = next((found.group(1) for line in near if (found := SCREEN_EFFORT.search(line))), None)
    model = seen if seen is None or seen.startswith("deepseek") else seen.lower()
    return {"mode": desk_mode(lines), "effort": effort, "model": model}


def picker_open(lines: list[str]) -> bool:
    return any(SCREEN_PICKER in line for line in lines[-40:])


def picker_options(lines: list[str]) -> list[tuple[bool, str]]:
    start = max((at for at, line in enumerate(lines) if SCREEN_PICKER in line), default=0)
    options = []
    for line in lines[start:]:
        found = SCREEN_OPTION.match(line)
        if found:
            options.append((line.lstrip().startswith("❯"), found.group(3).split("  ")[0].replace("✔", "").strip()))
    return options


def picker_means(provider: str, model: str, label: str) -> bool:
    if model == "default":
        return label.startswith("Default")
    if provider == "claude":
        return label.lower().startswith(model)
    return label == model


def picked_effort(lines: list[str]) -> tuple[str, bool] | None:
    for line in reversed(lines):
        found = SCREEN_PICKED_EFFORT.search(line)
        if found:
            return found.group(1).lower(), bool(found.group(2))
    return None


def settle(pane: str, ready, tries: int = 12) -> list[str] | None:
    for _ in range(tries):
        time.sleep(0.2)
        lines = pane_lines(pane)
        if ready(lines):
            return lines
    return None


def cycle_mode(pane: str, mode: str) -> None:
    for _ in range(len(MODES) + 1):
        now = desk_mode(pane_lines(pane))
        if now is None:
            raise RuntimeError("the terminal shows no mode line; is a dialog open there?")
        if now == mode:
            return
        tmux("send-keys", "-t", pane, "BTab")
        time.sleep(0.4)
    raise RuntimeError(f"the terminal did not reach {mode} mode")


def walk_effort(pane: str, effort: str | None) -> None:
    heading = "Left"
    for _ in range(len(EFFORTS) * 2 + 2):
        found = picked_effort(pane_lines(pane))
        if found is None:
            raise RuntimeError("that model has no effort setting")
        level, default = found
        if (default if effort is None else level == effort):
            return
        if effort is not None:
            if level not in EFFORTS:
                raise RuntimeError(f"the terminal shows an unknown effort {level}")
            heading = "Right" if EFFORTS.index(effort) > EFFORTS.index(level) else "Left"
        tmux("send-keys", "-t", pane, heading)
        time.sleep(0.25)
        after = picked_effort(pane_lines(pane))
        if after is not None and after[0] == level:
            if effort is not None or heading == "Right":
                raise RuntimeError(f"that model does not offer {effort or 'a default'} effort")
            heading = "Right"
    raise RuntimeError("the terminal did not reach that effort")


def pick_on_desk(pane: str, provider: str, model: str | None, effort: str | None, effort_given: bool) -> None:
    if desk_mode(pane_lines(pane)) is None:
        raise RuntimeError("the terminal has a dialog open; answer it first")
    tmux("send-keys", "-t", pane, "M-p")
    lines = settle(pane, picker_open)
    if lines is None:
        raise RuntimeError("the model picker did not open in that terminal")
    try:
        if model is not None:
            options = picker_options(lines)
            target = next((at for at, (_, label) in enumerate(options) if picker_means(provider, model, label)), None)
            cursor = next((at for at, (on, _) in enumerate(options) if on), None)
            if target is None or cursor is None:
                raise RuntimeError(f"that terminal does not offer {model}")
            for _ in range(abs(target - cursor)):
                tmux("send-keys", "-t", pane, "Down" if target > cursor else "Up")
                time.sleep(0.1)
            landed = settle(pane, lambda now: any(on and picker_means(provider, model, label) for on, label in picker_options(now)), 6)
            if landed is None:
                raise RuntimeError(f"could not reach {model} in the model picker")
        if effort_given:
            walk_effort(pane, effort)
        tmux("send-keys", "-t", pane, "s")
    except Exception:
        if picker_open(pane_lines(pane)):
            tmux("send-keys", "-t", pane, "Escape")
        raise
    if settle(pane, lambda now: not picker_open(now)) is None:
        raise RuntimeError("the model picker did not close")


def tune_desk(pane: str, provider: str, changes: dict) -> None:
    if "mode" in changes:
        cycle_mode(pane, changes["mode"])
    if "model" in changes or "effort" in changes:
        pick_on_desk(pane, provider, changes.get("model"), changes.get("effort"), "effort" in changes)


def press_into(pane: str, steps: list[tuple[str, str]]) -> None:
    for n, (kind, value) in enumerate(steps):
        if n:
            time.sleep(SCREEN_STEP_SECONDS)
        if kind == "text":
            tmux("send-keys", "-t", pane, "-l", "--", value)
        else:
            tmux("send-keys", "-t", pane, value)


def parse_screen(screen: str) -> dict | None:
    lines = [line.rstrip() for line in screen.splitlines()]
    hits = [(i, match) for i, line in enumerate(lines) if (match := SCREEN_OPTION.match(line))]
    first = next((k for k in range(len(hits) - 1, -1, -1) if hits[k][1].group(2) == "1"), None)
    if first is None:
        return None
    chosen = [hits[first]]
    for hit in hits[first + 1:]:
        if int(hit[1].group(2)) != int(chosen[-1][1].group(2)) + 1:
            break
        chosen.append(hit)
    if len(chosen) < 2:
        return None
    options = []
    below = False
    for n, (i, match) in enumerate(chosen):
        end = chosen[n + 1][0] if n + 1 < len(chosen) else len(lines)
        column = match.start(2)
        detail = []
        for line in lines[i + 1:end]:
            stripped = line.strip()
            submit = SCREEN_SUBMIT.match(line)
            if submit:
                below = below or submit.group(1) is not None
                continue
            if not stripped or SCREEN_RULE.match(line) or SCREEN_DASH.match(line):
                continue
            if SCREEN_FOOTER.search(line) or len(line) - len(line.lstrip()) <= column:
                break
            detail.append(stripped)
        raw = match.group(3)
        box = SCREEN_BOX.match(raw)
        label = box.group(2) if box else raw
        options.append({
            "key": match.group(2),
            "label": SCREEN_PICKED.sub("", label),
            "detail": " ".join(detail),
            "text": bool(SCREEN_TEXT.search(raw)),
            "value": "",
            "current": "❯" in lines[i][:column],
            "checked": (box.group(1) != " ") if box else None,
            "picked": bool(SCREEN_PICKED.search(label)),
            "aside": bool(SCREEN_ASIDE.match(raw)),
        })
    top = chosen[0][0]
    start = next((k + 1 for k in range(top - 1, -1, -1) if SCREEN_RULE.match(lines[k])), 0)
    region = lines[start:top]
    bar = next((line for line in region if SCREEN_TABS.match(line)), None)
    last_dash = max((k for k, line in enumerate(region) if SCREEN_DASH.match(line)), default=-1)
    kept = [line for line in region if not SCREEN_DASH.match(line)]
    question = [line for line in region[last_dash + 1:] if line.strip() and not SCREEN_TABS.match(line)]
    body = textwrap.dedent("\n".join(kept[-60:])).strip()
    body = re.sub(r"\n{3,}", "\n\n", body)
    prose = ["" if SCREEN_DASH.match(line) else line for line in region[-60:] if not SCREEN_TABS.match(line)]
    title, context = screen_title(textwrap.dedent("\n".join(prose)).strip())
    review = title == SCREEN_REVIEW
    if bar is not None and not review:
        own_answer(options)
    return {
        "body": body,
        "question": textwrap.dedent("\n".join(question)).strip(),
        "title": title,
        "context": context,
        "options": options,
        "tabs": bar is not None,
        "steps": screen_steps(bar) if bar else [],
        "review": review,
        "multiple": any(option["checked"] is not None for option in options),
        "below": below,
    }


def own_answer(options: list[dict]) -> None:
    listed = [option for option in options if not option["aside"]]
    if not listed or listed[-1]["detail"]:
        return
    last = listed[-1]
    last["text"] = True
    if not SCREEN_TEXT.search(last["label"]):
        last["value"] = last["label"]


def cursor_row(screen: dict, listed: list[dict]) -> int | None:
    found = next((n for n, option in enumerate(listed) if option.get("current")), None)
    if found is not None:
        return found
    rows = len(listed) + (1 if screen.get("multiple") else 0)
    if screen.get("below"):
        return len(listed)
    asides = [option for option in screen.get("options") or [] if option.get("aside")]
    return next((rows + n for n, option in enumerate(asides) if option.get("current")), None)


def screen_keys(screen: dict, key: str, said: str | None) -> list[tuple[str, str]] | None:
    if key == "escape":
        return [("key", SCREEN_KEYS[key])]
    words = " ".join((said or "").split())
    if not screen.get("tabs"):
        if not key.isdigit():
            return [("key", SCREEN_KEYS[key])]
        return [("key", key)] + ([("text", words), ("key", "Enter")] if words else [])
    options = screen.get("options") or []
    listed = [option for option in options if not option.get("aside")]
    multiple = bool(screen.get("multiple"))
    steps: list[tuple[str, str]] = []
    at = cursor_row(screen, listed)
    while at is not None and at > 0 and (at >= len(listed) or listed[at].get("text")):
        steps.append(("key", "Up"))
        at -= 1
    if not key.isdigit():
        return steps + [("key", SCREEN_KEYS[key])]
    target = next((n for n, option in enumerate(listed) if option["key"] == key), None)
    option = listed[target] if target is not None else next((o for o in options if o["key"] == key), None)
    if said is None or option is None or not option.get("text"):
        return steps + [("key", key)]
    if target is not None and at is not None:
        steps += [("key", "Down" if target > at else "Up")] * abs(target - at)
    elif not multiple and not option.get("value"):
        steps.append(("key", key))
    else:
        return None
    if option.get("value"):
        steps += [("key", "C-e"), ("key", "C-u")]
    if words:
        steps.append(("text", words))
    if multiple:
        steps.append(("key", "Up"))
    elif words:
        steps.append(("key", "Enter"))
    return steps


def screen_title(prose: str) -> tuple[str, str]:
    if prose.startswith(SCREEN_REVIEW):
        return SCREEN_REVIEW, textwrap.dedent(prose[len(SCREEN_REVIEW):].strip("\n")).strip()
    paragraphs = [p for p in re.split(r"\n\s*\n", prose) if p.strip()]
    return (paragraphs[-1].strip(), "\n\n".join(paragraphs[:-1])) if paragraphs else ("", "")


def screen_steps(bar: str) -> list[dict]:
    inner = bar.strip().removeprefix("←").removesuffix("→").strip()
    found = (SCREEN_TAB.match(token.strip()) for token in re.split(r"\s{2,}", inner))
    return [{"label": match.group(2), "done": match.group(1) == "☒"} for match in found if match]


def screen_step(parsed: dict, pending: list[dict]) -> int:
    if not parsed["steps"]:
        return -1
    shown = " ".join(parsed["title"].split())
    if shown.startswith(SCREEN_REVIEW):
        return len(parsed["steps"]) - 1
    asked = next((tool["input"].get("questions") for tool in pending if tool["name"] == "AskUserQuestion"), None)
    texts = [" ".join(str(q.get("question", "")).split()) for q in asked or [] if isinstance(q, dict)]
    return texts.index(shown) if shown in texts else -1


def plan_text(data: dict) -> str | None:
    path = data.get("planFilePath")
    if isinstance(path, str):
        target = Path(path).expanduser()
        try:
            if target.suffix == ".md" and target.resolve().parent == PLANS.resolve():
                return target.read_text(encoding="utf-8")
        except OSError:
            pass
    plan = data.get("plan")
    return plan if isinstance(plan, str) else None


def pending_tools(sid: str) -> list[dict]:
    path = next(TRANSCRIPTS.glob(f"*/{sid}.jsonl"), None)
    if path is None:
        return []
    with path.open("rb") as handle:
        size = handle.seek(0, 2)
        handle.seek(max(0, size - SCREEN_TAIL_BYTES))
        data = handle.read()
    answered: set[str] = set()
    pending = []
    for raw in reversed(data.split(b"\n")):
        try:
            record = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(record, dict) or record.get("isSidechain") or record.get("type") not in ("user", "assistant"):
            continue
        content = (record.get("message") or {}).get("content")
        if record["type"] == "user" and not (isinstance(content, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content)):
            break
        for block in content if isinstance(content, list) else []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_result":
                answered.add(block.get("tool_use_id"))
            elif block.get("type") == "tool_use" and block.get("id") not in answered:
                pending.append({"name": block.get("name"), "input": block.get("input") or {}})
    return pending


def screen_id(sid: str, parsed: dict) -> str:
    seed = json.dumps([sid, parsed["body"], [(o["key"], o["label"], o["current"], o.get("checked")) for o in parsed["options"]]], ensure_ascii=False)
    return "scr_" + sha1(seed.encode("utf-8")).hexdigest()[:16]


def screen_payload(sid: str, live: dict, previous: dict | None) -> dict | None:
    pane = pane_of(int(live["pid"]))
    if pane is None:
        return None
    screen = tmux("capture-pane", "-p", "-J", "-t", pane)
    parsed = parse_screen(screen)
    if parsed is None:
        tail = [line.rstrip() for line in screen.splitlines() if line.strip()][-25:]
        parsed = {"body": textwrap.dedent("\n".join(tail)).strip(), "question": "", "title": "", "context": "", "options": [], "tabs": False, "steps": []}
    ask_id = screen_id(sid, parsed)
    if previous is not None and previous["id"] == ask_id:
        return previous
    pending = pending_tools(sid)
    plan = next((text for tool in pending if tool["name"] == "ExitPlanMode" and (text := plan_text(tool["input"]))), None)
    return {
        "id": ask_id,
        "sessionID": sid,
        "waiting": live.get("waiting") or "an answer",
        "body": parsed["question"] if plan else parsed["body"],
        "plan": plan,
        "title": parsed["title"],
        "context": "" if plan else parsed["context"],
        "options": parsed["options"],
        "tabs": parsed["tabs"],
        "steps": parsed["steps"],
        "step": screen_step(parsed, pending),
        "review": parsed.get("review", False),
        "multiple": parsed.get("multiple", False),
        "below": parsed.get("below", False),
    }


def find_rows(query: str) -> list[tuple[str, str]]:
    now = time.time()
    if now - finder_state["indexed"] > FIND_REINDEX_SECONDS:
        subprocess.run([FINDER, "index", "--quiet"], capture_output=True, timeout=180)
        finder_state["indexed"] = now
    done = subprocess.run([FINDER, "query", *query.split()], capture_output=True, text=True, timeout=60)
    rows = []
    for line in done.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) >= 5:
            rows.append((parts[0], parts[4]))
    return rows


def hot_transcripts(now: float) -> dict[str, Path]:
    found: dict[str, Path] = {}
    for path in TRANSCRIPTS.glob("*/*.jsonl"):
        try:
            if now - path.stat().st_mtime < HOT_SECONDS:
                found[path.stem] = path
        except OSError:
            continue
    return found


def live_status(live: dict) -> dict:
    status = live.get("status")
    return {"type": "busy", "message": status} if status in ("busy", "waiting") else {"type": "idle"}


async def watch_outside(bridge) -> None:
    paths: dict[str, Path] = {}
    seen: dict[str, tuple[float, int]] = {}
    statuses: dict[str, str] = {}
    scanned = 0.0
    looked = 0.0
    while True:
        try:
            now = time.time()
            if now - scanned > RESCAN_SECONDS:
                paths = await asyncio.to_thread(hot_transcripts, now)
                scanned = now
            live = bridge.live_sessions()
            if now - looked > BACKGROUND_SECONDS:
                await bridge.sync_background(live)
                looked = now
            for sid, info in live.items():
                state = live_status(info)
                mark = f"{state['type']}:{state.get('message') or ''}"
                if statuses.get(sid) != mark:
                    statuses[sid] = mark
                    bridge.bus.emit("session.status", {"sessionID": sid, "status": state})
                if info.get("status") == "waiting" or sid in bridge.screens:
                    await bridge.sync_screen(sid, info)
            for sid in [s for s in statuses if s not in live]:
                if statuses.pop(sid) != "idle:":
                    bridge.bus.emit("session.status", {"sessionID": sid, "status": {"type": "idle"}})
            for sid in [s for s in bridge.screens if s not in live]:
                await bridge.sync_screen(sid, None)
            for sid, path in paths.items():
                try:
                    stat = path.stat()
                except OSError:
                    continue
                key = (stat.st_mtime, stat.st_size)
                before = seen.get(sid)
                seen[sid] = key
                if before is not None and before != key and sid not in bridge.runs:
                    bridge.bus.emit("transcript.changed", {"sessionID": sid, "updated": int(stat.st_mtime * 1000)})
        except Exception as err:
            print(f"claude-bridge: watcher: {err}", flush=True)
        await asyncio.sleep(WATCH_SECONDS)


async def start_watcher(app: web.Application) -> None:
    app["watcher"] = asyncio.create_task(watch_outside(app[BRIDGE]))


async def stop_watcher(app: web.Application) -> None:
    app["watcher"].cancel()


async def close_streams(app: web.Application) -> None:
    bridge = app[BRIDGE]
    if isinstance(bridge, Bridge):
        bridge.bus.close()


def make_app() -> web.Application:
    app = web.Application(middlewares=[auth_middleware], client_max_size=32 * 1024 * 1024)
    app[PASSWORD] = load_password()
    app[BRIDGE] = Bridge()
    app.on_startup.append(start_watcher)
    app.on_shutdown.append(close_streams)
    app.on_cleanup.append(stop_watcher)
    if app[PASSWORD] is None:
        print("claude-bridge: no password file could be written; the server is unsecured", flush=True)
    app.router.add_get("/global/health", health)
    app.router.add_get("/provider", providers)
    app.router.add_get("/config", config)
    app.router.add_get("/project", projects)
    app.router.add_get("/session", sessions)
    app.router.add_get("/find", find)
    app.router.add_get("/command", commands)
    app.router.add_post("/upload", upload)
    app.router.add_post("/session", create_session)
    app.router.add_get("/session/status", session_status)
    app.router.add_get("/session/{sid}/message", messages)
    app.router.add_post("/session/{sid}/prompt_async", prompt)
    app.router.add_post("/session/{sid}/abort", abort)
    app.router.add_post("/session/{sid}/close", close_session)
    app.router.add_get("/session/{sid}/settings", get_settings)
    app.router.add_post("/session/{sid}/settings", set_settings)
    app.router.add_patch("/session/{sid}", rename)
    app.router.add_delete("/session/{sid}", remove)
    app.router.add_post("/session/{sid}/fork", fork)
    app.router.add_post("/session/{sid}/permissions/{pid}", reply_permission)
    app.router.add_get("/permission", permissions)
    app.router.add_get("/question", questions)
    app.router.add_post("/question/{qid}/reply", reply_question)
    app.router.add_post("/question/{qid}/reject", reject_question)
    app.router.add_get("/screen", screens)
    app.router.add_post("/session/{sid}/screen", press_screen)
    app.router.add_get("/event", events)
    return app


if __name__ == "__main__":
    web.run_app(make_app(), host=HOST, port=PORT, print=lambda line: print(line, flush=True))
