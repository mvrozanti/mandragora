import asyncio
import json
import logging
import os
import sqlite3
from datetime import datetime, timezone
from typing import Any

import httpx

import sources

log = logging.getLogger("watch.poller")

POLL_INTERVAL = int(os.environ.get("WATCH_POLL_INTERVAL", "300"))
WEBHOOK_URL = os.environ.get("WATCH_WEBHOOK_URL", "").strip()
USER_AGENT = os.environ.get(
    "WATCH_USER_AGENT",
    "mandragora-watch/0.1 (+https://watch.mvr.ac)",
)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


async def poll_once(conn_factory) -> dict[str, int]:
    stats = {"watchers": 0, "events": 0, "errors": 0, "fanout": 0}
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
                if WEBHOOK_URL:
                    if await _fanout(row, ev):
                        stats["fanout"] += 1
            c.execute(
                "UPDATE watchers SET cursor = ?, last_polled_at = ?, last_error = NULL WHERE id = ?",
                (new_cursor, now_iso(), row["id"]),
            )
            _prune(c, row["id"])
        finally:
            c.close()
    return stats


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
                (ev.get("summary") or "")[:2000],
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


async def _fanout(watcher_row: sqlite3.Row, ev: dict[str, Any]) -> bool:
    payload = {
        "source": "mandragora-watch",
        "kind": watcher_row["kind"],
        "target": watcher_row["target"],
        "name": watcher_row["name"],
        "external_id": ev.get("external_id"),
        "title": ev.get("title"),
        "summary": ev.get("summary"),
        "link": ev.get("link"),
        "occurred_at": ev.get("occurred_at"),
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
