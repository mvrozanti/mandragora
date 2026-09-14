import json
import logging
import os
import uuid

from datetime import datetime

import llm
import match as matcher
import sources

log = logging.getLogger("watch.compose")

PROBE_ITEMS = int(os.environ.get("WATCH_COMPOSE_PROBE_ITEMS", "12"))
COMPOSE_NUM_CTX = int(os.environ.get("WATCH_COMPOSE_NUM_CTX", "8192"))


SYSTEM_PROMPT = (
    "You turn one sentence into a set of sources for a feed-polling system to watch.\n\n"
    "Choose the FEWEST sources that can actually answer it. Prefer a source that states "
    "the answer as a fact over one that carries people talking about it: a TV season's "
    "release is tvmaze_season, a security advisory is github_advisory, whether a game runs "
    "on Linux is anticheat_game, a software release is github_release. Reach for search "
    "feeds or subreddits only when no fact source can answer, such as an exploit or a leak.\n\n"
    "Targets must be real and exact, in the format shown for that kind. If you are not sure "
    "an identifier exists, choose a search source instead of guessing one.\n\n"
    "For each source give `match`: a keyword rule that an item's text must satisfy before "
    "the user is told. Whitespace means AND; uppercase AND, OR and NOT are operators; "
    "\"quoted phrases\" match as a phrase; terms match on word boundaries. Leave it as an "
    "empty string when every item the source emits is worth sending.\n\n"
    "Keep rules SHORT, and never restate what the source already scopes. A Kindle "
    "jailbreak forum is already about Kindles, so the rule there is `jailbreak`, not "
    "`kindle AND jailbreak`. This matters: a rule of `paperwhite AND jailbreak` on such a "
    "forum was measured at 20% recall, because announcements name models as PW6 or KT5 and "
    "never contain the generic word you would have guessed. Every extra term you add can "
    "only lose signal.\n\n"
    "stop_after: 1 when the thing can only happen once — a season releasing, a specific "
    "version shipping, a device being jailbroken. 0 when it can recur.\n\n"
    "Return ONLY JSON:\n"
    '{"name":"<short label>","stop_after":0,'
    '"sources":[{"kind":"...","target":"...","match":"...","why":"<=80 chars"}]}'
)


def source_menu() -> str:
    lines = []
    for kind, meta in sources.SOURCE_KINDS.items():
        emits = sources.SOURCE_EMITS.get(kind, "")
        lines.append(f"- {kind} (target looks like: {meta.get('target_hint', '')})")
        lines.append(f"    emits: {emits}")
    return "\n".join(lines)


def interpret_prompt(text: str) -> str:
    return (
        "SOURCE KINDS YOU MAY USE:\n"
        f"{source_menu()}\n\n"
        "SENTENCE:\n"
        f"{text.strip()}\n"
    )


async def interpret(text: str) -> tuple[dict, str]:
    if not (text or "").strip():
        raise ValueError("say what you want to watch")
    raw, provider = await llm.complete(SYSTEM_PROMPT, interpret_prompt(text))
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError:
        a, b = raw.find("{"), raw.rfind("}")
        if a < 0 or b <= a:
            raise ValueError(f"model did not return a plan: {raw[:120]}")
        doc = json.loads(raw[a:b + 1])

    raw_sources = doc.get("sources") or []
    if not isinstance(raw_sources, list) or not raw_sources:
        raise ValueError("model proposed no sources")
    cleaned = []
    for item in raw_sources[:4]:
        if not isinstance(item, dict):
            continue
        kind = str(item.get("kind") or "").strip()
        target = str(item.get("target") or "").strip()
        if kind not in sources.SOURCE_KINDS or not target:
            continue
        cleaned.append({
            "kind": kind,
            "target": target,
            "match": str(item.get("match") or "").strip(),
            "why": str(item.get("why") or "").strip()[:200],
        })
    if not cleaned:
        offered = sorted({str(i.get("kind")) for i in raw_sources if isinstance(i, dict)})
        raise ValueError(
            "model proposed no source I recognise"
            + (f" (it suggested: {', '.join(offered)})" if offered else "")
        )
    try:
        stop_after = max(0, int(doc.get("stop_after") or 0))
    except (TypeError, ValueError):
        stop_after = 0
    plan = {
        "name": str(doc.get("name") or text.strip())[:120],
        "condition": text.strip(),
        "stop_after": stop_after,
        "sources": cleaned,
    }
    return plan, provider


def validate_plan(plan: dict) -> list[str]:
    problems = []
    for entry in plan["sources"]:
        rule = entry.get("match") or ""
        if rule:
            ok, err = matcher.is_valid(rule)
            if not ok:
                problems.append(f"{entry['kind']}: rule {rule!r} is not valid — {err}")
    return problems


def match_samples(entry: dict, probe: dict) -> list[dict]:
    rule = entry.get("match") or ""
    if not rule:
        return []
    out = []
    for sample in probe.get("samples", [])[:PROBE_ITEMS]:
        text = f"{sample['title']} {sample.get('summary', '')}"
        try:
            hit = matcher.matches(rule, text)
            why = matcher.explain(rule, text)
        except matcher.MatchError as exc:
            hit, why = False, str(exc)
        out.append({"title": sample["title"], "verdict": "MATCH" if hit else "no", "reason": why})
    return out


async def probe_source(entry: dict) -> dict:
    result = {**entry, "ok": False, "error": None, "resolved_target": None, "samples": []}
    try:
        target = sources.validate_target(entry["kind"], entry["target"])
    except ValueError as exc:
        result["error"] = f"not a usable target: {exc}"
        return result
    except Exception as exc:
        result["error"] = f"target lookup failed: {exc}"
        return result
    result["resolved_target"] = target
    try:
        exists, detail = await sources.target_exists(entry["kind"], target)
    except Exception as exc:
        exists, detail = True, f"could not verify {target}: {str(exc)[:80]}"
    if not exists:
        result["error"] = detail
        return result
    if detail:
        result["note"] = detail
    try:
        items, _ = await sources.fetch(entry["kind"], target, None)
    except Exception as exc:
        result["error"] = f"source unreachable: {str(exc)[:160]}"
        return result
    result["ok"] = True
    result["samples"] = [
        {"title": (it.get("title") or "")[:160], "link": it.get("link") or "",
         "summary": (it.get("summary") or "")[:2000],
         "occurred_at": it.get("occurred_at") or ""}
        for it in items[:PROBE_ITEMS]
    ]
    result["available"] = len(items)
    return result


async def preview(plan: dict) -> dict:
    warnings = validate_plan(plan)
    checked = []
    for entry in plan["sources"]:
        probe = await probe_source(entry)
        probe["judged"] = match_samples(entry, probe) if probe["ok"] else []
        if not probe["ok"]:
            warnings.append(f"{entry['kind']}:{entry['target']} — {probe['error']}")
        checked.append(probe)
    usable = [c for c in checked if c["ok"]]
    if not usable:
        warnings.append("no source could be reached; nothing would ever fire")
    for c in usable:
        if c.get("available", 0) == 0:
            warnings.append(f"{c['kind']}:{c['resolved_target']} returned nothing on a live fetch")
        if c["judged"] and all(j["verdict"] != "MATCH" for j in c["judged"]):
            warnings.append(
                f"{c['kind']}:{c['resolved_target']} — nothing on it matches right now, so this "
                "watch is waiting for something that has not happened yet"
            )
    return {"plan": plan, "sources": checked, "warnings": warnings, "usable": len(usable)}


def estimate_volume(probe: dict, rule: str) -> dict | None:
    samples = probe.get("samples") or []
    if not samples:
        return None
    dates = sorted(d for d in (s.get("occurred_at") for s in samples) if d)
    hits = sum(
        1 for s in samples
        if matcher.matches(rule or "", s.get("title") or "", s.get("summary") or "")
    )
    span_days = None
    if len(dates) >= 2:
        try:
            a = datetime.fromisoformat(dates[0].replace("Z", "+00:00"))
            b = datetime.fromisoformat(dates[-1].replace("Z", "+00:00"))
            span_days = max((b - a).total_seconds() / 86400.0, 0.0)
        except ValueError:
            span_days = None
    per_month = None
    if span_days and span_days >= 0.5:
        per_month = hits / span_days * 30.0
    return {"sampled": len(samples), "matched": hits, "span_days": span_days,
            "per_month": per_month}


def format_estimate(est: dict | None) -> str:
    if not est:
        return ""
    if est["matched"] == 0:
        return "nothing in the recent sample matches — it is waiting for something new"
    if est["per_month"] is None:
        return f"{est['matched']} of the last {est['sampled']} items match"
    return f"~{est['per_month']:.0f} msgs/month"


def plan_rows(plan: dict, checked: list[dict]) -> list[dict]:
    group = uuid.uuid4().hex[:12]
    rows = []
    for entry, probe in zip(plan["sources"], checked):
        if not probe.get("ok"):
            continue
        rows.append({
            "condition": plan.get("condition"),
            "kind": entry["kind"],
            "target": probe["resolved_target"],
            "name": plan["name"],
            "match_rule": entry.get("match") or None,
            "stop_after": int(plan.get("stop_after") or 0),
            "watch_group": group,
        })
    return rows


async def quick_create(text: str) -> dict:
    plan, provider = await interpret(text)
    result = await preview(plan)
    rows = plan_rows(result["plan"], result["sources"])
    if not rows:
        raise ValueError(
            "nothing usable came out of that — "
            + ("; ".join(result["warnings"][:2]) or "no source could be reached")
        )
    estimates = {}
    for entry, probe in zip(result["plan"]["sources"], result["sources"]):
        if probe.get("ok"):
            estimates[probe.get("resolved_target") or entry["target"]] = estimate_volume(
                probe, entry.get("match") or ""
            )
    return {"plan": result["plan"], "sources": result["sources"], "rows": rows,
            "warnings": result["warnings"], "provider": provider, "estimates": estimates}


def format_preview(result: dict) -> str:
    plan = result["plan"]
    lines = [f"<b>{plan['name']}</b>", f"<i>{plan['condition']}</i>", ""]
    for probe in result["sources"]:
        head = f"{probe['kind']} · {probe.get('resolved_target') or probe['target']}"
        if not probe["ok"]:
            lines.append(f"✗ {head}\n    {probe['error']}")
            continue
        rule = probe.get("match") or "every item from this source notifies you"
        lines.append(f"✓ {head} — {probe.get('available', 0)} items now")
        lines.append(f"    rule: {rule}")
        for j in probe.get("judged", []):
            lines.append(f"    [{j['verdict']}] {j['title'][:60]}")
            if j.get("reason"):
                lines.append(f"        {j['reason'][:110]}")
    stop = plan.get("stop_after") or 0
    lines.append("")
    lines.append(f"stops after: {stop if stop else 'never — ongoing'}")
    for w in result["warnings"]:
        lines.append(f"⚠ {w}")
    return "\n".join(lines)
