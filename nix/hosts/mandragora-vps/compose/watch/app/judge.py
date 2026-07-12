import asyncio
import json
import logging
import os
import re
from datetime import datetime, timezone
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
LINK_MAX_CHARS = int(os.environ.get("WATCH_LINK_MAX_CHARS", "8000"))
LINK_TIMEOUT = float(os.environ.get("WATCH_LINK_TIMEOUT", "20"))
USER_AGENT = os.environ.get(
    "WATCH_USER_AGENT",
    "mandragora-watch/0.1 (+https://watch.mvr.ac)",
)

VERDICTS = {"GO", "MAYBE", "NO"}

QUOTA_SIGNALS = ("quota", "rate limit", "rate-limit", "resource_exhausted", "too many requests")


class QuotaExceeded(RuntimeError):
    pass


SYSTEM_PROMPT = (
    "You are a strict relevance judge for a notification pipeline. "
    "Given a target spec (what the user actually cares about), a candidate event, "
    "and the fetched text content at the event's link, decide whether the event is a "
    "genuine match for the spec.\n\n"
    "Return ONLY a single line of JSON, no markdown, no prose, no <think> tags:\n"
    '{"verdict":"GO|MAYBE|NO","reason":"<=200 chars"}\n\n'
    "Definitions:\n"
    "- GO: the link content clearly satisfies EVERY explicit requirement in the spec "
    "(e.g. correct device generation AND firmware range AND a working release/exploit). "
    "Quote the matched fields in the reason.\n"
    "- MAYBE: link content positively evidences every explicit spec requirement, but "
    "deliverability is unclear (e.g. dev preview asserts correct device+firmware with no "
    "artifact yet).\n"
    "- NO: off-topic, wrong device/firmware/version, speculation, OR the link content "
    "fails to positively assert any explicit spec requirement. Missing required info is "
    "NO, not MAYBE. A notification the user has to hand-verify is a failed filter.\n\n"
    "Hard rules:\n"
    "1. If the spec lists concrete constraints (model number, firmware range, version, "
    "platform) and the content does not positively assert each one, return NO.\n"
    "2. Do not infer, do not assume, do not give benefit of the doubt.\n"
    "3. If link content is empty or fetch failed, fall back to title+summary only; if "
    "those also do not positively assert each required field, return NO.\n"
    "4. Reason must cite which required field matched or which is missing/mismatched. "
    "Never invent facts not present in the provided text."
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


def _parse_verdict_json(text: str) -> tuple[str, str]:
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()
    raw = text
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        m = _JSON_OBJ_RE.search(raw)
        if not m:
            raise RuntimeError(f"no json object in response: {raw[:200]}")
        parsed = json.loads(m.group(0))
    verdict = str(parsed.get("verdict", "")).upper().strip()
    reason = str(parsed.get("reason", ""))[:500]
    if verdict not in VERDICTS:
        raise RuntimeError(f"bad verdict: {verdict!r}")
    return verdict, reason


async def judge_event(ai_spec: str, event: dict[str, Any]) -> tuple[str, str]:
    link_text, fetch_err = await fetch_link(event.get("link") or "")
    payload = {
        "model": OLLAMA_MODEL,
        "system": SYSTEM_PROMPT,
        "prompt": build_user_prompt(ai_spec, event, link_text, fetch_err),
        "stream": False,
        "format": {
            "type": "object",
            "properties": {
                "verdict": {"type": "string", "enum": ["GO", "MAYBE", "NO"]},
                "reason": {"type": "string"},
            },
            "required": ["verdict", "reason"],
        },
        "options": {
            "temperature": 0.0,
            "num_ctx": OLLAMA_NUM_CTX,
            "num_predict": 512,
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
    return _parse_verdict_json(text)


async def judge_pending(conn_factory) -> dict[str, int]:
    stats = {"judged": 0, "go": 0, "maybe": 0, "no": 0, "errors": 0}
    c = conn_factory()
    rows = c.execute(
        """
        SELECT e.id AS id, e.title, e.summary, e.link, e.occurred_at, e.external_id,
               w.ai_spec AS w_spec, w.kind AS w_kind, w.target AS w_target
        FROM events e JOIN watchers w ON w.id = e.watcher_id
        WHERE e.ai_verdict IS NULL AND w.ai_spec IS NOT NULL AND w.enabled = 1
        ORDER BY e.id ASC
        LIMIT ?
        """,
        (JUDGE_BATCH,),
    ).fetchall()
    c.close()
    for r in rows:
        try:
            verdict, reason = await judge_event(r["w_spec"], dict(r))
        except QuotaExceeded as exc:
            log.warning("judge quota exceeded, deferring batch: %s", exc)
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


async def run_forever(conn_factory) -> None:
    log.info(
        "judge starting model=%s ollama=%s interval=%ss batch=%s",
        OLLAMA_MODEL, OLLAMA_URL, JUDGE_INTERVAL, JUDGE_BATCH,
    )
    while True:
        try:
            stats = await judge_pending(conn_factory)
            if stats["judged"] or stats["errors"]:
                log.info("judge done %s", stats)
        except Exception as exc:
            log.exception("judge loop error: %s", exc)
        await asyncio.sleep(JUDGE_INTERVAL)
