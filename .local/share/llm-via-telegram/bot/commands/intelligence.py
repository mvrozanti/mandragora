"""Intelligence layer: plain text → local LLM with native shell tool, /p, /context, /clear."""

import asyncio
import logging
import os
import re

import httpx

from bot.helpers.formatter import MAX_MESSAGE_LENGTH, split_messages
from bot.helpers.ollama import evict_model, evict_others
from bot.helpers.web import fetch_url, web_search

import config
from telegram import Update
from telegram.constants import ChatAction
from telegram.ext import ContextTypes

from gpu_lock import gpu_lock, GpuBusy

logger = logging.getLogger(__name__)

_log_dir = os.getenv("LLM_VIA_TELEGRAM_LOG_DIR", os.path.join(config.BASE_DIR, "logs"))
os.makedirs(_log_dir, exist_ok=True)
_chat_log = logging.getLogger("chat_log")
_chat_log.setLevel(logging.INFO)
_fh = logging.FileHandler(os.path.join(_log_dir, "chat.log"))
_fh.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
_chat_log.addHandler(_fh)

_AGENTS_TEXT: str | None = None
try:
    with open(config.AGENTS_MD_PATH) as f:
        _AGENTS_TEXT = f.read().strip()
    logger.info("loaded AGENTS.md (%d chars)", len(_AGENTS_TEXT))
except FileNotFoundError:
    logger.warning("AGENTS.md not found at %s", config.AGENTS_MD_PATH)

_LOCAL_LLM_TEXT: str | None = None
try:
    with open(config.LOCAL_LLM_MD_PATH) as f:
        _LOCAL_LLM_TEXT = f.read().strip()
    logger.info("loaded local-llm.md (%d chars)", len(_LOCAL_LLM_TEXT))
except FileNotFoundError:
    logger.warning("local-llm.md not found at %s", config.LOCAL_LLM_MD_PATH)


def _build_system_prompt() -> str | None:
    parts = [p for p in (_AGENTS_TEXT, _LOCAL_LLM_TEXT) if p]
    return "\n\n---\n\n".join(parts) if parts else None


_TOOLS = [
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
                "properties": {
                    "command": {"type": "string", "description": "Shell command to execute"}
                },
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
                    "max_results": {
                        "type": "integer",
                        "description": "1–10, default 5",
                    },
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
                    "max_chars": {
                        "type": "integer",
                        "description": "Truncate body to this many chars; default 8000",
                    },
                },
                "required": ["url"],
            },
        },
    },
]

_THINK_RE = re.compile(r"<think>(.*?)</think>\s*", re.DOTALL | re.IGNORECASE)


_think_mode = True


def _split_thinking_and_content(msg: dict) -> tuple[str, str]:
    content = (msg.get("content") or "").strip()
    thinking = (msg.get("thinking") or "").strip()

    if not thinking:
        m = _THINK_RE.search(content)
        if m:
            thinking = m.group(1).strip()
            content = _THINK_RE.sub("", content).strip()

    return (thinking if _think_mode else ""), content


def _thinking_chunks(thinking: str) -> list[str]:
    safe = thinking.replace("```", "'''")
    chunks = split_messages(safe, max_length=MAX_MESSAGE_LENGTH - 12)
    return [f"```\n{c}\n```" for c in chunks]


async def _send_response(update: Update, thinking: str, content: str) -> None:
    if thinking:
        for chunk in _thinking_chunks(thinking):
            await update.message.reply_text(chunk, parse_mode="Markdown")
    body = content or "(empty response)"
    for chunk in split_messages(body):
        await update.message.reply_text(chunk)


_HISTORY_MAX = 20
_history: list[dict[str, str]] = []

_MAX_TOOL_TURNS = 12
_TYPING_REFRESH_SECONDS = 4
_TOOL_RESULT_MAX_CHARS = 8000


def _format_exc(exc: BaseException) -> str:
    msg = str(exc).strip()
    return f"{type(exc).__name__}: {msg}" if msg else type(exc).__name__


def _busy_message(busy: GpuBusy) -> str:
    holder = busy.holder or {}
    name = holder.get("name", "another workload")
    remaining = busy.expected_remaining()
    if remaining is not None:
        return f"GPU is busy with {name}, ~{int(remaining)}s remaining. Try again then."
    return f"GPU is busy with {name}. Try again later."


async def _execute_shell(command: str) -> str:
    logger.info("tool:shell: %s", command)
    _chat_log.info("[tool:shell] %s", command)
    proc = await asyncio.create_subprocess_shell(
        command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=30.0)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return "Error: command timed out after 30s"
    out = stdout.decode(errors="replace").strip()
    err = stderr.decode(errors="replace").strip()
    result = out or err or "(no output)"
    if proc.returncode != 0:
        result = f"Exit {proc.returncode}: {result}"
    if len(result) > _TOOL_RESULT_MAX_CHARS:
        head = result[: _TOOL_RESULT_MAX_CHARS // 2]
        tail = result[-_TOOL_RESULT_MAX_CHARS // 2 :]
        omitted = len(result) - len(head) - len(tail)
        result = f"{head}\n\n[... {omitted} chars truncated ...]\n\n{tail}"
    _chat_log.info("[tool:result] %s", result[:200])
    return result


async def _execute_tool(name: str, args: dict) -> str:
    if name == "shell":
        return await _execute_shell(args.get("command", ""))
    if name == "web_search":
        query = args.get("query", "")
        max_results = int(args.get("max_results", 5) or 5)
        _chat_log.info("[tool:web_search] %s (max=%d)", query, max_results)
        result = await web_search(query, max_results=max_results)
        _chat_log.info("[tool:result] %s", result[:200])
        return result
    if name == "fetch_url":
        url = args.get("url", "")
        max_chars = int(args.get("max_chars", 8000) or 8000)
        _chat_log.info("[tool:fetch_url] %s", url)
        result = await fetch_url(url, max_chars=max_chars)
        _chat_log.info("[tool:result] %s", result[:200])
        return result
    return f"Unknown tool: {name}"


async def _typing_loop(chat) -> None:
    try:
        while True:
            try:
                await chat.send_action(ChatAction.TYPING)
            except Exception:
                pass
            await asyncio.sleep(_TYPING_REFRESH_SECONDS)
    except asyncio.CancelledError:
        pass


async def _run_agentic(messages: list[dict]) -> tuple[str, str]:
    last_call: tuple[str, str] | None = None
    last_result: str | None = None
    for _ in range(_MAX_TOOL_TURNS):
        payload = {
            "model": config.OLLAMA_MODEL,
            "messages": messages,
            "tools": _TOOLS,
            "stream": False,
            "keep_alive": 0,
            "think": _think_mode,
            "options": {"num_ctx": 32768},
        }
        async with httpx.AsyncClient(timeout=180.0) as client:
            resp = await client.post(
                f"{config.OLLAMA_BASE_URL.rstrip('/')}/api/chat", json=payload
            )

        if resp.status_code != 200:
            raise RuntimeError(f"Ollama returned HTTP {resp.status_code}: {resp.text[:300]}")

        body = resp.json()
        msg = body.get("message", {})
        tool_calls = msg.get("tool_calls") or []

        if not tool_calls:
            return _split_thinking_and_content(msg)

        messages.append({
            "role": "assistant",
            "content": msg.get("content", ""),
            "tool_calls": tool_calls,
        })
        for tc in tool_calls:
            fn = tc.get("function", {})
            name = fn.get("name", "")
            args = fn.get("arguments", {})
            result = await _execute_tool(name, args)
            arg_repr = args.get("command") or args.get("query") or args.get("url") or ""
            last_call = (name, str(arg_repr)[:200])
            last_result = result
            messages.append({"role": "tool", "content": result})

    note = f"(reached tool call limit after {_MAX_TOOL_TURNS} turns)"
    if last_call:
        tail = (last_result or "")[-400:]
        note += f"\nlast: {last_call[0]}({last_call[1]})\nlast result: {tail}"
    return "", note


async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await dispatch_query(update, update.message.text.strip())


async def dispatch_query(update: Update, query: str) -> None:
    _chat_log.info("[user] %s", query.replace("\n", " | ")[:200])

    messages: list[dict] = []
    sys_prompt = _build_system_prompt()
    if sys_prompt:
        messages.append({"role": "system", "content": sys_prompt})
    messages.extend(_history)
    messages.append({"role": "user", "content": query})

    typing_task = asyncio.create_task(_typing_loop(update.message.chat))
    thinking = ""
    content = "(no response)"

    try:
        async with gpu_lock.acquire_async("llm-via-telegram:local", expected_seconds=60):
            await evict_others(config.OLLAMA_BASE_URL, config.OLLAMA_MODEL)

            try:
                thinking, content = await _run_agentic(messages)
            finally:
                try:
                    await asyncio.shield(
                        asyncio.create_task(evict_model(config.OLLAMA_BASE_URL, config.OLLAMA_MODEL))
                    )
                except Exception:
                    logger.exception("ollama evict failed")

        _chat_log.info("[assistant] %s", content.replace("\n", " | ")[:200])

        await _send_response(update, thinking, content)

        _history.append({"role": "user", "content": query})
        _history.append({"role": "assistant", "content": content})
        while len(_history) > _HISTORY_MAX:
            _history.pop(0)

    except GpuBusy as busy:
        await update.message.reply_text(_busy_message(busy))
    except RuntimeError as exc:
        logger.error("LLM error: %s", exc)
        await update.message.reply_text(f"Query failed: {_format_exc(exc)}")
    except Exception as exc:
        logger.exception("Unexpected error in handle_text")
        await update.message.reply_text(f"Query failed: {_format_exc(exc)}")
    finally:
        typing_task.cancel()
        try:
            await typing_task
        except (asyncio.CancelledError, Exception):
            pass



async def cmd_think(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    global _think_mode
    _think_mode = not _think_mode
    status = "on" if _think_mode else "off"
    detail = (
        "model will reason before answering; trace shown above each reply"
        if _think_mode
        else "fast replies, no reasoning trace"
    )
    await update.message.reply_text(f"Thinking mode: {status} — {detail}.")


async def cmd_clear(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    _history.clear()
    await update.message.reply_text("Conversation history cleared.")


def _approx_tokens(s: str) -> int:
    return max(1, len(s) // 4) if s else 0


async def cmd_context(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    num_ctx = 32768
    agents_chars = len(_AGENTS_TEXT) if _AGENTS_TEXT else 0
    llm_chars = len(_LOCAL_LLM_TEXT) if _LOCAL_LLM_TEXT else 0
    sys_prompt = _build_system_prompt() or ""
    sys_chars = len(sys_prompt)
    history_chars = sum(len(m["content"]) for m in _history)
    total_tokens = _approx_tokens(sys_prompt) + sum(_approx_tokens(m["content"]) for m in _history)
    used_pct = 100.0 * total_tokens / num_ctx

    lines = [
        f"*Model*: `{config.OLLAMA_MODEL}`",
        f"*Context window*: `num_ctx={num_ctx}`",
        "",
        "*System prompt*",
        f"  AGENTS.md:    {agents_chars:,} chars",
        f"  local-llm.md: {llm_chars:,} chars",
        f"  combined:     {sys_chars:,} chars (~{_approx_tokens(sys_prompt):,} tokens)",
        "",
        f"*History*: {len(_history)} messages, {history_chars:,} chars",
        f"*Total*: ~{total_tokens:,} tokens / {num_ctx:,} ({used_pct:.1f}% of window)",
    ]

    if _history:
        lines.append("")
        lines.append("*Last turns* (most recent last)")
        for msg in _history[-5:]:
            content = msg["content"].replace("\n", " ").replace("`", "'")
            if len(content) > 120:
                content = content[:117] + "..."
            lines.append(f"  `{msg['role'][0]}`: {content}")

    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def cmd_reg_prompt(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    from db import store
    if len(context.args) < 2:
        await update.message.reply_text("Usage: /reg prompt <name> <instruction>")
        return
    name = context.args[0]
    instruction = " ".join(context.args[1:])
    store.save_prompt(name, instruction)
    await update.message.reply_text(f"Prompt '{name}' saved.")


async def cmd_p(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    from db import store
    if len(context.args) < 2:
        await update.message.reply_text("Usage: /p <name> <query>")
        return

    name = context.args[0]
    query = " ".join(context.args[1:])
    system_instruction = store.get_prompt(name)

    if system_instruction is None:
        await update.message.reply_text(
            f"No prompt named '{name}' found. Register it with /reg prompt."
        )
        return

    await update.message.reply_text("Thinking...")
    try:
        messages = [
            {"role": "system", "content": system_instruction},
            {"role": "user", "content": query},
        ]
        async with gpu_lock.acquire_async("llm-via-telegram:local", expected_seconds=60):
            await evict_others(config.OLLAMA_BASE_URL, config.OLLAMA_MODEL)
            try:
                thinking, content = await _run_agentic(messages)
            finally:
                try:
                    await asyncio.shield(
                        asyncio.create_task(evict_model(config.OLLAMA_BASE_URL, config.OLLAMA_MODEL))
                    )
                except Exception:
                    logger.exception("ollama evict failed")
        await _send_response(update, thinking, content)
    except GpuBusy as busy:
        await update.message.reply_text(_busy_message(busy))
    except RuntimeError as exc:
        logger.error("persona error: %s", exc)
        await update.message.reply_text(f"Local LLM error: {_format_exc(exc)}")
    except Exception as exc:
        logger.exception("Persona error")
        await update.message.reply_text(f"Persona query failed: {_format_exc(exc)}")
