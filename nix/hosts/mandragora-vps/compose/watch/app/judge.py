import asyncio
import json
import logging
import os
import re
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from typing import Any

import httpx

log = logging.getLogger("watch.judge")

OLLAMA_URL = os.environ.get("WATCH_OLLAMA_URL", "http://100.115.80.79:11434").rstrip("/")
OLLAMA_MODEL = os.environ.get("WATCH_OLLAMA_MODEL", "qwen3:14b").strip()
OLLAMA_TIMEOUT = float(os.environ.get("WATCH_OLLAMA_TIMEOUT", "180"))
OLLAMA_NUM_CTX = int(os.environ.get("WATCH_OLLAMA_NUM_CTX", "16384"))
JUDGE_INTERVAL = int(os.environ.get("WATCH_JUDGE_INTERVAL", "30"))
JUDGE_BATCH = int(os.environ.get("WATCH_JUDGE_BATCH", "3"))
CLAIM_TTL = int(os.environ.get("WATCH_JUDGE_CLAIM_TTL", "900"))
LINK_MAX_CHARS = int(os.environ.get("WATCH_LINK_MAX_CHARS", "8000"))
LINK_TIMEOUT = float(os.environ.get("WATCH_LINK_TIMEOUT", "20"))
USER_AGENT = os.environ.get(
    "WATCH_USER_AGENT",
    "mandragora-watch/0.1 (+https://watch.mvr.ac)",
)

VERDICTS = {"GO", "UNCLEAR", "NO"}

CORROBORATE = os.environ.get("WATCH_CORROBORATE", "1").strip().lower() in ("1", "true", "yes", "on")
CORROBORATE_WINDOW_HOURS = int(os.environ.get("WATCH_CORROBORATE_WINDOW", "72"))
CORROBORATE_CANDIDATES = int(os.environ.get("WATCH_CORROBORATE_CANDIDATES", "12"))

QUOTA_SIGNALS = ("quota", "rate limit", "rate-limit", "resource_exhausted", "too many requests")


class QuotaExceeded(RuntimeError):
    pass


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _stale_cutoff_iso() -> str:
    cutoff = datetime.now(timezone.utc) - timedelta(seconds=CLAIM_TTL)
    return cutoff.isoformat(timespec="seconds").replace("+00:00", "Z")


CLAIM_SQL = (
    "UPDATE events SET ai_claimed_at = ? "
    "WHERE id = ? AND ai_verdict IS NULL AND (ai_claimed_at IS NULL OR ai_claimed_at < ?)"
)

WRITE_VERDICT_SQL = (
    "UPDATE events SET ai_verdict = ?, ai_reason = ?, ai_claim = ?, ai_judged_at = ?, ai_claimed_at = NULL "
    "WHERE id = ? AND ai_verdict IS NULL"
)

RELEASE_CLAIM_SQL = "UPDATE events SET ai_claimed_at = NULL WHERE id = ? AND ai_verdict IS NULL"

PROMOTE_SQL = (
    "UPDATE events SET ai_verdict = 'GO', ai_reason = ?, ai_judged_at = ? "
    "WHERE id = ? AND ai_verdict = 'UNCLEAR'"
)


SYSTEM_PROMPT = (
    "You are a strict relevance judge for a notification pipeline. "
    "Given a target spec (what the user actually cares about), a candidate event, "
    "and the fetched text content at the event's link, decide whether the event is a "
    "genuine match for the spec.\n\n"
    "Return ONLY a single line of JSON, no markdown, no prose, no <think> tags:\n"
    '{"verdict":"GO|UNCLEAR|NO","reason":"<=200 chars","claim":"<=160 chars"}\n\n'
    "Definitions:\n"
    "- GO: the link content clearly satisfies EVERY explicit requirement in the spec "
    "(e.g. correct device generation AND firmware range AND a working release/exploit) "
    "and states it as established fact. Quote the matched fields in the reason.\n"
    "- UNCLEAR: the content positively evidences every explicit spec requirement, but the "
    "assertion itself is weak — an unverified single report, a rumor attributed to no "
    "source, or a preview with nothing shipped yet. Corroboration from another source "
    "will promote it. Never use UNCLEAR for missing information.\n"
    "- NO: off-topic, wrong device/firmware/version, speculation about something that has "
    "not happened, OR the link content fails to positively assert any explicit spec "
    "requirement. Missing required info is NO, not UNCLEAR.\n\n"
    "The claim field is one normalized sentence naming exactly what is asserted (actor, "
    "artifact, action), written so two independent articles about the same underlying "
    "event yield near-identical claims. Omit outlet names, dates, and adjectives. Use an "
    "empty string when the verdict is NO.\n\n"
    "Hard rules:\n"
    "1. If the spec lists concrete constraints (model number, firmware range, version, "
    "platform) and the content does not positively assert each one, return NO.\n"
    "2. Do not infer, do not assume, do not give benefit of the doubt.\n"
    "3. If link content is empty or fetch failed, fall back to title+summary only; if "
    "those also do not positively assert each required field, return NO.\n"
    "4. Reason must cite which required field matched or which is missing/mismatched. "
    "Never invent facts not present in the provided text."
)


SAME_CLAIM_PROMPT = (
    "You decide whether two short claims describe the same underlying real-world event.\n"
    "Return ONLY a single line of JSON: "
    '{"same":true|false,"reason":"<=120 chars"}\n'
    "Same means identical actor, identical artifact or system, and identical action. "
    "Two outlets reporting one event are the same claim. A different version, a different "
    "product, a different vulnerability, or a later follow-up development is NOT the same "
    "claim. When in doubt, return false."
)


class _HTMLTextExtractor(HTMLParser):
    SKIP_TAGS = {"script", "style", "noscript", "template", "svg", "head"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._chunks: list[str] = []
        self._skip_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self.SKIP_TAGS:
            self._skip_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in self.SKIP_TAGS and self._skip_depth > 0:
            self._skip_depth -= 1

    def handle_data(self, data: str) -> None:
        if self._skip_depth:
            return
        s = data.strip()
        if s:
            self._chunks.append(s)

    def text(self) -> str:
        return re.sub(r"\s+", " ", " ".join(self._chunks)).strip()


def _strip_html(html: str) -> str:
    parser = _HTMLTextExtractor()
    try:
        parser.feed(html)
        parser.close()
    except Exception:
        pass
    return parser.text()


async def fetch_link(url: str) -> tuple[str, str | None]:
    if not url:
        return "", "no link"
    try:
        async with httpx.AsyncClient(
            timeout=LINK_TIMEOUT,
            follow_redirects=True,
            headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/xhtml+xml,application/xml,application/json;q=0.9,*/*;q=0.5"},
        ) as c:
            r = await c.get(url)
    except Exception as exc:
        return "", f"fetch error: {exc}"
    if r.status_code >= 400:
        return "", f"http {r.status_code}"
    ctype = (r.headers.get("content-type") or "").lower()
    body = r.text or ""
    if "html" in ctype or "xml" in ctype:
        text = _strip_html(body)
    elif "json" in ctype:
        try:
            text = json.dumps(json.loads(body), ensure_ascii=False)
        except Exception:
            text = body
    else:
        text = body
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > LINK_MAX_CHARS:
        text = text[:LINK_MAX_CHARS]
    return text, None


def build_user_prompt(ai_spec: str, event: dict[str, Any], link_text: str, fetch_err: str | None) -> str:
    link_block = link_text or "(empty)"
    if fetch_err:
        link_block = f"(fetch failed: {fetch_err}; falling back to title+summary)"
    return (
        "SPEC:\n"
        f"{ai_spec}\n\n"
        "EVENT:\n"
        f"source: {event.get('w_kind')}:{event.get('w_target')}\n"
        f"title: {event.get('title') or ''}\n"
        f"summary: {(event.get('summary') or '')[:1500]}\n"
        f"link: {event.get('link') or ''}\n"
        f"occurred_at: {event.get('occurred_at') or ''}\n\n"
        f"FETCHED LINK CONTENT (truncated to {LINK_MAX_CHARS} chars):\n"
        f"{link_block}\n"
    )


_JSON_OBJ_RE = re.compile(r"\{.*\}", re.DOTALL)


def _parse_json_object(text: str) -> dict:
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        m = _JSON_OBJ_RE.search(text)
        if not m:
            raise RuntimeError(f"no json object in response: {text[:200]}")
        return json.loads(m.group(0))


def _parse_verdict_json(text: str) -> tuple[str, str, str]:
    parsed = _parse_json_object(text)
    verdict = str(parsed.get("verdict", "")).upper().strip()
    reason = str(parsed.get("reason", ""))[:500]
    claim = str(parsed.get("claim", "") or "")[:300]
    if verdict not in VERDICTS:
        raise RuntimeError(f"bad verdict: {verdict!r}")
    return verdict, reason, claim


async def _generate(system: str, prompt: str, schema: dict, num_predict: int = 512) -> str:
    payload = {
        "model": OLLAMA_MODEL,
        "system": system,
        "prompt": prompt,
        "stream": False,
        "format": schema,
        "options": {
            "temperature": 0.0,
            "num_ctx": OLLAMA_NUM_CTX,
            "num_predict": num_predict,
        },
    }
    async with httpx.AsyncClient(timeout=OLLAMA_TIMEOUT) as c:
        r = await c.post(f"{OLLAMA_URL}/api/generate", json=payload)
    if r.status_code >= 400:
        body = r.text[:300]
        if r.status_code == 429 or any(sig in body.lower() for sig in QUOTA_SIGNALS):
            raise QuotaExceeded(f"ollama http {r.status_code}: {body}")
        raise RuntimeError(f"ollama http {r.status_code}: {body}")
    doc = r.json()
    text = doc.get("response") or ""
    if not text:
        raise RuntimeError(f"ollama empty response: {json.dumps(doc)[:200]}")
    return text


VERDICT_SCHEMA = {
    "type": "object",
    "properties": {
        "verdict": {"type": "string", "enum": ["GO", "UNCLEAR", "NO"]},
        "reason": {"type": "string"},
        "claim": {"type": "string"},
    },
    "required": ["verdict", "reason", "claim"],
}

SAME_CLAIM_SCHEMA = {
    "type": "object",
    "properties": {
        "same": {"type": "boolean"},
        "reason": {"type": "string"},
    },
    "required": ["same", "reason"],
}


async def judge_event(ai_spec: str, event: dict[str, Any]) -> tuple[str, str, str]:
    link_text, fetch_err = await fetch_link(event.get("link") or "")
    text = await _generate(
        SYSTEM_PROMPT,
        build_user_prompt(ai_spec, event, link_text, fetch_err),
        VERDICT_SCHEMA,
    )
    return _parse_verdict_json(text)


async def same_claim(claim_a: str, claim_b: str) -> tuple[bool, str]:
    text = await _generate(
        SAME_CLAIM_PROMPT,
        f"CLAIM A:\n{claim_a}\n\nCLAIM B:\n{claim_b}\n",
        SAME_CLAIM_SCHEMA,
        num_predict=200,
    )
    parsed = _parse_json_object(text)
    return bool(parsed.get("same")), str(parsed.get("reason", ""))[:200]


def _claim_event(conn_factory, event_id: int) -> bool:
    c = conn_factory()
    try:
        cur = c.execute(CLAIM_SQL, (_now_iso(), event_id, _stale_cutoff_iso()))
        return cur.rowcount == 1
    finally:
        c.close()


def _release_claim(conn_factory, event_id: int) -> None:
    c = conn_factory()
    try:
        c.execute(RELEASE_CLAIM_SQL, (event_id,))
    finally:
        c.close()


def _write_verdict(conn_factory, event_id: int, verdict: str, reason: str, claim: str = "") -> bool:
    c = conn_factory()
    try:
        cur = c.execute(WRITE_VERDICT_SQL, (verdict, reason[:500], claim[:300] or None, _now_iso(), event_id))
        return cur.rowcount == 1
    finally:
        c.close()


async def judge_pending(conn_factory) -> dict[str, int]:
    stats = {"judged": 0, "go": 0, "unclear": 0, "no": 0, "errors": 0, "skipped": 0}
    c = conn_factory()
    rows = c.execute(
        """
        SELECT e.id AS id, e.title, e.summary, e.link, e.occurred_at, e.external_id,
               w.ai_spec AS w_spec, w.kind AS w_kind, w.target AS w_target
        FROM events e JOIN watchers w ON w.id = e.watcher_id
        WHERE e.ai_verdict IS NULL AND w.ai_spec IS NOT NULL AND w.enabled = 1
          AND (e.ai_claimed_at IS NULL OR e.ai_claimed_at < ?)
        ORDER BY e.id DESC
        LIMIT ?
        """,
        (_stale_cutoff_iso(), JUDGE_BATCH),
    ).fetchall()
    c.close()
    for r in rows:
        if not _claim_event(conn_factory, r["id"]):
            stats["skipped"] += 1
            continue
        try:
            verdict, reason, claim = await judge_event(r["w_spec"], dict(r))
        except QuotaExceeded as exc:
            _release_claim(conn_factory, r["id"])
            log.warning("judge quota exceeded, deferring batch: %s", exc)
            break
        except Exception as exc:
            _release_claim(conn_factory, r["id"])
            stats["errors"] += 1
            log.warning("judge error event_id=%s: %s", r["id"], exc)
            continue
        if not _write_verdict(conn_factory, r["id"], verdict, reason, claim):
            stats["skipped"] += 1
            continue
        stats["judged"] += 1
        stats[verdict.lower()] = stats.get(verdict.lower(), 0) + 1
    return stats


def _corroboration_cutoff_iso() -> str:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=CORROBORATE_WINDOW_HOURS)
    return cutoff.isoformat(timespec="seconds").replace("+00:00", "Z")


def _promote(conn_factory, event_id: int, reason: str) -> bool:
    c = conn_factory()
    try:
        cur = c.execute(PROMOTE_SQL, (reason[:500], _now_iso(), event_id))
        return cur.rowcount == 1
    finally:
        c.close()


async def corroborate_pending(conn_factory) -> dict[str, int]:
    stats = {"checked": 0, "promoted": 0, "errors": 0}
    if not CORROBORATE:
        return stats
    cutoff = _corroboration_cutoff_iso()
    c = conn_factory()
    unclear = c.execute(
        """
        SELECT e.id, e.watcher_id, e.ai_claim, e.title, w.name AS w_name
        FROM events e JOIN watchers w ON w.id = e.watcher_id
        WHERE e.ai_verdict = 'UNCLEAR' AND e.ai_claim IS NOT NULL AND e.ai_claim != ''
          AND e.acked_at IS NULL AND e.received_at >= ? AND w.enabled = 1 AND w.push = 1
        ORDER BY e.id DESC
        """,
        (cutoff,),
    ).fetchall()
    c.close()
    resolved: set[int] = set()
    for row in unclear:
        if row["id"] in resolved:
            continue
        c = conn_factory()
        candidates = c.execute(
            """
            SELECT e.id, e.ai_claim, e.ai_verdict, w.name AS w_name
            FROM events e JOIN watchers w ON w.id = e.watcher_id
            WHERE e.ai_verdict IN ('GO', 'UNCLEAR') AND e.ai_claim IS NOT NULL AND e.ai_claim != ''
              AND e.watcher_id != ? AND e.id != ? AND e.received_at >= ?
            ORDER BY e.id DESC
            LIMIT ?
            """,
            (row["watcher_id"], row["id"], cutoff, CORROBORATE_CANDIDATES),
        ).fetchall()
        c.close()
        for candidate in candidates:
            stats["checked"] += 1
            try:
                matched, why = await same_claim(row["ai_claim"], candidate["ai_claim"])
            except QuotaExceeded as exc:
                log.warning("corroboration quota exceeded, deferring: %s", exc)
                return stats
            except Exception as exc:
                stats["errors"] += 1
                log.warning("corroboration error event_id=%s vs %s: %s", row["id"], candidate["id"], exc)
                continue
            if not matched:
                continue
            source = candidate["w_name"] or candidate["id"]
            if _promote(conn_factory, row["id"], f"corroborated by event {candidate['id']} ({source}): {why}"):
                stats["promoted"] += 1
                resolved.add(row["id"])
            if candidate["ai_verdict"] == "UNCLEAR" and _promote(
                conn_factory, candidate["id"], f"corroborated by event {row['id']} ({row['w_name']}): {why}"
            ):
                stats["promoted"] += 1
                resolved.add(candidate["id"])
            break
    return stats


async def run_forever(conn_factory) -> None:
    log.info(
        "judge starting model=%s ollama=%s interval=%ss batch=%s corroborate=%s window=%sh",
        OLLAMA_MODEL, OLLAMA_URL, JUDGE_INTERVAL, JUDGE_BATCH, CORROBORATE, CORROBORATE_WINDOW_HOURS,
    )
    while True:
        try:
            stats = await judge_pending(conn_factory)
            if stats["judged"] or stats["errors"]:
                log.info("judge done %s", stats)
            corroboration = await corroborate_pending(conn_factory)
            if corroboration["promoted"] or corroboration["errors"]:
                log.info("corroboration done %s", corroboration)
        except Exception as exc:
            log.exception("judge loop error: %s", exc)
        await asyncio.sleep(JUDGE_INTERVAL)
