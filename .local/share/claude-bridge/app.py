from __future__ import annotations

import asyncio
import base64
import json
import os
import secrets
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from aiohttp import web
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
    get_session_messages,
    list_sessions,
    rename_session,
)

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
WATCH_SECONDS = 1.0
HOT_SECONDS = 900
RESCAN_SECONDS = 15
PROJECTS_TTL = 10
VERSION = "claude-bridge/1"
DEEPSEEK_BASE_URL = "https://api.deepseek.com/anthropic"
PROVIDERS = {
    "claude": {"name": "Claude Code", "default": "default", "models": ["default"]},
    "deepseek": {"name": "DeepSeek via Claude Code", "default": "deepseek-v4-pro", "models": ["deepseek-v4-pro", "deepseek-v4-flash"]},
}
INPUT_KEYS = ("command", "description", "file_path", "pattern", "path", "url", "query")
SETTING_SOURCES = ["user", "project", "local"]

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


def provider_of(model: str | None) -> str:
    return "deepseek" if model and model.startswith("deepseek") else "claude"


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
            if text and not text.startswith("<"):
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
        self.projects_cache: tuple[float, list[dict]] = (0.0, [])

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
            found[sid] = {"name": data.get("name"), "status": data.get("status"), "cwd": data.get("cwd"), "tmux": data.get("tmux")}
        return found

    async def projects(self) -> list[dict]:
        stamp, cached = self.projects_cache
        if time.time() - stamp < PROJECTS_TTL:
            return cached
        infos = await asyncio.to_thread(list_sessions, None, 400)
        grouped: dict[str, dict] = {}
        for info in infos:
            cwd = info.cwd
            if not cwd or not Path(cwd).is_dir():
                continue
            updated = to_ms(info.last_modified)
            project = grouped.get(cwd)
            if project is None:
                grouped[cwd] = {"id": cwd, "worktree": cwd, "name": Path(cwd).name or cwd, "time": {"created": updated, "updated": updated}, "sandboxes": []}
            elif updated > project["time"]["updated"]:
                project["time"]["updated"] = updated
        for live in self.live_sessions().values():
            cwd = live.get("cwd")
            if cwd and cwd not in grouped and Path(cwd).is_dir():
                grouped[cwd] = {"id": cwd, "worktree": cwd, "name": Path(cwd).name or cwd, "time": {"created": now_ms(), "updated": now_ms()}, "sandboxes": []}
        result = sorted(grouped.values(), key=lambda p: p["time"]["updated"], reverse=True)
        self.projects_cache = (time.time(), result)
        return result

    def session_dict(self, info, live: dict | None) -> dict:
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
            session["live"] = {"name": live.get("name"), "status": live.get("status"), "tmux": live.get("tmux")}
        return session

    async def sessions(self, directory: str | None, limit: int) -> list[dict]:
        infos = await asyncio.to_thread(list_sessions, directory, limit)
        live = self.live_sessions()
        return [self.session_dict(info, live.get(info.session_id)) for info in infos]

    def statuses(self) -> dict[str, dict]:
        result = {sid: {"type": "busy"} for sid, run in self.runs.items() if run.busy}
        for sid, live in self.live_sessions().items():
            if live.get("status") in ("busy", "waiting"):
                result[sid] = {"type": "busy", "message": live.get("status")}
        return result

    def env_for(self, provider: str) -> dict[str, str]:
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

    def model_arg(self, provider: str, model: str) -> str | None:
        if provider == "claude":
            return None if model in ("", "default") else model
        return model or PROVIDERS[provider]["default"]

    async def ensure_run(self, sid: str, directory: str, provider: str, model: str) -> Run:
        run = self.runs.get(sid)
        if run is not None and run.provider == provider:
            if run.model != model and run.client is not None:
                await run.client.set_model(self.model_arg(provider, model))
                run.model = model
            return run
        if run is not None:
            await self.stop_run(run)
        fresh = sid in self.fresh
        run = Run(sid=sid, directory=directory, provider=provider, model=model)
        options = ClaudeAgentOptions(
            cwd=directory,
            env=self.env_for(provider),
            model=self.model_arg(provider, model),
            can_use_tool=self.permission_handler(sid),
            include_partial_messages=True,
            permission_mode="default",
            setting_sources=SETTING_SOURCES,
            cli_path=CLI_PATH,
            **({"session_id": sid} if fresh else {"resume": sid}),
        )
        run.client = ClaudeSDKClient(options)
        await run.client.connect()
        self.fresh.pop(sid, None)
        self.runs[sid] = run
        run.reader = asyncio.create_task(self.read(run))
        return run

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
        self.asks[ask.payload["id"]] = ask
        try:
            return await ask.future
        finally:
            self.asks.pop(ask.payload["id"], None)

    async def ask_permission(self, sid: str, tool: str, data: dict, context):
        run = self.runs.get(sid)
        suggestions = list(getattr(context, "suggestions", None) or [])
        payload = {
            "id": "per_" + uuid.uuid4().hex[:16],
            "sessionID": sid,
            "permission": tool,
            "patterns": [getattr(context, "title", None) or summarize(tool, data)],
            "always": [json.dumps(s)[:120] for s in suggestions],
            "metadata": {k: v for k, v in data.items() if k in INPUT_KEYS and isinstance(v, str)} | ({"description": context.description} if getattr(context, "description", None) else {}),
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
        for question, picked in zip(questions, answers):
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
    bridge.fresh[sid] = {"directory": directory, "provider": provider, "model": model.get("id") or PROVIDERS[provider]["default"]}
    stamp = now_ms()
    return web.json_response({"id": sid, "title": body.get("title") or "", "directory": directory, "parentID": None, "time": {"created": stamp, "updated": stamp}})


async def messages(request: web.Request) -> web.Response:
    bridge = bridge_of(request)
    sid = request.match_info["sid"]
    directory = request.query.get("directory") or None
    limit = int(request.query.get("limit") or 80)
    try:
        records = await asyncio.to_thread(get_session_messages, sid, directory)
    except Exception:
        records = []
    entries = convert_records(sid, records)
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
        return json_error(f"running on the desktop as {live.get('name') or 'an open session'}; resuming here would start a copy", 409)
    fresh = bridge.fresh.get(sid)
    run = bridge.runs.get(sid)
    directory = request.query.get("directory") or (fresh or {}).get("directory") or (run.directory if run else None) or str(HOME)
    model = body.get("model") if isinstance(body.get("model"), dict) else {}
    provider = model.get("providerID") or (fresh or {}).get("provider") or (run.provider if run else "claude")
    if provider not in PROVIDERS:
        return json_error(f"unknown provider {provider}", 400)
    chosen = model.get("modelID") or (fresh or {}).get("model") or (run.model if run and run.provider == provider else PROVIDERS[provider]["default"])
    try:
        run = await bridge.ensure_run(sid, directory, provider, chosen)
    except Exception as err:
        return json_error(f"could not start claude: {str(err)[:200]}", 503)
    if run.idle_handle:
        run.idle_handle.cancel()
    user_id = "usr_" + uuid.uuid4().hex[:16]
    bridge.bus.emit("message.updated", {"sessionID": sid, "info": entry_for(user_id, sid, "user", created=now_ms())["info"]})
    bridge.bus.emit("message.part.updated", {"sessionID": sid, "part": text_part(f"{user_id}:0", user_id, sid, "text", text), "time": now_ms()})
    bridge.set_busy(run, True)
    await run.client.query(text)
    return web.Response(status=204)


async def abort(request: web.Request) -> web.Response:
    run = bridge_of(request).runs.get(request.match_info["sid"])
    if run is None or run.client is None:
        return web.json_response(False)
    await run.client.interrupt()
    return web.json_response(True)


async def rename(request: web.Request) -> web.Response:
    sid = request.match_info["sid"]
    body = await request.json()
    title = (body or {}).get("title") if isinstance(body, dict) else None
    if not title:
        return json_error("title required", 400)
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
    except (ConnectionResetError, asyncio.CancelledError, RuntimeError):
        pass
    finally:
        bridge.bus.unsubscribe(queue)
    return response


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
    while True:
        try:
            now = time.time()
            if now - scanned > RESCAN_SECONDS:
                paths = await asyncio.to_thread(hot_transcripts, now)
                scanned = now
            live = bridge.live_sessions()
            for sid, info in live.items():
                state = live_status(info)
                if statuses.get(sid) != state["type"]:
                    statuses[sid] = state["type"]
                    bridge.bus.emit("session.status", {"sessionID": sid, "status": state})
            for sid in [s for s in statuses if s not in live]:
                if statuses.pop(sid) != "idle":
                    bridge.bus.emit("session.status", {"sessionID": sid, "status": {"type": "idle"}})
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


def make_app() -> web.Application:
    app = web.Application(middlewares=[auth_middleware])
    app[PASSWORD] = load_password()
    app[BRIDGE] = Bridge()
    app.on_startup.append(start_watcher)
    app.on_cleanup.append(stop_watcher)
    if app[PASSWORD] is None:
        print("claude-bridge: no password file could be written; the server is unsecured", flush=True)
    app.router.add_get("/global/health", health)
    app.router.add_get("/provider", providers)
    app.router.add_get("/config", config)
    app.router.add_get("/project", projects)
    app.router.add_get("/session", sessions)
    app.router.add_post("/session", create_session)
    app.router.add_get("/session/status", session_status)
    app.router.add_get("/session/{sid}/message", messages)
    app.router.add_post("/session/{sid}/prompt_async", prompt)
    app.router.add_post("/session/{sid}/abort", abort)
    app.router.add_patch("/session/{sid}", rename)
    app.router.add_delete("/session/{sid}", remove)
    app.router.add_post("/session/{sid}/fork", fork)
    app.router.add_post("/session/{sid}/permissions/{pid}", reply_permission)
    app.router.add_get("/permission", permissions)
    app.router.add_get("/question", questions)
    app.router.add_post("/question/{qid}/reply", reply_question)
    app.router.add_post("/question/{qid}/reject", reject_question)
    app.router.add_get("/event", events)
    return app


if __name__ == "__main__":
    web.run_app(make_app(), host=HOST, port=PORT, print=lambda line: print(line, flush=True))
