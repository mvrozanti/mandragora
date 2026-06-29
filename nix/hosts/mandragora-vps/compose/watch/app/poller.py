import asyncio
import json
import logging
import os
import sqlite3
from datetime import datetime, timezone
from typing import Any

import httpx

import sources
import telegram as tg

log = logging.getLogger("watch.poller")

POLL_INTERVAL = int(os.environ.get("WATCH_POLL_INTERVAL", "300"))
SUMMARY_MAX = int(os.environ.get("WATCH_SUMMARY_MAX", "16000"))
WEBHOOK_URL = os.environ.get("WATCH_WEBHOOK_URL", "").strip()
PUBLIC_BASE = os.environ.get("WATCH_PUBLIC_BASE", "https://watch.mvr.ac")
PUSH_MAYBE = os.environ.get("WATCH_PUSH_MAYBE", "0").strip().lower() in ("1", "true", "yes", "on")
USER_AGENT = os.environ.get(
    "WATCH_USER_AGENT",
    "mandragora-watch/0.1 (+https://watch.mvr.ac)",
)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


async def poll_once(conn_factory) -> dict[str, int]:
    stats = {"watchers": 0, "events": 0, "errors": 0, "fanout": 0, "reminders": 0}
    c = conn_factory()
    rows = c.execute("SELECT * FROM watchers WHERE enabled = 1").fetchall()
    c.close()
    for row in rows:
        stats["watchers"] += 1
        try:
            events, new_cursor = await sources.fetch(row["kind"], row["target"], row["cursor"])
        except Exception as exc:
            stats["errors"] += 1
            log.warning("poll failed kind=%s target=%s err=%s", row["kind"], row["target"], exc)
            c = conn_factory()
            c.execute(
                "UPDATE watchers SET last_error = ?, last_polled_at = ? WHERE id = ?",
                (str(exc)[:500], now_iso(), row["id"]),
            )
            c.close()
            continue
        c = conn_factory()
        try:
            for ev in events:
                _insert_event(c, row["id"], ev)
                stats["events"] += 1
            c.execute(
                "UPDATE watchers SET cursor = ?, last_polled_at = ?, last_error = NULL WHERE id = ?",
                (new_cursor, now_iso(), row["id"]),
            )
            _prune(c, row["id"])
        finally:
            c.close()
    pushed, reminded = await _push_pending(conn_factory)
    stats["fanout"] += pushed
    stats["reminders"] += reminded
    return stats


async def _push_pending(conn_factory) -> tuple[int, int]:
    pushed = 0
    reminded = 0
    c = conn_factory()
    rows = c.execute(
        """
        SELECT e.*, w.id AS w_id, w.kind AS w_kind, w.target AS w_target, w.name AS w_name,
               w.requires_ack AS w_req, w.reminder_interval AS w_ri, w.ai_spec AS w_spec,
               w.push AS w_push
        FROM events e JOIN watchers w ON w.id = e.watcher_id
        WHERE e.acked_at IS NULL AND w.enabled = 1 AND w.push = 1
        ORDER BY e.id ASC
        """
    ).fetchall()
    c.close()
    now_ts = datetime.now(timezone.utc).timestamp()
    for r in rows:
        if r["w_spec"]:
            verdict = r["ai_verdict"]
            if verdict is None:
                continue
            if verdict == "NO":
                continue
            if verdict == "MAYBE" and not PUSH_MAYBE:
                continue
        last = r["last_reminder_at"]
        if last is None:
            due = True
            is_reminder = False
        elif r["w_req"]:
            try:
                last_ts = datetime.fromisoformat(last.replace("Z", "+00:00")).timestamp()
            except Exception:
                last_ts = 0.0
            if now_ts - last_ts >= int(r["w_ri"]):
                due = True
                is_reminder = True
            else:
                due = False
                is_reminder = False
        else:
            due = False
            is_reminder = False
        if not due:
            continue
        watcher_proxy = {
            "id": r["w_id"],
            "kind": r["w_kind"],
            "target": r["w_target"],
            "name": r["w_name"],
            "requires_ack": r["w_req"],
        }
        ev_proxy = {
            "id": r["id"],
            "external_id": r["external_id"],
            "title": r["title"],
            "summary": r["summary"],
            "link": r["link"],
            "occurred_at": r["occurred_at"],
            "is_reminder": is_reminder,
            "ai_verdict": r["ai_verdict"],
            "ai_reason": r["ai_reason"],
        }
        if WEBHOOK_URL:
            if await _fanout(watcher_proxy, ev_proxy):
                pushed += 1
        await tg.push_event(watcher_proxy, ev_proxy)
        if is_reminder:
            reminded += 1
        c = conn_factory()
        c.execute("UPDATE events SET last_reminder_at = ? WHERE id = ?", (now_iso(), r["id"]))
        c.close()
    return pushed, reminded


def _insert_event(c: sqlite3.Connection, watcher_id: int, ev: dict[str, Any]) -> None:
    try:
        c.execute(
            """
            INSERT INTO events (watcher_id, external_id, title, summary, link, occurred_at, received_at, raw)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                watcher_id,
                ev.get("external_id", ""),
                (ev.get("title") or "")[:500],
                (ev.get("summary") or "")[:SUMMARY_MAX],
                ev.get("link") or "",
                ev.get("occurred_at") or now_iso(),
                now_iso(),
                json.dumps(ev.get("raw") or {})[:32768],
            ),
        )
    except sqlite3.IntegrityError:
        pass


def _prune(c: sqlite3.Connection, watcher_id: int) -> None:
    cap = int(os.environ.get("WATCH_MAX_EVENTS_PER_WATCHER", "500"))
    c.execute(
        """
        DELETE FROM events
        WHERE watcher_id = ? AND id NOT IN (
          SELECT id FROM events
          WHERE watcher_id = ?
          ORDER BY id DESC
          LIMIT ?
        )
        """,
        (watcher_id, watcher_id, cap),
    )


async def _fanout(watcher: Any, ev: dict[str, Any]) -> bool:
    payload = {
        "source": "mandragora-watch",
        "kind": watcher["kind"],
        "target": watcher["target"],
        "name": watcher["name"],
        "event_id": ev.get("id"),
        "external_id": ev.get("external_id"),
        "title": ev.get("title"),
        "summary": ev.get("summary"),
        "link": ev.get("link"),
        "occurred_at": ev.get("occurred_at"),
        "requires_ack": bool(watcher["requires_ack"]),
        "is_reminder": bool(ev.get("is_reminder")),
        "ack_url": f"{PUBLIC_BASE.rstrip('/')}/ack/{ev.get('id')}" if ev.get("id") else None,
        "ai_verdict": ev.get("ai_verdict"),
        "ai_reason": ev.get("ai_reason"),
    }
    try:
        async with httpx.AsyncClient(timeout=10.0, headers={"User-Agent": USER_AGENT}) as c:
            r = await c.post(WEBHOOK_URL, json=payload)
        if r.status_code >= 400:
            log.warning("fanout non-2xx: %s %s", r.status_code, r.text[:200])
            return False
        return True
    except Exception as exc:
        log.warning("fanout failed: %s", exc)
        return False


async def run_forever(conn_factory) -> None:
    log.info("poller starting interval=%ss webhook=%s", POLL_INTERVAL, bool(WEBHOOK_URL))
    while True:
        try:
            stats = await poll_once(conn_factory)
            log.info("poll done %s", stats)
        except Exception as exc:
            log.exception("poll loop error: %s", exc)
        await asyncio.sleep(POLL_INTERVAL)
