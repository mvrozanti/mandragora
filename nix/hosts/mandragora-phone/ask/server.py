from __future__ import annotations

import asyncio
import http.client
import json
import os
import queue
import shutil
import signal
import socket
import sqlite3
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import httpx
from bs4 import BeautifulSoup
from ddgs import DDGS
from gpu_lock import GpuBusy, gpu_lock
from gpu_lock_ollama import evict_model, evict_others

HOST = os.environ.get("PHONE_ASK_HOST", "0.0.0.0")
PORT = int(os.environ.get("PHONE_ASK_PORT", "6689"))
STATE_DIR = Path(os.environ.get("PHONE_ASK_STATE", "~/.local/state/phone-ask")).expanduser()
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434").rstrip("/")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "gpt-oss:20b")
AGENTS_MD = os.environ.get("PHONE_ASK_AGENTS_MD", "/etc/nixos/mandragora/AGENTS.md")
LOCAL_LLM_MD = os.environ.get("PHONE_ASK_LOCAL_LLM_MD", "/etc/nixos/mandragora/docs/local-llm.md")
LEGACY_DB = Path(os.environ.get("PHONE_ASK_LEGACY_DB", "~/.local/share/llm-via-telegram/data/bot.db")).expanduser()
VJ_BASE = os.environ.get("PHONE_ASK_VJ", "http://127.0.0.1:8100").rstrip("/")
LOCK_NAME = "phone-ask:local"

TIMELINE_FILE = STATE_DIR / "timeline.json"
REGISTRY_FILE = STATE_DIR / "registry.json"
TIMELINE_KEEP = 300
HISTORY_MAX = 20
MAX_TOOL_TURNS = 12
NUM_CTX = 32768
OLLAMA_TIMEOUT = 180
TOOL_SHELL_TIMEOUT = 30
COMMAND_TIMEOUT = 120
TOOL_RESULT_MAX_CHARS = 8000
ENTRY_TEXT_MAX = 6000
WAIT_MAX = 50
QUEUE_MAX = 8

FETCH_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
FETCH_TIMEOUT = 15.0
FETCH_MAX_BYTES = 4 * 1024 * 1024
FETCH_DROP_TAGS = ("script", "style", "noscript", "template", "svg", "nav", "footer", "header", "aside", "form")

KNOWN = ("/help", "/start", "/context", "/clear", "/think", "/p", "/reg", "/run", "/sh", "/term", "/ff", "/open", "/vj", "/hotkey", "/browser", "/mpv")
DROPPED = {
    "/hotkey": "/hotkey is gone: it drove xdotool, which only works on X11 and this desktop is Wayland.",
    "/browser": "/browser is gone: it managed a marionette Firefox session that no longer exists. /open <url> opens a link on the desktop.",
    "/mpv": "/mpv is gone: mpv runs without an ipc socket, and the desktop's players are on the music card.",
}

HELP = """**ask** — the local model and the desktop's shell, from the phone

**Model**
- plain text — ask the local model; it can run shell, search the web and fetch pages
- `/p <persona> <question>` — ask with a registered persona instead of the system prompt
- `/think` — toggle reasoning (slower, better answers, trace shown above the reply)
- `/context` — model, system prompt sizes, history, token budget
- `/clear` — forget the conversation history

**Desktop**
- `/sh <command>` — run a shell command
- `/run <name>` — run a registered command
- `/term <command>` — open it in a new terminal on the desktop
- `/open <url>` (or `/ff`) — open a link in the desktop's browser

**Registry**
- `/reg prompt <name> <instruction>` — save a persona
- `/reg cmd <name> <command>` — save a shell shortcut
- `/reg list` · `/reg del <name>`

**vj**
- `/vj` — where to rate · `/vj stats` — what it learned · `/vj undo` — undo the last judgement"""

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "shell",
            "description": (
                "Run a shell command on this Linux machine. "
                "Covers window management (hyprctl), system queries, file ops, "
                "launching programs, NixOS rebuilds, etc."
            ),
            "parameters": {
                "type": "object",
                "properties": {"command": {"type": "string", "description": "Shell command to execute"}},
                "required": ["command"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": (
                "Search the public web via DuckDuckGo. Returns titles, URLs, and snippets. "
                "Use for current events, package versions, docs lookups, and anything beyond "
                "the local model's training cutoff. Follow up with fetch_url on promising hits."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"},
                    "max_results": {"type": "integer", "description": "1–10, default 5"},
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "fetch_url",
            "description": (
                "Fetch a URL and return extracted text (HTML stripped to main content). "
                "Use to read pages found via web_search or any direct link the user gives."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "Absolute URL or bare host"},
                    "max_chars": {"type": "integer", "description": "Truncate body to this many chars; default 8000"},
                },
                "required": ["url"],
            },
        },
    },
]


class Stopped(Exception):
    pass


def log(message: str) -> None:
    print(message.replace("\n", " | ")[:400], flush=True)


def read_json(path: Path, fallback):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return fallback


def write_json(path: Path, payload) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload), encoding="utf-8")
    os.replace(tmp, path)


def clip(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    head = text[: limit // 2]
    tail = text[-limit // 2 :]
    return f"{head}\n\n[... {len(text) - len(head) - len(tail)} chars truncated ...]\n\n{tail}"


def read_text(path: str) -> str | None:
    try:
        return Path(path).read_text(encoding="utf-8").strip() or None
    except OSError:
        return None


def system_parts() -> tuple[str | None, str | None]:
    return read_text(AGENTS_MD), read_text(LOCAL_LLM_MD)


def system_prompt() -> str | None:
    parts = [p for p in system_parts() if p]
    return "\n\n---\n\n".join(parts) if parts else None


def approx_tokens(text: str) -> int:
    return max(1, len(text) // 4) if text else 0


def format_exc(exc: BaseException) -> str:
    message = str(exc).strip()
    return f"{type(exc).__name__}: {message}" if message else type(exc).__name__


def busy_message(busy: GpuBusy) -> str:
    holder = busy.holder or {}
    name = holder.get("name", "another workload")
    remaining = busy.expected_remaining()
    if remaining is not None:
        return f"GPU is busy with {name}, ~{int(remaining)}s remaining. Try again then."
    return f"GPU is busy with {name}. Try again later."


def web_search(query: str, max_results: int = 5) -> str:
    if not query.strip():
        return "Error: empty query"
    max_results = max(1, min(max_results, 10))
    try:
        with DDGS() as ddgs:
            results = list(ddgs.text(query, max_results=max_results))
    except Exception as exc:
        return f"Error: search failed: {type(exc).__name__}: {exc}"
    if not results:
        return f"No results for: {query}"
    lines = []
    for i, row in enumerate(results, 1):
        title = (row.get("title") or "").strip()
        url = (row.get("href") or row.get("url") or "").strip()
        snippet = (row.get("body") or "").strip()
        lines.append(f"[{i}] {title}\n    {url}\n    {snippet}")
    return "\n\n".join(lines)


def extract_text(html: str) -> str:
    soup = BeautifulSoup(html, "lxml")
    for tag in soup(FETCH_DROP_TAGS):
        tag.decompose()
    main = soup.find("main") or soup.find("article") or soup.body or soup
    text = main.get_text(separator="\n", strip=True)
    out: list[str] = []
    previous = ""
    for line in (ln.strip() for ln in text.splitlines()):
        if line and line != previous:
            out.append(line)
            previous = line
    return "\n".join(out)


def fetch_url(url: str, max_chars: int = 8000) -> str:
    url = url.strip()
    if not url:
        return "Error: empty url"
    if not url.startswith(("http://", "https://")):
        url = "https://" + url
    max_chars = max(500, min(max_chars, 32000))
    try:
        with httpx.Client(timeout=FETCH_TIMEOUT, follow_redirects=True, headers={"User-Agent": FETCH_UA, "Accept": "text/html,*/*;q=0.8"}) as client:
            resp = client.get(url)
    except httpx.HTTPError as exc:
        return f"Error: {type(exc).__name__}: {exc}"
    content_type = resp.headers.get("content-type", "").lower()
    body = resp.content[:FETCH_MAX_BYTES]
    if "html" in content_type or "<html" in body[:512].lower().decode(errors="replace"):
        try:
            text = extract_text(body.decode(resp.encoding or "utf-8", errors="replace"))
        except Exception:
            text = body.decode("utf-8", errors="replace")
    else:
        text = body.decode("utf-8", errors="replace")
    header = f"URL: {resp.url}\nStatus: {resp.status_code}\nContent-Type: {content_type}\n\n"
    return header + clip(text, max_chars)


class Registry:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        data = read_json(REGISTRY_FILE, None)
        if not isinstance(data, dict):
            data = {"prompts": {}, "commands": {}}
            self._import_legacy(data)
            write_json(REGISTRY_FILE, data)
        self.prompts: dict[str, str] = dict(data.get("prompts") or {})
        self.commands: dict[str, str] = dict(data.get("commands") or {})

    @staticmethod
    def _import_legacy(data: dict) -> None:
        if not LEGACY_DB.is_file():
            return
        try:
            conn = sqlite3.connect(f"file:{LEGACY_DB}?mode=ro", uri=True)
            try:
                data["prompts"] = {name: text for name, text in conn.execute("SELECT name, system_instruction FROM prompts")}
                data["commands"] = {name: seq for name, seq in conn.execute("SELECT name, sequence FROM registered_commands")}
            finally:
                conn.close()
            log(f"imported {len(data['prompts'])} prompts and {len(data['commands'])} commands from {LEGACY_DB}")
        except sqlite3.Error as exc:
            log(f"legacy import skipped: {exc}")

    def _save(self) -> None:
        write_json(REGISTRY_FILE, {"prompts": self.prompts, "commands": self.commands})

    def save_prompt(self, name: str, instruction: str) -> None:
        with self.lock:
            self.prompts[name] = instruction
            self._save()

    def save_command(self, name: str, sequence: str) -> None:
        with self.lock:
            self.commands[name] = sequence
            self._save()

    def delete(self, name: str) -> str | None:
        with self.lock:
            if self.prompts.pop(name, None) is not None:
                self._save()
                return "prompt"
            if self.commands.pop(name, None) is not None:
                self._save()
                return "command"
            return None

    def view(self) -> tuple[list[dict], list[dict]]:
        with self.lock:
            personas = [{"name": k, "instruction": v} for k, v in sorted(self.prompts.items())]
            commands = [{"name": k, "command": v} for k, v in sorted(self.commands.items())]
        return personas, commands


class Ask:
    def __init__(self) -> None:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        self.cond = threading.Condition()
        self.registry = Registry()
        data = read_json(TIMELINE_FILE, {})
        self.entries: list[dict] = list(data.get("entries") or [])[-TIMELINE_KEEP:]
        self.next_id = max(int(data.get("next") or 1), 1 + max((e["id"] for e in self.entries), default=0))
        self.history: list[dict] = list(data.get("history") or [])[-HISTORY_MAX:]
        self.think = bool(data.get("think", True))
        self.version = 0
        self.busy = False
        self.activity: str | None = None
        self.jobs: queue.Queue[str] = queue.Queue()
        self.stop_flag = threading.Event()
        self.current_conn: http.client.HTTPConnection | None = None
        self.current_proc: subprocess.Popen | None = None
        threading.Thread(target=self._work, name="ask-worker", daemon=True).start()

    def _persist(self) -> None:
        write_json(TIMELINE_FILE, {"next": self.next_id, "entries": self.entries, "history": self.history, "think": self.think})

    def _changed(self) -> None:
        self.version += 1
        self.cond.notify_all()

    def add(self, role: str, text: str, thinking: str | None = None, meta: dict | None = None) -> int:
        with self.cond:
            entry = {"id": self.next_id, "ts": time.time(), "role": role, "text": clip(text, ENTRY_TEXT_MAX)}
            if thinking:
                entry["thinking"] = clip(thinking, ENTRY_TEXT_MAX)
            if meta:
                entry["meta"] = meta
            self.next_id += 1
            self.entries = (self.entries + [entry])[-TIMELINE_KEEP:]
            self._persist()
            self._changed()
        log(f"[{role}] {text[:200]}")
        return entry["id"]

    def set_activity(self, busy: bool, activity: str | None) -> None:
        with self.cond:
            self.busy = busy
            self.activity = activity
            self._changed()

    def view(self, after: int) -> dict:
        personas, commands = self.registry.view()
        newer = [e for e in self.entries if e["id"] > after]
        return {
            "entries": newer[-200:],
            "last": self.next_id - 1,
            "busy": self.busy,
            "queued": self.jobs.qsize(),
            "activity": self.activity,
            "model": OLLAMA_MODEL,
            "think": self.think,
            "personas": personas,
            "commands": commands,
        }

    def wait(self, after: int, wait: float) -> dict:
        deadline = time.monotonic() + min(max(wait, 0.0), WAIT_MAX)
        with self.cond:
            seen = self.version
            while True:
                remaining = deadline - time.monotonic()
                if any(e["id"] > after for e in self.entries) or self.version != seen or remaining <= 0:
                    return self.view(after)
                self.cond.wait(remaining)

    def submit(self, text: str) -> dict:
        text = text.strip()
        if not text:
            raise ValueError("text required")
        if self.jobs.qsize() >= QUEUE_MAX:
            raise ValueError("too many queued; wait for the current turn")
        entry_id = self.add("user", text)
        self.jobs.put(text)
        with self.cond:
            self._changed()
        return {"accepted": True, "id": entry_id}

    def stop(self) -> dict:
        drained = 0
        while True:
            try:
                self.jobs.get_nowait()
                drained += 1
            except queue.Empty:
                break
        was_busy = self.busy
        if was_busy:
            self.stop_flag.set()
            conn = self.current_conn
            if conn is not None and conn.sock is not None:
                try:
                    conn.sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
            proc = self.current_proc
            if proc is not None and proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    pass
        if drained and not was_busy:
            self.add("system", f"dropped {drained} queued")
        with self.cond:
            self._changed()
        return {"stopped": was_busy, "dropped": drained}

    def set_think(self, on: bool | None) -> dict:
        with self.cond:
            self.think = (not self.think) if on is None else bool(on)
            self._persist()
        self.add("system", "thinking on — the model reasons before answering; the trace sits above each reply" if self.think else "thinking off — fast replies, no reasoning trace")
        return {"think": self.think}

    def _work(self) -> None:
        while True:
            text = self.jobs.get()
            self.stop_flag.clear()
            self.set_activity(True, "working")
            try:
                self.handle(text)
            except Stopped:
                self.add("system", "stopped")
            except Exception as exc:
                log(f"handler failed: {format_exc(exc)}")
                self.add("error", f"Internal error: {format_exc(exc)}")
            finally:
                self.current_conn = None
                self.current_proc = None
                self.set_activity(False, None)

    def handle(self, text: str) -> None:
        if not text.startswith("/"):
            self.query(text)
            return
        head, _, rest = text.partition(" ")
        command = head.split("@", 1)[0].lower()
        rest = rest.strip()
        args = rest.split()
        if command in DROPPED:
            self.add("system", DROPPED[command])
        elif command in ("/help", "/start"):
            self.add("system", HELP)
        elif command == "/context":
            self.add("system", self.context())
        elif command == "/clear":
            with self.cond:
                self.history.clear()
                self._persist()
            self.add("system", "conversation history cleared", meta={"divider": True})
        elif command == "/think":
            on = {"on": True, "off": False}.get(args[0].lower()) if args else None
            self.set_think(on)
        elif command == "/p":
            self.persona(args, rest)
        elif command == "/reg":
            self.reg(args, rest)
        elif command == "/run":
            self.run_registered(args)
        elif command == "/sh":
            if not rest:
                self.add("system", "usage: `/sh <command>`")
            else:
                self.shell_entry(rest, rest, COMMAND_TIMEOUT)
        elif command == "/term":
            self.terminal(rest)
        elif command in ("/ff", "/open"):
            self.open_url(rest)
        elif command == "/vj":
            self.vj(args)
        else:
            near = [p for p in KNOWN if command.startswith(p)]
            if near:
                self.add("system", f"unknown command `{head}` — did you mean `{near[0]}`? `/help` lists them all")
            else:
                self.query(text)

    def context(self) -> str:
        agents, local = system_parts()
        prompt = system_prompt() or ""
        with self.cond:
            history = list(self.history)
        history_chars = sum(len(m["content"]) for m in history)
        total = approx_tokens(prompt) + sum(approx_tokens(m["content"]) for m in history)
        lines = [
            f"**Model** `{OLLAMA_MODEL}` · `num_ctx={NUM_CTX}` · thinking {'on' if self.think else 'off'}",
            "",
            "**System prompt**",
            f"- AGENTS.md: {len(agents or ''):,} chars",
            f"- local-llm.md: {len(local or ''):,} chars",
            f"- combined: {len(prompt):,} chars (~{approx_tokens(prompt):,} tokens)",
            "",
            f"**History** {len(history)} messages, {history_chars:,} chars",
            f"**Total** ~{total:,} tokens of {NUM_CTX:,} ({100.0 * total / NUM_CTX:.1f}% of the window)",
        ]
        if history:
            lines += ["", "**Last turns**"]
            for message in history[-5:]:
                content = message["content"].replace("\n", " ").replace("`", "'")
                if len(content) > 120:
                    content = content[:117] + "..."
                lines.append(f"- `{message['role'][0]}` {content}")
        return "\n".join(lines)

    def reg(self, args: list[str], rest: str) -> None:
        if not args:
            self.add("system", "`/reg prompt <name> <instruction>` · `/reg cmd <name> <command>` · `/reg list` · `/reg del <name>`")
            return
        sub = args[0].lower()
        body = rest[len(args[0]):].strip()
        name, _, value = body.partition(" ")
        value = value.strip()
        if sub == "prompt":
            if not name or not value:
                self.add("system", "usage: `/reg prompt <name> <instruction>`")
                return
            self.registry.save_prompt(name, value)
            self.add("system", f"persona `{name}` saved")
        elif sub in ("cmd", "command"):
            if not name or not value:
                self.add("system", "usage: `/reg cmd <name> <shell command>`")
                return
            self.registry.save_command(name, value)
            self.add("system", f"command `{name}` registered:\n\n```\n{value}\n```")
        elif sub == "list":
            personas, commands = self.registry.view()
            if not personas and not commands:
                self.add("system", "nothing registered yet")
                return
            lines: list[str] = []
            if personas:
                lines.append("**Personas**")
                lines += [f"- `{p['name']}` — {p['instruction'][:160]}" for p in personas]
            if commands:
                if lines:
                    lines.append("")
                lines.append("**Commands**")
                lines += [f"- `{c['name']}` → `{c['command']}`" for c in commands]
            self.add("system", "\n".join(lines))
        elif sub in ("del", "delete", "rm"):
            if not name:
                self.add("system", "usage: `/reg del <name>`")
                return
            kind = self.registry.delete(name)
            self.add("system", f"{'persona' if kind == 'prompt' else kind} `{name}` deleted" if kind else f"nothing named `{name}`")
        else:
            self.add("system", f"unknown subcommand `{sub}` — use prompt, cmd, list or del")

    def run_registered(self, args: list[str]) -> None:
        if not args:
            self.add("system", "usage: `/run <name>`")
            return
        name = args[0]
        _, commands = self.registry.view()
        found = {c["name"]: c["command"] for c in commands}
        sequence = found.get(name)
        if sequence is None:
            if found:
                listing = "\n".join(f"- `{n}` → `{s}`" for n, s in found.items())
                self.add("system", f"no command named `{name}`. Registered:\n\n{listing}")
            else:
                self.add("system", f"no command named `{name}` and none registered yet — `/reg cmd <name> <command>` adds one")
            return
        self.shell_entry(sequence, sequence, COMMAND_TIMEOUT, name=name)

    def run_process(self, command: str, timeout: int) -> tuple[int, str]:
        proc = subprocess.Popen(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
        self.current_proc = proc
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
            return -1, f"timed out after {timeout}s"
        finally:
            self.current_proc = None
        if self.stop_flag.is_set():
            raise Stopped()
        stdout = out.decode("utf-8", errors="replace").strip()
        stderr = err.decode("utf-8", errors="replace").strip()
        return proc.returncode, stdout or stderr or "(no output)"

    def shell_entry(self, command: str, shown: str, timeout: int, name: str | None = None) -> None:
        self.set_activity(True, f"running {name or shown}"[:120])
        rc, output = self.run_process(command, timeout)
        meta = {"command": shown, "rc": rc}
        if name:
            meta["name"] = name
        self.add("shell", output, meta=meta)

    def spawn(self, argv: list[str]) -> None:
        subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    def terminal(self, command: str) -> None:
        if not command:
            self.add("system", "usage: `/term <command>`")
            return
        builders = (
            ("kitty", lambda c: ["kitty", "--", "bash", "-c", c]),
            ("alacritty", lambda c: ["alacritty", "-e", "bash", "-c", c]),
            ("foot", lambda c: ["foot", "bash", "-c", c]),
        )
        for binary, build in builders:
            if shutil.which(binary):
                try:
                    self.spawn(build(command))
                except OSError as exc:
                    self.add("error", f"could not open a terminal: {exc}")
                    return
                self.add("system", f"opened in {binary} on the desktop: `{command}`")
                return
        self.add("error", "no terminal emulator found (looked for kitty, alacritty, foot)")

    def open_url(self, url: str) -> None:
        url = url.strip().split()[0] if url.strip() else ""
        if not url:
            self.add("system", "usage: `/open <url>`")
            return
        if not url.startswith(("http://", "https://")):
            url = "https://" + url
        try:
            self.spawn(["xdg-open", url])
        except OSError as exc:
            self.add("error", f"could not open {url}: {exc}")
            return
        self.add("system", f"opened on the desktop: {url}")

    def vj(self, args: list[str]) -> None:
        sub = args[0].lower() if args else ""
        try:
            if sub == "undo":
                data = vj_call("POST", "/api/trial/undo", {})
                self.add("system", f"undid the last judgement · {data['total']} judged" if data.get("ok") else "nothing to undo")
            elif sub == "stats":
                self.add("system", vj_stats(vj_call("GET", "/api/insight")))
            else:
                self.add("system", "vj trials are drawn live in the browser, so they are rated there.\n\nRate at https://vj.mvr.ac · what it learned: https://vj.mvr.ac/insight\n\n`/vj stats` · `/vj undo`")
        except (OSError, ValueError, KeyError) as exc:
            self.add("error", f"vj core unreachable at {VJ_BASE}: {format_exc(exc)}")

    def persona(self, args: list[str], rest: str) -> None:
        if len(args) < 2:
            self.add("system", "usage: `/p <name> <question>`")
            return
        name = args[0]
        question = rest[len(name):].strip()
        personas, _ = self.registry.view()
        instruction = next((p["instruction"] for p in personas if p["name"] == name), None)
        if instruction is None:
            self.add("system", f"no persona named `{name}` — register it with `/reg prompt`")
            return
        messages = [{"role": "system", "content": instruction}, {"role": "user", "content": question}]
        result = self.on_gpu(messages)
        if result is not None:
            thinking, content = result
            self.add("assistant", content or "(empty response)", thinking=thinking, meta={"persona": name})

    def query(self, text: str) -> None:
        messages: list[dict] = []
        prompt = system_prompt()
        if prompt:
            messages.append({"role": "system", "content": prompt})
        with self.cond:
            messages.extend(self.history)
        messages.append({"role": "user", "content": text})
        result = self.on_gpu(messages)
        if result is None:
            return
        thinking, content = result
        self.add("assistant", content or "(empty response)", thinking=thinking)
        with self.cond:
            self.history.append({"role": "user", "content": text})
            self.history.append({"role": "assistant", "content": content})
            del self.history[:-HISTORY_MAX]
            self._persist()

    def on_gpu(self, messages: list[dict]) -> tuple[str, str] | None:
        self.set_activity(True, "waiting for the gpu")
        try:
            with gpu_lock.acquire(LOCK_NAME, expected_seconds=60):
                asyncio.run(evict_others(OLLAMA_BASE_URL, OLLAMA_MODEL))
                try:
                    return self.agentic(messages)
                finally:
                    self.set_activity(True, "freeing the gpu")
                    try:
                        asyncio.run(evict_model(OLLAMA_BASE_URL, OLLAMA_MODEL))
                    except Exception as exc:
                        log(f"ollama evict failed: {format_exc(exc)}")
        except GpuBusy as busy:
            self.add("error", busy_message(busy))
        except Stopped:
            raise
        except RuntimeError as exc:
            self.add("error", f"Query failed: {format_exc(exc)}")
        except OSError as exc:
            if self.stop_flag.is_set():
                raise Stopped() from exc
            self.add("error", f"Query failed: {format_exc(exc)}")
        return None

    def chat(self, messages: list[dict]) -> dict:
        payload = {
            "model": OLLAMA_MODEL,
            "messages": messages,
            "tools": TOOLS,
            "stream": False,
            "keep_alive": 0,
            "think": self.think,
            "options": {"num_ctx": NUM_CTX},
        }
        parsed = urllib.parse.urlparse(OLLAMA_BASE_URL)
        conn = http.client.HTTPConnection(parsed.hostname or "localhost", parsed.port or 11434, timeout=OLLAMA_TIMEOUT)
        self.current_conn = conn
        try:
            if self.stop_flag.is_set():
                raise Stopped()
            conn.request("POST", "/api/chat", body=json.dumps(payload), headers={"Content-Type": "application/json"})
            response = conn.getresponse()
            body = response.read()
        except (OSError, http.client.HTTPException) as exc:
            if self.stop_flag.is_set():
                raise Stopped() from exc
            raise RuntimeError(f"Ollama unreachable: {format_exc(exc)}") from exc
        finally:
            self.current_conn = None
            conn.close()
        if response.status != 200:
            raise RuntimeError(f"Ollama returned HTTP {response.status}: {body[:300].decode(errors='replace')}")
        return json.loads(body)

    def split_thinking(self, message: dict) -> tuple[str, str]:
        content = (message.get("content") or "").strip()
        thinking = (message.get("thinking") or "").strip()
        if not thinking and "<think>" in content.lower():
            start = content.lower().find("<think>")
            end = content.lower().find("</think>", start)
            if end != -1:
                thinking = content[start + 7 : end].strip()
                content = (content[:start] + content[end + 8 :]).strip()
        return (thinking if self.think else ""), content

    def agentic(self, messages: list[dict]) -> tuple[str, str]:
        last_call: tuple[str, str] | None = None
        last_result: str | None = None
        for _ in range(MAX_TOOL_TURNS):
            if self.stop_flag.is_set():
                raise Stopped()
            self.set_activity(True, "thinking" if self.think else "answering")
            message = self.chat(messages).get("message", {})
            calls = message.get("tool_calls") or []
            if not calls:
                return self.split_thinking(message)
            messages.append({"role": "assistant", "content": message.get("content", ""), "tool_calls": calls})
            for call in calls:
                if self.stop_flag.is_set():
                    raise Stopped()
                fn = call.get("function", {})
                name = fn.get("name", "")
                args = fn.get("arguments", {}) or {}
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except ValueError:
                        args = {}
                shown = str(args.get("command") or args.get("query") or args.get("url") or "")
                self.set_activity(True, f"{name}: {shown}"[:120])
                result = self.tool(name, args)
                self.add("tool", clip(result, 4000), meta={"name": name, "arg": shown[:300]})
                last_call = (name, shown[:200])
                last_result = result
                messages.append({"role": "tool", "content": result})
        note = f"(reached the tool call limit after {MAX_TOOL_TURNS} turns)"
        if last_call:
            note += f"\n\nlast: {last_call[0]}({last_call[1]})\n\nlast result: {(last_result or '')[-400:]}"
        return "", note

    def tool(self, name: str, args: dict) -> str:
        if name == "shell":
            rc, output = self.run_process(str(args.get("command", "")), TOOL_SHELL_TIMEOUT)
            if rc == -1:
                return f"Error: command {output}"
            result = output if rc == 0 else f"Exit {rc}: {output}"
            return clip(result, TOOL_RESULT_MAX_CHARS)
        if name == "web_search":
            return web_search(str(args.get("query", "")), int(args.get("max_results", 5) or 5))
        if name == "fetch_url":
            return fetch_url(str(args.get("url", "")), int(args.get("max_chars", 8000) or 8000))
        return f"Unknown tool: {name}"


def vj_call(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(f"{VJ_BASE}{path}", data=data, method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def vj_stats(data: dict) -> str:
    lines = [f"**{data['n']} judged**"]
    for axis, label in (("beauty", "beautiful"), ("sync", "in sync"), ("complete", "complete")):
        effect = (data.get("reading_effect") or {}).get(axis) or {}
        if effect:
            top = sorted(effect.items(), key=lambda kv: -kv[1])[:3]
            lines.append(f"- {label}: " + ", ".join(f"{k} {v:+.2f}" for k, v in top))
    means = data.get("media_means") or {}
    ranked = sorted((m for m in means if means[m]["n"]), key=lambda m: -sum(means[m][a] or 0 for a in ("beauty", "sync", "complete")))
    if ranked:
        lines.append("- best media: " + ", ".join(f"{m} ({means[m]['n']})" for m in ranked[:3]))
    return "\n".join(lines)


ASK: Ask | None = None


def ask() -> Ask:
    if ASK is None:
        raise RuntimeError("phone-ask has not started")
    return ASK


class Handler(BaseHTTPRequestHandler):
    server_version = "phone-ask/1"

    def log_message(self, format, *args):
        pass

    def send_json(self, payload, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def read_body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except ValueError:
            raise ValueError("body must be json") from None
        return data if isinstance(data, dict) else {}

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = dict(urllib.parse.parse_qsl(url.query))
        try:
            if url.path == "/healthz":
                self.send_json({"ok": True, "model": OLLAMA_MODEL, "busy": ask().busy})
            elif url.path == "/api/ask":
                self.send_json(ask().wait(int(query.get("after") or 0), float(query.get("wait") or 0)))
            else:
                self.send_json({"error": "not found"}, 404)
        except ValueError as err:
            self.send_json({"error": str(err)}, 400)

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        try:
            body = self.read_body()
            if url.path == "/api/ask":
                self.send_json(ask().submit(str(body.get("text") or "")))
            elif url.path == "/api/ask/stop":
                self.send_json(ask().stop())
            elif url.path == "/api/ask/think":
                on = body.get("on")
                self.send_json(ask().set_think(None if on is None else bool(on)))
            else:
                self.send_json({"error": "not found"}, 404)
        except ValueError as err:
            self.send_json({"error": str(err)}, 400)


def main() -> None:
    global ASK
    ASK = Ask()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.daemon_threads = True
    log(f"phone-ask listening on {HOST}:{PORT}, model {OLLAMA_MODEL}")
    server.serve_forever()


if __name__ == "__main__":
    main()
