import json
import logging
import os
import sqlite3
from typing import Any

import httpx

log = logging.getLogger("watch.judge")

API_KEY = os.environ.get("GEMINI_API_KEY", "").strip()
MODEL = os.environ.get("WATCH_GEMINI_MODEL", "gemini-2.5-flash").strip()
ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models"
TIMEOUT = float(os.environ.get("WATCH_GEMINI_TIMEOUT", "30"))
MAX_PER_CYCLE = int(os.environ.get("WATCH_JUDGE_MAX_PER_CYCLE", "20"))

VERDICTS = {"GO", "MAYBE", "NO"}


class QuotaExceeded(RuntimeError):
    pass


def enabled() -> bool:
    return bool(API_KEY)


SYSTEM_PROMPT = (
    "You are a strict relevance judge for a notification pipeline. "
    "Given a target spec (what the user actually cares about) and a candidate event, "
    "decide whether the event is a genuine match for the spec.\n\n"
    "Return ONLY a single line of JSON, no markdown, no prose:\n"
    '{\"verdict\":\"GO|MAYBE|NO\",\"reason\":\"<=200 chars\"}\n\n'
    "Definitions:\n"
    "- GO: the event clearly satisfies EVERY explicit requirement in the spec right now "
    "  (e.g. correct device generation AND firmware range AND a working release/exploit).\n"
    "- MAYBE: on-topic AND every explicit spec requirement is positively evidenced, but "
    "  deliverability is unclear (e.g. dev preview claims the right device + firmware but no "
    "  artifact yet). Reserved for cases where the spec's checklist is fully satisfied on paper "
    "  but execution is in doubt.\n"
    "- NO: off-topic, wrong device/firmware/version, speculation, or — critically — the event "
    "  fails to specify ANY explicit spec requirement (e.g. spec demands PW12 + fw 5.18.x and "
    "  the event just says 'Kindle Paperwhite' with no generation or firmware). Missing required "
    "  info is NO, not MAYBE. A notification the user has to manually verify is a failed filter.\n\n"
    "Hard rule: if the spec lists concrete constraints (model number, firmware range, version, "
    "platform) and the event does not positively assert each one, return NO. Do not infer, do "
    "not assume, do not give benefit of the doubt. Reason must cite which required field is "
    "missing or which value mismatches. Never invent facts not in the event."
)


def build_user_prompt(ai_spec: str, event: dict[str, Any]) -> str:
    return (
        "SPEC:\n"
        f"{ai_spec}\n\n"
        "EVENT:\n"
        f"source: {event.get('w_kind')}:{event.get('w_target')}\n"
        f"title: {event.get('title') or ''}\n"
        f"summary: {(event.get('summary') or '')[:1500]}\n"
        f"link: {event.get('link') or ''}\n"
        f"occurred_at: {event.get('occurred_at') or ''}\n"
    )


async def judge_event(ai_spec: str, event: dict[str, Any]) -> tuple[str, str]:
    if not enabled():
        raise RuntimeError("GEMINI_API_KEY not configured")
    url = f"{ENDPOINT}/{MODEL}:generateContent"
    payload = {
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": [{"role": "user", "parts": [{"text": build_user_prompt(ai_spec, event)}]}],
        "generationConfig": {
            "temperature": 0.0,
            "responseMimeType": "application/json",
            "responseSchema": {
                "type": "OBJECT",
                "properties": {
                    "verdict": {"type": "STRING", "enum": ["GO", "MAYBE", "NO"]},
                    "reason": {"type": "STRING"},
                },
                "required": ["verdict", "reason"],
            },
            "maxOutputTokens": 256,
        },
    }
    async with httpx.AsyncClient(timeout=TIMEOUT) as c:
        r = await c.post(url, params={"key": API_KEY}, json=payload)
    if r.status_code == 429:
        raise QuotaExceeded(r.text[:300])
    if r.status_code in (401, 403):
        raise RuntimeError(f"gemini auth error {r.status_code}: {r.text[:200]}")
    if r.status_code >= 400:
        body = r.text[:300]
        if "quota" in body.lower() or "rate" in body.lower():
            raise QuotaExceeded(body)
        raise RuntimeError(f"gemini http {r.status_code}: {body}")
    doc = r.json()
    try:
        text = doc["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError, TypeError) as exc:
        raise RuntimeError(f"gemini bad response shape: {exc} {json.dumps(doc)[:200]}")
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"gemini bad json: {exc} text={text[:200]}")
    verdict = str(parsed.get("verdict", "")).upper()
    reason = str(parsed.get("reason", ""))[:500]
    if verdict not in VERDICTS:
        raise RuntimeError(f"gemini bad verdict: {verdict!r}")
    return verdict, reason


async def judge_pending(conn_factory) -> dict[str, int]:
    stats = {"judged": 0, "go": 0, "maybe": 0, "no": 0, "errors": 0}
    if not enabled():
        return stats
    c = conn_factory()
    rows = c.execute(
        """
        SELECT e.id AS id, e.title, e.summary, e.link, e.occurred_at, e.external_id,
               w.ai_spec AS w_spec, w.kind AS w_kind, w.target AS w_target
        FROM events e JOIN watchers w ON w.id = e.watcher_id
        WHERE e.ai_verdict IS NULL AND w.ai_spec IS NOT NULL AND w.enabled = 1
        ORDER BY e.id DESC
        LIMIT ?
        """,
        (MAX_PER_CYCLE,),
    ).fetchall()
    c.close()
    from datetime import datetime, timezone
    for r in rows:
        try:
            verdict, reason = await judge_event(r["w_spec"], dict(r))
        except QuotaExceeded as exc:
            log.warning("gemini quota exceeded; deferring %d remaining events: %s", len(rows) - stats["judged"], exc)
            break
        except Exception as exc:
            stats["errors"] += 1
            log.warning("judge error event_id=%s: %s", r["id"], exc)
            continue
        now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        c = conn_factory()
        c.execute(
            "UPDATE events SET ai_verdict = ?, ai_reason = ?, ai_judged_at = ? WHERE id = ?",
            (verdict, reason[:500], now, r["id"]),
        )
        c.close()
        stats["judged"] += 1
        stats[verdict.lower()] = stats.get(verdict.lower(), 0) + 1
    return stats
