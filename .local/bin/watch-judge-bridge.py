#!/usr/bin/env python3
import datetime
import json
import logging
import os
import re
import subprocess
import sys
import textwrap

VPS = os.environ.get("WATCH_JUDGE_VPS", "opc@mandragora-vps")
MODEL = os.environ.get("WATCH_JUDGE_MODEL", "gemini-2.5-flash")
LIMIT = int(os.environ.get("WATCH_JUDGE_LIMIT", "10"))
TIMEOUT = int(os.environ.get("WATCH_JUDGE_TIMEOUT", "60"))
CLAIM_TTL = int(os.environ.get("WATCH_JUDGE_CLAIM_TTL", "900"))
BUSY_TIMEOUT_MS = int(os.environ.get("WATCH_BUSY_TIMEOUT_MS", "5000"))


def now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def stale_cutoff_iso() -> str:
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=CLAIM_TTL)
    return cutoff.isoformat(timespec="seconds").replace("+00:00", "Z")


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("watch-judge-bridge")

PROMPT_HEADER = textwrap.dedent(
    """\
    You are a strict relevance judge for a notification pipeline.
    Output ONLY one line of JSON, no markdown, no prose, no code fence:
    {"verdict":"GO|MAYBE|NO","reason":"<=200 chars"}

    Definitions:
    - GO: the event clearly satisfies the spec right now (e.g. a working exploit/release for the exact device + firmware range the spec asks about).
    - MAYBE: the event is on-topic but unclear whether it actually delivers what the spec asks for (partial info, ambiguous firmware version, dev preview, theoretical).
    - NO: off-topic, different device/firmware, speculation, news about other models, unrelated jailbreak/news.

    Bias toward NO when unsure. Reason must cite the concrete signal that drove the verdict (version number, device name, missing detail). Never invent facts not in the event.
    """
)


def remote_python(script: str) -> str:
    """Run a python snippet inside the watch container via SSH+docker exec. Returns stdout."""
    cmd = ["ssh", VPS, "docker", "exec", "-i", "watch", "python", "-"]
    res = subprocess.run(cmd, input=script, capture_output=True, text=True, timeout=30)
    if res.returncode != 0:
        raise RuntimeError(f"remote python failed: {res.stderr.strip()}")
    return res.stdout


def fetch_pending() -> list[dict]:
    payload = json.dumps({"stale": stale_cutoff_iso(), "limit": LIMIT, "busy": BUSY_TIMEOUT_MS})
    script = textwrap.dedent(
        f"""\
        import sqlite3, json
        a = json.loads({payload!r})
        c = sqlite3.connect("/data/watch.db"); c.row_factory = sqlite3.Row
        c.execute("PRAGMA busy_timeout=%d" % a["busy"])
        rows = c.execute(
            "SELECT e.id AS id, e.title AS title, e.summary AS summary, e.link AS link, "
            "e.occurred_at AS occurred_at, w.kind AS kind, w.target AS target, w.ai_spec AS ai_spec "
            "FROM events e JOIN watchers w ON w.id = e.watcher_id "
            "WHERE e.ai_verdict IS NULL AND w.ai_spec IS NOT NULL AND w.enabled = 1 "
            "AND (e.ai_claimed_at IS NULL OR e.ai_claimed_at < ?) "
            "ORDER BY e.id DESC LIMIT ?",
            (a["stale"], a["limit"]),
        ).fetchall()
        print(json.dumps([dict(r) for r in rows]))
        """
    )
    out = remote_python(script)
    return json.loads(out or "[]")


def claim_event(event_id: int) -> bool:
    payload = json.dumps({"id": event_id, "now": now_iso(), "stale": stale_cutoff_iso(), "busy": BUSY_TIMEOUT_MS})
    script = textwrap.dedent(
        f"""\
        import sqlite3, json
        a = json.loads({payload!r})
        c = sqlite3.connect("/data/watch.db")
        c.execute("PRAGMA busy_timeout=%d" % a["busy"])
        cur = c.execute(
            "UPDATE events SET ai_claimed_at = ? "
            "WHERE id = ? AND ai_verdict IS NULL AND (ai_claimed_at IS NULL OR ai_claimed_at < ?)",
            (a["now"], a["id"], a["stale"]),
        )
        c.commit()
        print(cur.rowcount)
        c.close()
        """
    )
    out = remote_python(script)
    return out.strip() == "1"


def write_verdict(event_id: int, verdict: str, reason: str) -> bool:
    payload = json.dumps({"id": event_id, "verdict": verdict, "reason": reason[:500], "now": now_iso(), "busy": BUSY_TIMEOUT_MS})
    script = textwrap.dedent(
        f"""\
        import sqlite3, json
        p = json.loads({payload!r})
        c = sqlite3.connect("/data/watch.db")
        c.execute("PRAGMA busy_timeout=%d" % p["busy"])
        cur = c.execute(
            "UPDATE events SET ai_verdict = ?, ai_reason = ?, ai_judged_at = ?, ai_claimed_at = NULL "
            "WHERE id = ? AND ai_verdict IS NULL",
            (p["verdict"], p["reason"], p["now"], p["id"]),
        )
        c.commit()
        print(cur.rowcount)
        c.close()
        """
    )
    out = remote_python(script)
    return out.strip() == "1"


def release_claim(event_id: int) -> bool:
    payload = json.dumps({"id": event_id, "busy": BUSY_TIMEOUT_MS})
    script = textwrap.dedent(
        f"""\
        import sqlite3, json
        p = json.loads({payload!r})
        c = sqlite3.connect("/data/watch.db")
        c.execute("PRAGMA busy_timeout=%d" % p["busy"])
        cur = c.execute(
            "UPDATE events SET ai_claimed_at = NULL "
            "WHERE id = ? AND ai_verdict IS NULL",
            (p["id"],),
        )
        c.commit()
        print(cur.rowcount)
        c.close()
        """
    )
    out = remote_python(script)
    return out.strip() == "1"


def build_prompt(ev: dict) -> str:
    spec = ev.get("ai_spec") or ""
    return (
        PROMPT_HEADER
        + "\nSPEC:\n"
        + spec
        + "\n\nEVENT:\n"
        + f"source: {ev.get('kind')}:{ev.get('target')}\n"
        + f"title: {ev.get('title') or ''}\n"
        + f"summary: {(ev.get('summary') or '')[:1500]}\n"
        + f"link: {ev.get('link') or ''}\n"
        + f"occurred_at: {ev.get('occurred_at') or ''}\n"
    )


JSON_RE = re.compile(r"\{[^{}]*\"verdict\"[^{}]*\}", re.DOTALL)


def call_gemini(prompt: str) -> tuple[str, str]:
    res = subprocess.run(
        ["gemini", "-p", prompt, "-m", MODEL],
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
    )
    if res.returncode != 0:
        stderr = res.stderr.lower()
        if "quota" in stderr or "rate limit" in stderr or "429" in stderr or "resource_exhausted" in stderr:
            raise QuotaExceeded(res.stderr.strip())
        raise RuntimeError(f"gemini exit {res.returncode}: {res.stderr.strip()[:300]}")
    out = res.stdout
    m = JSON_RE.search(out)
    if not m:
        raise RuntimeError(f"no JSON in gemini output: {out[:200]}")
    try:
        doc = json.loads(m.group(0))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"json parse: {exc} {m.group(0)[:200]}")
    verdict = str(doc.get("verdict", "")).upper()
    reason = str(doc.get("reason", ""))[:500]
    if verdict not in {"GO", "MAYBE", "NO"}:
        raise RuntimeError(f"bad verdict: {verdict!r}")
    return verdict, reason


class QuotaExceeded(RuntimeError):
    pass


def main() -> int:
    try:
        queue = fetch_pending()
    except Exception as exc:
        log.error("fetch failed: %s", exc)
        return 1
    if not queue:
        log.info("nothing pending")
        return 0
    log.info("judging %d events", len(queue))
    judged = 0
    skipped = 0
    for ev in queue:
        try:
            if not claim_event(ev["id"]):
                skipped += 1
                continue
        except Exception as exc:
            log.warning("claim failed id=%s: %s", ev["id"], exc)
            continue
        try:
            verdict, reason = call_gemini(build_prompt(ev))
        except QuotaExceeded as exc:
            try:
                release_claim(ev["id"])
            except Exception as rel_exc:
                log.warning("claim release failed id=%s: %s", ev["id"], rel_exc)
            log.warning("quota exceeded, deferring %d remaining: %s", len(queue) - judged, exc)
            return 0
        except Exception as exc:
            log.warning("judge error id=%s: %s", ev["id"], exc)
            continue
        try:
            wrote = write_verdict(ev["id"], verdict, reason)
        except Exception as exc:
            log.error("write-back failed id=%s: %s", ev["id"], exc)
            continue
        if not wrote:
            skipped += 1
            log.info("id=%s already judged by another writer, dropping verdict", ev["id"])
            continue
        log.info("id=%s verdict=%s reason=%s", ev["id"], verdict, reason)
        judged += 1
    log.info("done, judged=%d skipped=%d", judged, skipped)
    return 0


if __name__ == "__main__":
    sys.exit(main())
