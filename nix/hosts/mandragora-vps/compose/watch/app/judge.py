import asyncio
import json
import logging
import os
import re
from datetime import datetime, timedelta, timezone
from difflib import SequenceMatcher
from html.parser import HTMLParser
from typing import Any

import httpx

log = logging.getLogger("watch.judge")

OLLAMA_URL = os.environ.get("WATCH_OLLAMA_URL", "http://100.115.80.79:11434").rstrip("/")
OLLAMA_MODEL = os.environ.get("WATCH_OLLAMA_MODEL", "qwen3:14b").strip()
OLLAMA_TIMEOUT = float(os.environ.get("WATCH_OLLAMA_TIMEOUT", "180"))
OLLAMA_NUM_CTX = int(os.environ.get("WATCH_OLLAMA_NUM_CTX", "16384"))
OLLAMA_KEEP_ALIVE = os.environ.get("WATCH_OLLAMA_KEEP_ALIVE", "60s").strip()
FALLBACK_URL = os.environ.get("WATCH_JUDGE_FALLBACK_URL", "").strip().rstrip("/")
FALLBACK_MODEL = os.environ.get("WATCH_JUDGE_FALLBACK_MODEL", "deepseek-chat").strip()
FALLBACK_KEY = os.environ.get("WATCH_JUDGE_FALLBACK_KEY", "").strip()
FALLBACK_TIMEOUT = float(os.environ.get("WATCH_JUDGE_FALLBACK_TIMEOUT", "120"))
DEADLINE_HOURS = int(os.environ.get("WATCH_JUDGE_DEADLINE_HOURS", "24"))
STALL_HOURS = float(os.environ.get("WATCH_JUDGE_STALL_HOURS", "1"))
SWEEP_BATCH = int(os.environ.get("WATCH_JUDGE_SWEEP_BATCH", "20"))
JUDGE_ENABLED = os.environ.get("WATCH_JUDGE_ENABLED", "0").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
}
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
SPEC_LINT_BATCH = int(os.environ.get("WATCH_SPEC_LINT_BATCH", "2"))

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
    "UPDATE events SET ai_verdict = ?, ai_reason = ?, ai_claim = ?, ai_subject = ?, ai_incident = ?, "
    "ai_judged_at = ?, ai_claimed_at = NULL "
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
    "The claim field is one plain sentence naming exactly what is asserted. Omit outlet "
    "names, dates, and adjectives. Use an empty string when the verdict is NO.\n\n"
    "The subject field names the specific product, project or system the claim is about, "
    "lowercase, no version numbers, no outlet names — for example 'electrum bitcoin wallet' "
    "or 'claude code'. Always use the same wording for the same subject so independent "
    "reports about one product agree. Use an empty string when the verdict is NO.\n\n"
    "The incident field classifies what happened, chosen from: "
    "vulnerability, exploit, phishing, supply-chain, malware, outage, release, "
    "announcement, other.\n\n"
    "Hard rules:\n"
    "1. If the spec lists concrete constraints (model number, firmware range, version, "
    "platform) and the content does not positively assert each one, return NO.\n"
    "2. Do not infer, do not assume, do not give benefit of the doubt.\n"
    "3. If link content is empty or fetch failed, fall back to title+summary only; if "
    "those also do not positively assert each required field, return NO.\n"
    "4. Reason must cite which required field matched or which is missing/mismatched. "
    "Never invent facts not present in the provided text."
)


INCIDENT_KINDS = [
    "vulnerability",
    "exploit",
    "phishing",
    "supply-chain",
    "malware",
    "outage",
    "release",
    "announcement",
    "other",
]

INCIDENT_FAMILIES = {
    "security": ("vulnerability", "exploit", "phishing", "supply-chain", "malware"),
    "availability": ("outage",),
    "shipping": ("release", "announcement"),
    "other": ("other",),
}


def incident_family(incident: str) -> str:
    for family, members in INCIDENT_FAMILIES.items():
        if incident in members:
            return family
    return "other"


SUBJECT_MIN_TOKENS = 2
SUBJECT_MIN_SINGLE_TOKEN = 8

_SUBJECT_NOISE_RE = re.compile(r"[^a-z0-9]+")


def normalize_subject(subject: str) -> str:
    return _SUBJECT_NOISE_RE.sub(" ", (subject or "").lower()).strip()


def subjects_match(left: str, right: str) -> bool:
    if not left or not right:
        return False
    if left == right:
        return True
    left_tokens, right_tokens = set(left.split()), set(right.split())
    smaller, larger = sorted((left_tokens, right_tokens), key=len)
    if not smaller or not smaller.issubset(larger):
        return False
    if len(smaller) >= SUBJECT_MIN_TOKENS:
        return True
    return len(next(iter(smaller))) >= SUBJECT_MIN_SINGLE_TOKEN


SPEC_LINT_PROMPT = (
    "You audit notification filters. A user wrote a spec describing what they want to be "
    "notified about, attached to one source. You are told exactly what material the judge "
    "will hold when it applies that spec. Decide whether a careful reader holding that "
    "material could reach a definite yes or no, without guessing.\n\n"
    "Return ONLY a single line of JSON: "
    '{"decidable":true|false,"problems":["<=100 chars each"],"suggestion":"<=300 chars"}\n\n'
    "The judge always fetches and reads the page behind an item's link. Article bodies, "
    "release notes and linked announcements are therefore part of the material. NEVER call "
    "a spec undecidable because the answer lives in the article body rather than the title "
    "or headline -- that body is available.\n"
    "decidable is false only when: the spec turns on facts no published source carries "
    "(private, internal or unpublished information); its terms are subjective with no "
    "stated test (\"important\", \"interesting\", \"a big deal\"); or this source is about a "
    "wholly different subject, so no item it ever returns could bear on the spec.\n"
    "decidable is true when a typical item from this source, read together with the page it "
    "links to, could settle the spec either way -- even if most items are rejected, even if "
    "matching items are rare, and even if the source is a broad search that returns mostly "
    "noise. Rare is not undecidable.\n"
    "suggestion rewrites the spec so it is decidable, preserving the user's intent, and must "
    "differ from the spec. Leave suggestion empty when decidable is true."
)

SUGGESTION_ECHO_RATIO = 0.75
SUGGESTION_ECHO_HEAD = 60
SPEC_LINT_VERSION = 2

SPEC_LINT_SCHEMA = {
    "type": "object",
    "properties": {
        "decidable": {"type": "boolean"},
        "problems": {"type": "array", "items": {"type": "string"}},
        "suggestion": {"type": "string"},
    },
    "required": ["decidable", "problems", "suggestion"],
}

SOURCE_EMITS = {
    "github_user": "public activity events for one GitHub account: pushes, stars, forks, issue and PR openings, with repo names and short payload text",
    "github_repo": "commits on one GitHub repository: message, author, timestamp",
    "github_release": "GitHub release entries: tag, release title, and the full release-notes body",
    "reddit_user": "one Reddit account's posts and comments: title and body text",
    "reddit_sub": "posts from one subreddit: title, selftext, and the full text of the page the post links to",
    "youtube_channel": "video entries from one channel: title and description only, never the spoken content",
    "twitch_stream": "live/offline transitions for one streamer: stream title and game name only",
    "hn_search": "Hacker News search hits: story title and points, plus the full text of the page the story links to",
    "reddit_search": "Reddit search hits across subreddits: post title, subreddit, and the full text of the page the post links to",
    "rss": "feed entries: headline, summary or excerpt, plus the full text of the page the entry links to",
    "tvmaze_season": "structured season status from TVmaze: whether the season is listed, its episode order, and its premiere date — a fact table, never prose",
}


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


def _parse_verdict_json(text: str) -> dict[str, str]:
    parsed = _parse_json_object(text)
    verdict = str(parsed.get("verdict", "")).upper().strip()
    if verdict not in VERDICTS:
        raise RuntimeError(f"bad verdict: {verdict!r}")
    incident = str(parsed.get("incident", "") or "").lower().strip()
    return {
        "verdict": verdict,
        "reason": str(parsed.get("reason", ""))[:500],
        "claim": str(parsed.get("claim", "") or "")[:300],
        "subject": normalize_subject(str(parsed.get("subject", "") or ""))[:200],
        "incident": incident if incident in INCIDENT_KINDS else "other",
    }


async def _generate(system: str, prompt: str, schema: dict, num_predict: int = 512) -> str:
    try:
        return await _generate_ollama(system, prompt, schema, num_predict)
    except (httpx.ConnectError, httpx.ConnectTimeout, httpx.ReadTimeout) as exc:
        if not (FALLBACK_URL and FALLBACK_KEY):
            raise
        log.warning("ollama unreachable (%s), falling back to %s", exc, FALLBACK_MODEL)
        return await _generate_fallback(system, prompt, num_predict)


async def _generate_fallback(system: str, prompt: str, num_predict: int) -> str:
    payload = {
        "model": FALLBACK_MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.0,
        "max_tokens": num_predict,
        "response_format": {"type": "json_object"},
        "stream": False,
    }
    async with httpx.AsyncClient(timeout=FALLBACK_TIMEOUT) as c:
        r = await c.post(
            f"{FALLBACK_URL}/chat/completions",
            json=payload,
            headers={"Authorization": f"Bearer {FALLBACK_KEY}"},
        )
    if r.status_code >= 400:
        body = r.text[:300]
        if r.status_code == 429 or any(sig in body.lower() for sig in QUOTA_SIGNALS):
            raise QuotaExceeded(f"fallback http {r.status_code}: {body}")
        raise RuntimeError(f"fallback http {r.status_code}: {body}")
    doc = r.json()
    choices = doc.get("choices") or []
    text = (choices[0].get("message", {}).get("content") if choices else "") or ""
    if not text:
        raise RuntimeError(f"fallback empty response: {json.dumps(doc)[:200]}")
    return text


async def _generate_ollama(system: str, prompt: str, schema: dict, num_predict: int) -> str:
    payload = {
        "model": OLLAMA_MODEL,
        "system": system,
        "prompt": prompt,
        "stream": False,
        "format": schema,
        "keep_alive": OLLAMA_KEEP_ALIVE,
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
        "subject": {"type": "string"},
        "incident": {"type": "string", "enum": INCIDENT_KINDS},
    },
    "required": ["verdict", "reason", "claim", "subject", "incident"],
}


SUBJECT_STOPWORDS = {
    "the", "and", "for", "with", "app", "apps", "tool", "tools", "software",
    "client", "clients", "service", "project", "platform", "system", "systems",
}


def subject_terms(subject: str) -> list[str]:
    return [
        term
        for term in re.findall(r"[a-z0-9][a-z0-9.+_-]{2,}", (subject or "").lower())
        if term not in SUBJECT_STOPWORDS
    ]


def ungrounded_terms(subject: str, *texts: str) -> list[str]:
    terms = subject_terms(subject)
    if not terms:
        return []
    haystack = " ".join(t for t in texts if t).lower()
    return [term for term in terms if term not in haystack]


def required_terms(event: dict[str, Any]) -> list[str]:
    raw = str(event.get("w_must_mention") or "")
    return [t.strip().lower() for t in re.split(r"[,\s]+", raw) if t.strip()]


def ground_verdict(
    judgement: dict[str, str], event: dict[str, Any], link_text: str = ""
) -> dict[str, str]:
    if judgement.get("verdict") == "NO":
        return judgement
    texts = (
        str(event.get("title") or ""),
        str(event.get("summary") or ""),
        link_text or "",
    )
    haystack = " ".join(t for t in texts if t).lower()
    required = required_terms(event)
    if required:
        missing = [t for t in required if t not in haystack]
    else:
        missing = ungrounded_terms(judgement.get("subject", ""), *texts)
    if not missing:
        return judgement
    return {**judgement, **refusal(missing)}


def refusal(missing: list[str]) -> dict[str, str]:
    return {
        "verdict": "NO",
        "reason": (
            "subject is not named in the source: "
            + ", ".join(missing)
            + " absent from the title, summary and fetched text"
        )[:500],
        "claim": "",
        "subject": "",
        "incident": "other",
    }


async def judge_event(ai_spec: str, event: dict[str, Any]) -> dict[str, str]:
    link_text, fetch_err = await fetch_link(event.get("link") or "")
    required = required_terms(event)
    if required:
        haystack = " ".join(
            t
            for t in (
                str(event.get("title") or ""),
                str(event.get("summary") or ""),
                link_text or "",
            )
            if t
        ).lower()
        missing = [t for t in required if t not in haystack]
        if missing:
            return refusal(missing)
    text = await _generate(
        SYSTEM_PROMPT,
        build_user_prompt(ai_spec, event, link_text, fetch_err),
        VERDICT_SCHEMA,
    )
    return ground_verdict(_parse_verdict_json(text), event, link_text)


def _normalize_for_echo(text: str) -> str:
    return re.sub(r"[^a-z0-9 ]+", " ", re.sub(r"\s+", " ", text.lower())).strip()


def echoes_spec(suggestion: str, spec: str) -> bool:
    a, b = _normalize_for_echo(suggestion), _normalize_for_echo(spec)
    if not a:
        return True
    head = min(len(a), len(b), SUGGESTION_ECHO_HEAD)
    if head and (a[:head] == b[:head] or a in b or b in a):
        return True
    return SequenceMatcher(None, a, b).ratio() >= SUGGESTION_ECHO_RATIO


async def lint_spec(kind: str, target: str, spec: str) -> dict:
    emits = SOURCE_EMITS.get(kind, "a title, a summary, and the full text of the page the item links to")
    prompt = (
        f"SOURCE KIND: {kind}\n"
        f"SOURCE TARGET: {target}\n"
        f"MATERIAL THE JUDGE WILL HOLD: {emits}\n\n"
        f"SPEC:\n{spec}\n"
    )
    text = await _generate(SPEC_LINT_PROMPT, prompt, SPEC_LINT_SCHEMA, num_predict=400)
    parsed = _parse_json_object(text)
    decidable = bool(parsed.get("decidable"))
    problems = [str(p)[:100] for p in (parsed.get("problems") or [])][:5]
    suggestion = str(parsed.get("suggestion", "") or "")[:300]
    if decidable or echoes_spec(suggestion, spec):
        suggestion = ""
    return {
        "version": SPEC_LINT_VERSION,
        "decidable": decidable,
        "problems": [] if decidable else problems,
        "suggestion": suggestion,
    }


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


def _write_verdict(conn_factory, event_id: int, judgement: dict[str, str]) -> bool:
    c = conn_factory()
    try:
        cur = c.execute(
            WRITE_VERDICT_SQL,
            (
                judgement["verdict"],
                judgement.get("reason", "")[:500],
                judgement.get("claim") or None,
                judgement.get("subject") or None,
                judgement.get("incident") or None,
                _now_iso(),
                event_id,
            ),
        )
        return cur.rowcount == 1
    finally:
        c.close()


async def judge_pending(conn_factory) -> dict[str, int]:
    stats = {"judged": 0, "go": 0, "unclear": 0, "no": 0, "errors": 0, "skipped": 0}
    c = conn_factory()
    rows = c.execute(
        """
        SELECT e.id AS id, e.title, e.summary, e.link, e.occurred_at, e.external_id,
               w.ai_spec AS w_spec, w.kind AS w_kind, w.target AS w_target,
               w.must_mention AS w_must_mention
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
            judgement = await judge_event(r["w_spec"], dict(r))
        except QuotaExceeded as exc:
            _release_claim(conn_factory, r["id"])
            log.warning("judge quota exceeded, deferring batch: %s", exc)
            break
        except Exception as exc:
            _release_claim(conn_factory, r["id"])
            stats["errors"] += 1
            log.warning("judge error event_id=%s: %s", r["id"], exc)
            continue
        if not _write_verdict(conn_factory, r["id"], judgement):
            stats["skipped"] += 1
            continue
        stats["judged"] += 1
        verdict = judgement["verdict"].lower()
        stats[verdict] = stats.get(verdict, 0) + 1
    return stats


def _deadline_cutoff_iso() -> str:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=DEADLINE_HOURS)
    return cutoff.isoformat(timespec="seconds").replace("+00:00", "Z")


ESCALATE_SQL = (
    "UPDATE events SET escalated_at = ?, ai_reason = ? "
    "WHERE id = ? AND ai_verdict IS NULL AND escalated_at IS NULL"
)


async def deterministic_disposition(event: dict[str, Any]) -> tuple[str, str]:
    required = required_terms(event)
    if not required:
        return "escalate", f"unjudged after {DEADLINE_HOURS}h; no literal gate on this watcher"
    def _missing(*texts: str) -> list[str]:
        haystack = " ".join(t for t in texts if t).lower()
        return [t for t in required if t not in haystack]
    title = str(event.get("title") or "")
    summary = str(event.get("summary") or "")
    if not _missing(title, summary):
        return "escalate", f"unjudged after {DEADLINE_HOURS}h; required terms present in the source"
    link_text, _ = await fetch_link(event.get("link") or "")
    missing = _missing(title, summary, link_text)
    if not missing:
        return "escalate", f"unjudged after {DEADLINE_HOURS}h; required terms present in the source"
    return "reject", refusal(missing)["reason"]


def judge_is_progressing(conn_factory) -> bool:
    if not JUDGE_ENABLED:
        return False
    c = conn_factory()
    try:
        row = c.execute("SELECT MAX(ai_judged_at) AS t FROM events").fetchone()
    finally:
        c.close()
    last = row["t"] if row else None
    if not last:
        return False
    cutoff = datetime.now(timezone.utc) - timedelta(hours=STALL_HOURS)
    return str(last) >= cutoff.isoformat(timespec="seconds").replace("+00:00", "Z")


async def sweep_deadline(conn_factory) -> dict[str, int]:
    stats = {"escalated": 0, "rejected": 0, "errors": 0}
    if DEADLINE_HOURS <= 0:
        return stats
    if judge_is_progressing(conn_factory):
        return stats
    c = conn_factory()
    rows = c.execute(
        """
        SELECT e.id AS id, e.title, e.summary, e.link,
               w.must_mention AS w_must_mention
        FROM events e JOIN watchers w ON w.id = e.watcher_id
        WHERE e.ai_verdict IS NULL AND e.escalated_at IS NULL
          AND w.ai_spec IS NOT NULL AND w.enabled = 1
          AND e.received_at < ?
        ORDER BY e.id ASC
        LIMIT ?
        """,
        (_deadline_cutoff_iso(), SWEEP_BATCH),
    ).fetchall()
    c.close()
    for r in rows:
        try:
            action, reason = await deterministic_disposition(dict(r))
        except Exception as exc:
            stats["errors"] += 1
            log.warning("deadline sweep error event_id=%s: %s", r["id"], exc)
            continue
        c = conn_factory()
        try:
            if action == "escalate":
                c.execute(ESCALATE_SQL, (_now_iso(), reason[:500], r["id"]))
                stats["escalated"] += 1
            else:
                c.execute(
                    WRITE_VERDICT_SQL,
                    ("NO", reason[:500], None, None, "other", _now_iso(), r["id"]),
                )
                stats["rejected"] += 1
        finally:
            c.close()
    return stats


def lint_is_stale(spec_lint_at: str | None, spec_lint: str | None) -> bool:
    if not spec_lint_at:
        return True
    try:
        stored = json.loads(spec_lint or "{}")
    except (TypeError, ValueError):
        return True
    return stored.get("version") != SPEC_LINT_VERSION


async def lint_pending_specs(conn_factory) -> dict[str, int]:
    stats = {"linted": 0, "undecidable": 0, "errors": 0}
    c = conn_factory()
    candidates = c.execute(
        "SELECT id, kind, target, ai_spec, spec_lint, spec_lint_at FROM watchers "
        "WHERE enabled = 1 AND ai_spec IS NOT NULL AND ai_spec != '' "
        "ORDER BY id DESC"
    ).fetchall()
    c.close()
    rows = [r for r in candidates if lint_is_stale(r["spec_lint_at"], r["spec_lint"])][:SPEC_LINT_BATCH]
    for row in rows:
        try:
            result = await lint_spec(row["kind"], row["target"], row["ai_spec"])
        except QuotaExceeded as exc:
            log.warning("spec lint quota exceeded, deferring: %s", exc)
            break
        except Exception as exc:
            stats["errors"] += 1
            log.warning("spec lint error watcher_id=%s: %s", row["id"], exc)
            continue
        c = conn_factory()
        c.execute(
            "UPDATE watchers SET spec_lint = ?, spec_lint_at = ? WHERE id = ?",
            (json.dumps(result), _now_iso(), row["id"]),
        )
        c.close()
        stats["linted"] += 1
        if not result["decidable"]:
            stats["undecidable"] += 1
            log.warning(
                "watcher %s spec is undecidable against %s: %s",
                row["id"], row["kind"], "; ".join(result["problems"]) or "no detail",
            )
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


def corroborate_pending(conn_factory) -> dict[str, int]:
    stats = {"checked": 0, "promoted": 0, "errors": 0}
    if not CORROBORATE:
        return stats
    cutoff = _corroboration_cutoff_iso()
    c = conn_factory()
    unclear = c.execute(
        """
        SELECT e.id, e.watcher_id, e.ai_subject, e.ai_incident, w.name AS w_name
        FROM events e JOIN watchers w ON w.id = e.watcher_id
        WHERE e.ai_verdict = 'UNCLEAR' AND e.ai_subject IS NOT NULL AND e.ai_subject != ''
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
        family = incident_family(row["ai_incident"] or "other")
        members = INCIDENT_FAMILIES[family]
        c = conn_factory()
        candidates = c.execute(
            f"""
            SELECT e.id, e.ai_subject, e.ai_verdict, e.ai_incident, w.name AS w_name
            FROM events e JOIN watchers w ON w.id = e.watcher_id
            WHERE e.ai_verdict IN ('GO', 'UNCLEAR') AND e.ai_subject IS NOT NULL AND e.ai_subject != ''
              AND e.ai_incident IN ({','.join('?' * len(members))})
              AND e.watcher_id != ? AND e.id != ? AND e.received_at >= ?
            ORDER BY e.id DESC
            LIMIT ?
            """,
            (*members, row["watcher_id"], row["id"], cutoff, CORROBORATE_CANDIDATES),
        ).fetchall()
        c.close()
        for candidate in candidates:
            stats["checked"] += 1
            if not subjects_match(row["ai_subject"], candidate["ai_subject"]):
                continue
            agreement = f"{family} report on {row['ai_subject']}"
            source = candidate["w_name"] or candidate["id"]
            if _promote(conn_factory, row["id"], f"corroborated by event {candidate['id']} ({source}): {agreement}"):
                stats["promoted"] += 1
                resolved.add(row["id"])
            if candidate["ai_verdict"] == "UNCLEAR" and _promote(
                conn_factory, candidate["id"], f"corroborated by event {row['id']} ({row['w_name']}): {agreement}"
            ):
                stats["promoted"] += 1
                resolved.add(candidate["id"])
            break
    return stats


async def run_forever(conn_factory) -> None:
    if JUDGE_ENABLED:
        log.info(
            "judge starting model=%s ollama=%s keep_alive=%s fallback=%s interval=%ss batch=%s "
            "corroborate=%s window=%sh deadline=%sh",
            OLLAMA_MODEL, OLLAMA_URL, OLLAMA_KEEP_ALIVE, FALLBACK_MODEL if FALLBACK_KEY else "none",
            JUDGE_INTERVAL, JUDGE_BATCH, CORROBORATE, CORROBORATE_WINDOW_HOURS, DEADLINE_HOURS,
        )
    else:
        log.info(
            "judge model loop disabled (WATCH_JUDGE_ENABLED unset); deterministic deadline sweep "
            "still runs, escalating unjudged events after %sh",
            DEADLINE_HOURS,
        )
    while True:
        try:
            if JUDGE_ENABLED:
                stats = await judge_pending(conn_factory)
                if stats["judged"] or stats["errors"]:
                    log.info("judge done %s", stats)
                corroboration = corroborate_pending(conn_factory)
                if corroboration["promoted"] or corroboration["errors"]:
                    log.info("corroboration done %s", corroboration)
                lint = await lint_pending_specs(conn_factory)
                if lint["linted"] or lint["errors"]:
                    log.info("spec lint done %s", lint)
            sweep = await sweep_deadline(conn_factory)
            if sweep["escalated"] or sweep["rejected"] or sweep["errors"]:
                log.info("deadline sweep %s", sweep)
        except Exception as exc:
            log.exception("judge loop error: %s", exc)
        await asyncio.sleep(JUDGE_INTERVAL)
