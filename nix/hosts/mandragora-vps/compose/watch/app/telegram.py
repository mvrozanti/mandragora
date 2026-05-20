import asyncio
import html
import logging
import os
import sqlite3
from typing import Any

import httpx

import sources

log = logging.getLogger("watch.telegram")

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
ALLOWED_CHAT_IDS = {
    int(x) for x in os.environ.get("TELEGRAM_CHAT_ID", "").replace(",", " ").split() if x.strip().lstrip("-").isdigit()
}
API = f"https://api.telegram.org/bot{BOT_TOKEN}"


def enabled() -> bool:
    return bool(BOT_TOKEN) and bool(ALLOWED_CHAT_IDS)


def _esc(s: str | None) -> str:
    return html.escape(s or "", quote=False)


async def _post(method: str, payload: dict) -> dict | None:
    if not BOT_TOKEN:
        return None
    try:
        async with httpx.AsyncClient(timeout=20.0) as c:
            r = await c.post(f"{API}/{method}", json=payload)
        if r.status_code >= 400:
            log.warning("tg %s failed: %s %s", method, r.status_code, r.text[:200])
            return None
        return r.json()
    except Exception as exc:
        log.warning("tg %s exception: %s", method, exc)
        return None


async def push_event(watcher: sqlite3.Row, ev: dict[str, Any]) -> None:
    if not enabled():
        return
    title = ev.get("title") or "(no title)"
    summary = ev.get("summary") or ""
    link = ev.get("link") or ""
    kind = watcher["kind"]
    target = watcher["target"]
    text_lines = [
        f"<b>{_esc(kind)}</b> · <code>{_esc(target)}</code>",
        _esc(title),
    ]
    if summary:
        text_lines.append(f"<i>{_esc(summary[:300])}</i>")
    if link:
        text_lines.append(f'<a href="{_esc(link)}">open</a>')
    text = "\n".join(text_lines)
    for chat_id in ALLOWED_CHAT_IDS:
        await _post("sendMessage", {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": False,
        })


HELP = (
    "<b>mandragora-watch</b>\n"
    "/list — show watchers\n"
    "/add &lt;kind&gt; &lt;target&gt; — kinds: github_user, github_repo, reddit_user, reddit_sub\n"
    "/del &lt;id&gt; — remove watcher\n"
    "/pause &lt;id&gt; — disable\n"
    "/resume &lt;id&gt; — enable\n"
    "/poll &lt;id&gt; — poll now\n"
    "/recent [n] — last n events (default 10)\n"
)


async def _cmd_list(conn_factory) -> str:
    c = conn_factory()
    rows = c.execute("SELECT id, kind, target, name, enabled, last_polled_at, last_error FROM watchers ORDER BY id").fetchall()
    c.close()
    if not rows:
        return "no watchers"
    lines = []
    for r in rows:
        flag = "" if r["enabled"] else " [paused]"
        err = f"\n  err: {_esc(r['last_error'][:120])}" if r["last_error"] else ""
        lines.append(f"<code>{r['id']}</code> {_esc(r['kind'])}:{_esc(r['target'])}{flag}{err}")
    return "\n".join(lines)


async def _cmd_add(conn_factory, args: list[str]) -> str:
    if len(args) < 2:
        return "usage: /add &lt;kind&gt; &lt;target&gt;"
    kind, target = args[0], args[1]
    if kind not in sources.SOURCE_KINDS:
        return f"unknown kind: {_esc(kind)}\nknown: {', '.join(sources.SOURCE_KINDS)}"
    try:
        target = sources.validate_target(kind, target)
    except ValueError as e:
        return f"invalid target: {_esc(str(e))}"
    name = " ".join(args[2:]) or f"{kind}:{target}"
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    c = conn_factory()
    try:
        c.execute("INSERT INTO watchers (kind, target, name, created_at, enabled) VALUES (?, ?, ?, ?, 1)", (kind, target, name, now))
    except sqlite3.IntegrityError:
        c.close()
        return "already exists"
    row = c.execute("SELECT id FROM watchers WHERE kind = ? AND target = ?", (kind, target)).fetchone()
    c.close()
    return f"added <code>{row['id']}</code> {_esc(kind)}:{_esc(target)}"


async def _cmd_del(conn_factory, args: list[str]) -> str:
    if not args or not args[0].isdigit():
        return "usage: /del &lt;id&gt;"
    wid = int(args[0])
    c = conn_factory()
    cur = c.execute("DELETE FROM watchers WHERE id = ?", (wid,))
    c.close()
    return f"deleted {wid}" if cur.rowcount else "not found"


async def _cmd_toggle(conn_factory, args: list[str], enable: bool) -> str:
    if not args or not args[0].isdigit():
        return f"usage: /{'resume' if enable else 'pause'} &lt;id&gt;"
    wid = int(args[0])
    c = conn_factory()
    cur = c.execute("UPDATE watchers SET enabled = ? WHERE id = ?", (1 if enable else 0, wid))
    c.close()
    if not cur.rowcount:
        return "not found"
    return f"{'resumed' if enable else 'paused'} {wid}"


async def _cmd_poll(conn_factory, args: list[str]) -> str:
    if not args or not args[0].isdigit():
        return "usage: /poll &lt;id&gt;"
    wid = int(args[0])
    c = conn_factory()
    r = c.execute("SELECT * FROM watchers WHERE id = ?", (wid,)).fetchone()
    c.close()
    if not r:
        return "not found"
    try:
        events, new_cursor = await sources.fetch(r["kind"], r["target"], r["cursor"])
    except Exception as e:
        return f"fetch failed: {_esc(str(e))}"
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    c = conn_factory()
    inserted = 0
    for ev in events:
        try:
            c.execute(
                "INSERT INTO events (watcher_id, external_id, title, summary, link, occurred_at, received_at, raw) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (wid, ev.get("external_id", ""), (ev.get("title") or "")[:500], (ev.get("summary") or "")[:2000], ev.get("link") or "", ev.get("occurred_at") or now, now, ""),
            )
            inserted += 1
        except sqlite3.IntegrityError:
            pass
    c.execute("UPDATE watchers SET cursor = ?, last_polled_at = ?, last_error = NULL WHERE id = ?", (new_cursor, now, wid))
    c.close()
    return f"polled {wid}: fetched={len(events)} new={inserted}"


async def _cmd_recent(conn_factory, args: list[str]) -> str:
    n = 10
    if args and args[0].isdigit():
        n = max(1, min(50, int(args[0])))
    c = conn_factory()
    rows = c.execute(
        "SELECT e.title, e.link, e.received_at, w.kind, w.target FROM events e JOIN watchers w ON w.id = e.watcher_id ORDER BY e.id DESC LIMIT ?",
        (n,),
    ).fetchall()
    c.close()
    if not rows:
        return "no events"
    lines = []
    for r in rows:
        title = _esc(r["title"])
        if r["link"]:
            title = f'<a href="{_esc(r["link"])}">{title}</a>'
        lines.append(f"<b>{_esc(r['kind'])}:{_esc(r['target'])}</b> · {title}")
    return "\n".join(lines)


async def _dispatch(conn_factory, chat_id: int, text: str) -> str | None:
    text = text.strip()
    if not text.startswith("/"):
        return None
    parts = text.split()
    cmd = parts[0].split("@")[0].lower()
    args = parts[1:]
    if cmd in ("/start", "/help"):
        return HELP
    if cmd == "/list":
        return await _cmd_list(conn_factory)
    if cmd == "/add":
        return await _cmd_add(conn_factory, args)
    if cmd == "/del":
        return await _cmd_del(conn_factory, args)
    if cmd == "/pause":
        return await _cmd_toggle(conn_factory, args, False)
    if cmd == "/resume":
        return await _cmd_toggle(conn_factory, args, True)
    if cmd == "/poll":
        return await _cmd_poll(conn_factory, args)
    if cmd == "/recent":
        return await _cmd_recent(conn_factory, args)
    return None


async def run_forever(conn_factory) -> None:
    if not enabled():
        log.info("telegram disabled (no token / chat_id)")
        return
    log.info("telegram polling getUpdates for chat_ids=%s", ALLOWED_CHAT_IDS)
    offset = 0
    while True:
        try:
            r = await _post("getUpdates", {"timeout": 25, "offset": offset, "allowed_updates": ["message"]})
            if not r or not r.get("ok"):
                await asyncio.sleep(5)
                continue
            for upd in r.get("result", []):
                offset = upd["update_id"] + 1
                msg = upd.get("message") or {}
                chat = msg.get("chat") or {}
                chat_id = chat.get("id")
                text = msg.get("text") or ""
                if chat_id not in ALLOWED_CHAT_IDS:
                    log.info("ignoring chat_id=%s", chat_id)
                    continue
                reply = await _dispatch(conn_factory, chat_id, text)
                if reply:
                    await _post("sendMessage", {
                        "chat_id": chat_id,
                        "text": reply,
                        "parse_mode": "HTML",
                        "disable_web_page_preview": True,
                    })
        except Exception as exc:
            log.exception("telegram loop error: %s", exc)
            await asyncio.sleep(5)
