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


async def push_event(watcher: Any, ev: dict[str, Any]) -> None:
    if not enabled():
        return
    title = ev.get("title") or "(no title)"
    summary = ev.get("summary") or ""
    link = ev.get("link") or ""
    kind = watcher["kind"]
    target = watcher["target"]
    requires_ack = bool(watcher["requires_ack"])
    is_reminder = bool(ev.get("is_reminder"))
    event_id = ev.get("id")
    prefix = "🔔 reminder " if is_reminder else ""
    text_lines = [
        f"{prefix}<b>{_esc(kind)}</b> · <code>{_esc(target)}</code>",
        _esc(title),
    ]
    if summary:
        text_lines.append(f"<i>{_esc(summary[:300])}</i>")
    if link:
        text_lines.append(f'<a href="{_esc(link)}">open</a>')
    if requires_ack and event_id is not None:
        text_lines.append(f"<code>/ack {event_id}</code>")
    text = "\n".join(text_lines)
    payload: dict[str, Any] = {
        "chat_id": 0,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": False,
    }
    if requires_ack and event_id is not None:
        row = [{"text": "✓ ack", "callback_data": f"ack:{event_id}"}]
        if link:
            row.append({"text": "open", "url": link})
        payload["reply_markup"] = {"inline_keyboard": [row]}
    for chat_id in ALLOWED_CHAT_IDS:
        payload["chat_id"] = chat_id
        await _post("sendMessage", payload)


HELP = (
    "<b>mandragora-watch</b>\n"
    "/list — show watchers\n"
    "/add &lt;kind&gt; &lt;target&gt; [name] — add watcher\n"
    "/addack &lt;kind&gt; &lt;target&gt; [name] — add watcher that nags until acked\n"
    "/del &lt;id&gt; — remove watcher\n"
    "/pause &lt;id&gt; — disable\n"
    "/resume &lt;id&gt; — enable\n"
    "/poll &lt;id&gt; — poll now\n"
    "/recent [n] — last n events (default 10)\n"
    "/unacked — list events awaiting ack\n"
    "/ack &lt;event_id&gt; — acknowledge event\n"
    "/ackall &lt;watcher_id&gt; — ack every event from a watcher\n"
    "/ackrequire &lt;watcher_id&gt; on|off — toggle requires_ack on a watcher\n"
    "/remind &lt;watcher_id&gt; &lt;seconds&gt; — set reminder interval\n"
)


async def _cmd_list(conn_factory) -> str:
    c = conn_factory()
    rows = c.execute(
        """
        SELECT w.id, w.kind, w.target, w.name, w.enabled, w.last_polled_at, w.last_error,
               w.requires_ack, w.reminder_interval,
               (SELECT COUNT(*) FROM events e WHERE e.watcher_id = w.id AND e.acked_at IS NULL) AS un
        FROM watchers w ORDER BY w.id
        """
    ).fetchall()
    c.close()
    if not rows:
        return "no watchers"
    lines = []
    for r in rows:
        flag = "" if r["enabled"] else " [paused]"
        ack = f" 🔔ack@{r['reminder_interval']}s" if r["requires_ack"] else ""
        unacked = f" un={r['un']}" if r["un"] else ""
        err = f"\n  err: {_esc(r['last_error'][:120])}" if r["last_error"] else ""
        lines.append(f"<code>{r['id']}</code> {_esc(r['kind'])}:{_esc(r['target'])}{flag}{ack}{unacked}{err}")
    return "\n".join(lines)


async def _cmd_add(conn_factory, args: list[str], requires_ack: bool = False) -> str:
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
        c.execute(
            "INSERT INTO watchers (kind, target, name, created_at, enabled, requires_ack) VALUES (?, ?, ?, ?, 1, ?)",
            (kind, target, name, now, 1 if requires_ack else 0),
        )
    except sqlite3.IntegrityError:
        c.close()
        return "already exists"
    row = c.execute("SELECT id FROM watchers WHERE kind = ? AND target = ?", (kind, target)).fetchone()
    c.close()
    suffix = " [requires_ack]" if requires_ack else ""
    return f"added <code>{row['id']}</code> {_esc(kind)}:{_esc(target)}{suffix}"


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


async def _cmd_unacked(conn_factory, args: list[str]) -> str:
    n = 25
    if args and args[0].isdigit():
        n = max(1, min(100, int(args[0])))
    c = conn_factory()
    rows = c.execute(
        """
        SELECT e.id, e.title, e.link, w.kind, w.target
        FROM events e JOIN watchers w ON w.id = e.watcher_id
        WHERE e.acked_at IS NULL AND w.requires_ack = 1
        ORDER BY e.id DESC LIMIT ?
        """,
        (n,),
    ).fetchall()
    c.close()
    if not rows:
        return "no unacked events"
    lines = []
    for r in rows:
        title = _esc(r["title"])
        if r["link"]:
            title = f'<a href="{_esc(r["link"])}">{title}</a>'
        lines.append(f"<code>{r['id']}</code> {_esc(r['kind'])}:{_esc(r['target'])} · {title}")
    return "\n".join(lines)


async def _cmd_ack(conn_factory, args: list[str]) -> str:
    if not args or not args[0].isdigit():
        return "usage: /ack &lt;event_id&gt;"
    eid = int(args[0])
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    c = conn_factory()
    cur = c.execute("UPDATE events SET acked_at = ? WHERE id = ? AND acked_at IS NULL", (now, eid))
    exists = c.execute("SELECT id FROM events WHERE id = ?", (eid,)).fetchone()
    c.close()
    if not exists:
        return f"event {eid} not found"
    return f"acked {eid}" if cur.rowcount else f"event {eid} already acked"


async def _cmd_ackall(conn_factory, args: list[str]) -> str:
    if not args or not args[0].isdigit():
        return "usage: /ackall &lt;watcher_id&gt;"
    wid = int(args[0])
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    c = conn_factory()
    cur = c.execute("UPDATE events SET acked_at = ? WHERE watcher_id = ? AND acked_at IS NULL", (now, wid))
    c.close()
    return f"acked {cur.rowcount} events for watcher {wid}"


async def _cmd_ackrequire(conn_factory, args: list[str]) -> str:
    if len(args) < 2 or not args[0].isdigit() or args[1].lower() not in ("on", "off"):
        return "usage: /ackrequire &lt;watcher_id&gt; on|off"
    wid = int(args[0])
    val = 1 if args[1].lower() == "on" else 0
    c = conn_factory()
    cur = c.execute("UPDATE watchers SET requires_ack = ? WHERE id = ?", (val, wid))
    c.close()
    if not cur.rowcount:
        return "not found"
    return f"watcher {wid} requires_ack={'on' if val else 'off'}"


async def _cmd_remind(conn_factory, args: list[str]) -> str:
    if len(args) < 2 or not args[0].isdigit() or not args[1].isdigit():
        return "usage: /remind &lt;watcher_id&gt; &lt;seconds&gt;"
    wid = int(args[0])
    secs = max(60, int(args[1]))
    c = conn_factory()
    cur = c.execute("UPDATE watchers SET reminder_interval = ? WHERE id = ?", (secs, wid))
    c.close()
    if not cur.rowcount:
        return "not found"
    return f"watcher {wid} reminder_interval={secs}s"


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
        return await _cmd_add(conn_factory, args, requires_ack=False)
    if cmd == "/addack":
        return await _cmd_add(conn_factory, args, requires_ack=True)
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
    if cmd == "/unacked":
        return await _cmd_unacked(conn_factory, args)
    if cmd == "/ack":
        return await _cmd_ack(conn_factory, args)
    if cmd == "/ackall":
        return await _cmd_ackall(conn_factory, args)
    if cmd == "/ackrequire":
        return await _cmd_ackrequire(conn_factory, args)
    if cmd == "/remind":
        return await _cmd_remind(conn_factory, args)
    return None


async def _handle_callback(conn_factory, cb: dict) -> None:
    cb_id = cb.get("id")
    data = cb.get("data") or ""
    chat_id = ((cb.get("message") or {}).get("chat") or {}).get("id")
    if chat_id not in ALLOWED_CHAT_IDS:
        await _post("answerCallbackQuery", {"callback_query_id": cb_id, "text": "denied"})
        return
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    if data.startswith("ack:"):
        try:
            eid = int(data.split(":", 1)[1])
        except ValueError:
            await _post("answerCallbackQuery", {"callback_query_id": cb_id, "text": "bad id"})
            return
        c = conn_factory()
        cur = c.execute("UPDATE events SET acked_at = ? WHERE id = ? AND acked_at IS NULL", (now, eid))
        c.close()
        text = f"acked {eid}" if cur.rowcount else f"event {eid} already acked"
        await _post("answerCallbackQuery", {"callback_query_id": cb_id, "text": text})
        msg = cb.get("message") or {}
        if msg.get("message_id"):
            await _post("editMessageReplyMarkup", {
                "chat_id": chat_id,
                "message_id": msg["message_id"],
                "reply_markup": {"inline_keyboard": [[{"text": f"✓ acked {eid}", "callback_data": "noop"}]]},
            })
        return
    await _post("answerCallbackQuery", {"callback_query_id": cb_id})


async def run_forever(conn_factory) -> None:
    if not enabled():
        log.info("telegram disabled (no token / chat_id)")
        return
    log.info("telegram polling getUpdates for chat_ids=%s", ALLOWED_CHAT_IDS)
    offset = 0
    while True:
        try:
            r = await _post("getUpdates", {"timeout": 25, "offset": offset, "allowed_updates": ["message", "callback_query"]})
            if not r or not r.get("ok"):
                await asyncio.sleep(5)
                continue
            for upd in r.get("result", []):
                offset = upd["update_id"] + 1
                if "callback_query" in upd:
                    await _handle_callback(conn_factory, upd["callback_query"])
                    continue
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
