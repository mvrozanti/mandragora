import json
import logging
import os
import uuid

import judge
import sources

log = logging.getLogger("watch.compose")

PROBE_ITEMS = int(os.environ.get("WATCH_COMPOSE_PROBE_ITEMS", "3"))
COMPOSE_NUM_CTX = int(os.environ.get("WATCH_COMPOSE_NUM_CTX", "8192"))


SYSTEM_PROMPT = (
    "You turn a plain-language watch condition into a plan for a feed-polling system.\n\n"
    "Choose the FEWEST sources that can actually answer the condition. Prefer a structured "
    "fact source over a search feed whenever one exists: a TV season's release is "
    "tvmaze_season, a software release is github_release, a stream going live is "
    "twitch_stream. Reach for search feeds (hn_search, reddit_search) only when no fact "
    "source can answer, such as an exploit or a leak.\n\n"
    "Targets must be real and exact. Use the identifier the source itself uses — a real "
    "owner/repo, a real feed URL, a real show name. If you are not sure a repository or feed "
    "exists, choose a search source instead of guessing an identifier.\n\n"
    "For each source, write `spec`: what must be true of a fetched item before the user is "
    "told. Leave `spec` as an empty string when the source only emits the event in question "
    "anyway, so that every item from it is worth sending — a season's premiere date "
    "appearing, a streamer going live. Write a spec only where the source emits a mix of "
    "relevant and irrelevant items and something must read them. A spec must be decidable "
    "from an item's title, summary and the text of the page it links to, and must name the "
    "concrete constraints that matter: version, generation, firmware, platform.\n\n"
    "stop_after: how many times this watch should fire before it is finished. Use 1 for a "
    "one-time event that cannot recur — a season being released, a device being jailbroken, "
    "a specific version shipping. Use 0 for an ongoing condition that can happen repeatedly, "
    "such as security vulnerabilities in a product.\n\n"
    "Return ONLY JSON."
)

PLAN_SCHEMA = {
    "type": "object",
    "properties": {
        "name": {"type": "string"},
        "sources": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "kind": {"type": "string", "enum": sorted(sources.SOURCE_KINDS)},
                    "target": {"type": "string"},
                    "spec": {"type": "string"},
                    "why": {"type": "string"},
                },
                "required": ["kind", "target", "spec", "why"],
            },
        },
        "stop_after": {"type": "integer"},
    },
    "required": ["name", "sources", "stop_after"],
}


def source_menu() -> str:
    lines = []
    for kind, meta in sources.SOURCE_KINDS.items():
        emits = judge.SOURCE_EMITS.get(kind, "")
        hint = meta.get("target_hint", "")
        lines.append(f"- {kind} (target looks like: {hint})\n    emits: {emits}")
    return "\n".join(lines)


def build_prompt(condition: str) -> str:
    return (
        "AVAILABLE SOURCE KINDS:\n"
        f"{source_menu()}\n\n"
        "WATCH CONDITION:\n"
        f"{condition.strip()}\n"
    )


async def compose_plan(condition: str) -> dict:
    if not condition.strip():
        raise ValueError("empty condition")
    text = await judge._generate(
        SYSTEM_PROMPT, build_prompt(condition), PLAN_SCHEMA, num_predict=800
    )
    plan = judge._parse_json_object(text)
    plan["name"] = str(plan.get("name") or condition.strip())[:120]
    plan["condition"] = condition.strip()
    try:
        plan["stop_after"] = max(0, int(plan.get("stop_after") or 0))
    except (TypeError, ValueError):
        plan["stop_after"] = 0
    raw_sources = plan.get("sources") or []
    if not isinstance(raw_sources, list) or not raw_sources:
        raise RuntimeError("plan proposed no sources")
    cleaned = []
    for item in raw_sources[:4]:
        if not isinstance(item, dict):
            continue
        kind = str(item.get("kind") or "").strip()
        if kind not in sources.SOURCE_KINDS:
            continue
        cleaned.append({
            "kind": kind,
            "target": str(item.get("target") or "").strip(),
            "spec": str(item.get("spec") or "").strip(),
            "why": str(item.get("why") or "").strip()[:200],
        })
    if not cleaned:
        raise RuntimeError("plan proposed no usable sources")
    plan["sources"] = cleaned
    return plan


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
        {"title": (it.get("title") or "")[:160], "link": it.get("link") or ""}
        for it in items[:PROBE_ITEMS]
    ]
    result["available"] = len(items)
    return result


async def judge_samples(entry: dict, probe: dict) -> list[dict]:
    if not entry.get("spec"):
        return []
    out = []
    for sample in probe.get("samples", [])[:PROBE_ITEMS]:
        event = {
            "title": sample["title"],
            "summary": "",
            "link": sample["link"],
            "w_kind": entry["kind"],
            "w_target": probe.get("resolved_target"),
            "w_must_mention": "",
        }
        try:
            verdict = await judge.judge_event(entry["spec"], event)
        except Exception as exc:
            out.append({"title": sample["title"], "verdict": "ERROR", "reason": str(exc)[:160]})
            continue
        out.append({
            "title": sample["title"],
            "verdict": verdict["verdict"],
            "reason": verdict["reason"][:200],
        })
    return out


async def preview(condition: str) -> dict:
    plan = await compose_plan(condition)
    checked = []
    warnings = []
    for entry in plan["sources"]:
        probe = await probe_source(entry)
        if probe["ok"]:
            probe["judged"] = await judge_samples(entry, probe)
        else:
            probe["judged"] = []
            warnings.append(f"{entry['kind']}:{entry['target']} — {probe['error']}")
        checked.append(probe)
    usable = [c for c in checked if c["ok"]]
    if not usable:
        warnings.append("no proposed source could be reached; nothing would ever fire")
    for c in usable:
        if c.get("available", 0) == 0:
            warnings.append(f"{c['kind']}:{c['resolved_target']} returned nothing on a live fetch")
        if c["judged"] and all(j["verdict"] == "NO" for j in c["judged"]):
            warnings.append(
                f"{c['kind']}:{c['resolved_target']} — nothing on it matches right now, so this "
                "watch is waiting for something that has not happened yet"
            )
    return {"plan": plan, "sources": checked, "warnings": warnings, "usable": len(usable)}


def plan_rows(plan: dict, checked: list[dict]) -> list[dict]:
    group = uuid.uuid4().hex[:12]
    rows = []
    for entry, probe in zip(plan["sources"], checked):
        if not probe.get("ok"):
            continue
        rows.append({
            "kind": entry["kind"],
            "target": probe["resolved_target"],
            "name": plan["name"],
            "ai_spec": entry["spec"] or None,
            "stop_after": int(plan.get("stop_after") or 0),
            "watch_group": group,
        })
    return rows


def format_preview(result: dict) -> str:
    plan = result["plan"]
    lines = [f"<b>{plan['name']}</b>", f"<i>{plan['condition']}</i>", ""]
    for probe in result["sources"]:
        head = f"{probe['kind']} · {probe.get('resolved_target') or probe['target']}"
        if not probe["ok"]:
            lines.append(f"✗ {head}\n    {probe['error']}")
            continue
        rule = probe.get("spec") or "every item from this source notifies you"
        lines.append(f"✓ {head} — {probe.get('available', 0)} items now")
        lines.append(f"    rule: {rule}")
        for j in probe.get("judged", []):
            lines.append(f"    [{j['verdict']}] {j['title'][:60]}")
    stop = plan.get("stop_after") or 0
    lines.append("")
    lines.append(f"stops after: {stop if stop else 'never — ongoing'}")
    for w in result["warnings"]:
        lines.append(f"⚠ {w}")
    return "\n".join(lines)
