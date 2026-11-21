import logging
import os
from typing import Any

import httpx

log = logging.getLogger("watch.inbox")

INBOX_URL = os.environ.get("WATCH_INBOX_URL", "").strip()
TIMEOUT = 15.0
SUMMARY_MAX = 300

DELIVERED = "delivered"
REFUSED = "refused"
UNREACHABLE = "unreachable"


def enabled() -> bool:
    return bool(INBOX_URL)


async def _post(payload: dict[str, Any]) -> str:
    if not INBOX_URL:
        return UNREACHABLE
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as c:
            r = await c.post(INBOX_URL, json=payload)
    except Exception as exc:
        log.warning("inbox post failed: %s", exc)
        return UNREACHABLE
    if r.status_code in (408, 429) or r.status_code >= 500:
        log.warning("inbox unavailable: %s %s", r.status_code, r.text[:200])
        return UNREACHABLE
    if r.status_code >= 400:
        log.error("inbox refused the message: %s %s", r.status_code, r.text[:200])
        return REFUSED
    return DELIVERED


async def broadcast(text: str, title: str = "watch", level: str = "info", link: str | None = None) -> bool:
    if not enabled():
        return False
    payload: dict[str, Any] = {"source": "watch", "title": title, "text": text, "open": "watch", "level": level}
    if link:
        payload["link"] = link
    return await _post(payload) == DELIVERED


def headline(watcher: Any, ev: dict[str, Any]) -> str:
    badges = []
    if ev.get("is_reminder"):
        badges.append("reminder")
    verdict = ev.get("ai_verdict")
    if verdict == "GO":
        badges.append("go")
    elif verdict == "UNCLEAR":
        badges.append("unclear")
    elif ev.get("escalated_at"):
        badges.append("unjudged")
    place = f"{watcher['kind']} · {watcher['target']}"
    return " · ".join([*badges, place])


def body(ev: dict[str, Any]) -> str:
    lines = [ev.get("title") or "(no title)"]
    summary = (ev.get("summary") or "").strip()
    if summary:
        lines.append(summary[:SUMMARY_MAX])
    reason = (ev.get("ai_reason") or "").strip()
    if reason:
        lines.append(f"why: {reason}")
    return "\n".join(lines)


def event_payload(watcher: Any, ev: dict[str, Any]) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "source": "watch",
        "title": headline(watcher, ev),
        "text": body(ev),
        "open": "watch",
        "level": "alert" if watcher["requires_ack"] else "info",
        "ref": {"event": ev.get("id"), "watcher": watcher["id"]},
    }
    if ev.get("link"):
        payload["link"] = ev["link"]
    return payload


async def push_event(watcher: Any, ev: dict[str, Any]) -> bool:
    if not enabled():
        log.error("inbox push skipped: WATCH_INBOX_URL unset")
        return False
    return await _post(event_payload(watcher, ev)) != UNREACHABLE
