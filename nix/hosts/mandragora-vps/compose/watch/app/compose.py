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


TEMPLATES = {
    "tv": {
        "label": "a TV season is released",
        "fields": ["show", "season"],
        "example": "tv severance 3",
    },
    "advisory": {
        "label": "a project has a security advisory",
        "fields": ["owner/repo"],
        "example": "advisory spesmilo/electrum",
    },
    "release": {
        "label": "a project ships a release matching some words",
        "fields": ["owner/repo", "words (optional)"],
        "example": "release neovim/neovim 0.12",
    },
    "feeds": {
        "label": "any of these feeds mentions some words",
        "fields": ["words", "one or more feed urls"],
        "example": "feeds electrum https://www.bleepingcomputer.com/feed/",
    },
    "sub": {
        "label": "a subreddit posts about some words",
        "fields": ["subreddit", "words"],
        "example": "sub kindle paperwhite AND jailbreak",
    },
    "repo": {
        "label": "a repository has activity",
        "fields": ["owner/repo"],
        "example": "repo spesmilo/electrum",
    },
}


def template_help() -> str:
    lines = ["<b>watch templates</b>"]
    for key, t in TEMPLATES.items():
        lines.append(f"<code>/watch {key}</code> — {t['label']}")
        lines.append(f"    e.g. <code>/watch {t['example']}</code>")
    return "\n".join(lines)


INTERPRET_SYSTEM = (
    "You turn one sentence into a watch registration for a feed-polling system.\n\n"
    "You may ONLY fill in one of the templates listed. You may not invent a template, "
    "a source kind, or a field. Choose the template whose shape answers the sentence, "
    "and supply its arguments in order as a list of strings.\n\n"
    "Argument rules:\n"
    "- tv: [show name, season number]\n"
    "- advisory / repo: [owner/repo] — a real repository that exists\n"
    "- release: [owner/repo, optional words the release must mention]\n"
    "- feeds: [words, then one or more http(s) feed urls] — real feed urls only\n"
    "- sub: [subreddit name, then the words a post must mention]\n\n"
    "The words you supply become a keyword rule matched against an item's text. "
    "Whitespace means AND; uppercase AND, OR and NOT are operators; \"quoted phrases\" "
    "match as a phrase. Terms match on word boundaries.\n\n"
    "Keep rules SHORT and do not re-state what the source already scopes: a Kindle "
    "forum is already about Kindles, so the rule there is `jailbreak`, not "
    "`kindle AND jailbreak`. A rule that repeats the source's own topic costs recall "
    "and buys nothing, because announcements name models and versions rather than "
    "the generic word you would have guessed.\n\n"
    "Return ONLY a JSON object: {\"template\": \"...\", \"args\": [\"...\"], \"why\": \"<=120 chars\"}"
)


def interpret_prompt(text: str) -> str:
    lines = ["TEMPLATES:"]
    for key, t in TEMPLATES.items():
        lines.append(f"- {key}: {t['label']}")
        lines.append(f"    fields: {', '.join(t['fields'])}")
        lines.append(f"    example: /watch {t['example']}")
    lines.append("")
    lines.append("WHAT EACH SOURCE ACTUALLY EMITS:")
    for kind, emits in sources.SOURCE_EMITS.items():
        lines.append(f"- {kind}: {emits}")
    lines.append("")
    lines.append("SENTENCE:")
    lines.append(text.strip())
    return "\n".join(lines)


async def interpret(text: str) -> tuple[str, list[str], str]:
    if not (text or "").strip():
        raise ValueError("say what you want to watch")
    raw, provider = await llm.complete(INTERPRET_SYSTEM, interpret_prompt(text))
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError:
        start, end = raw.find("{"), raw.rfind("}")
        if start < 0 or end <= start:
            raise ValueError(f"model did not return a plan: {raw[:120]}")
        doc = json.loads(raw[start:end + 1])
    template = str(doc.get("template") or "").strip().lower()
    if template not in TEMPLATES:
        raise ValueError(f"model chose an unknown template {template!r}")
    args = doc.get("args") or []
    if isinstance(args, str):
        args = args.split()
    if not isinstance(args, list) or not args:
        raise ValueError(f"model gave no arguments for template {template!r}")
    return template, [str(a) for a in args][:20], provider


def build_plan(template: str, args: list[str]) -> dict:
    template = (template or "").strip().lower()
    if template not in TEMPLATES:
        raise ValueError(f"unknown template {template!r}; try one of: {', '.join(TEMPLATES)}")
    args = [a for a in args if a.strip()]
    if not args:
        raise ValueError(f"{template} needs: {', '.join(TEMPLATES[template]['fields'])}")

    if template == "tv":
        if len(args) < 2 or not args[-1].isdigit():
            raise ValueError("tv needs a show and a season number, e.g. tv severance 3")
        show, season = " ".join(args[:-1]), int(args[-1])
        return {
            "name": f"{show} season {season}",
            "condition": f"{show} season {season} is released",
            "stop_after": 1,
            "sources": [{"kind": "tvmaze_season", "target": f"{show}:{season}", "match": "",
                         "why": "the premiere date is a field, not an opinion"}],
        }

    if template == "advisory":
        repo = args[0]
        name = repo.split("/")[-1]
        return {
            "name": f"{name} security advisories",
            "condition": f"{repo} publishes a security advisory",
            "stop_after": 0,
            "sources": [
                {"kind": "github_advisory", "target": repo, "match": "",
                 "why": "advisories straight from the project"},
                {"kind": "osv_package", "target": f"PyPI:{name}", "match": "",
                 "why": "the same package in the OSV database"},
            ],
        }

    if template == "release":
        repo = args[0]
        words = " ".join(args[1:])
        return {
            "name": f"{repo} releases" + (f" matching {words}" if words else ""),
            "condition": f"{repo} ships a release" + (f" matching {words}" if words else ""),
            "stop_after": 1 if words else 0,
            "sources": [{"kind": "github_release", "target": repo, "match": words,
                         "why": "release notes from the project"}],
        }

    if template == "feeds":
        urls = [a for a in args if a.startswith("http")]
        words = " ".join(a for a in args if not a.startswith("http"))
        if not urls:
            raise ValueError("feeds needs at least one http(s) feed url")
        if not words:
            raise ValueError("feeds needs words to look for")
        return {
            "name": f"feeds mentioning {words}",
            "condition": f"one of {len(urls)} feeds mentions {words}",
            "stop_after": 0,
            "sources": [{"kind": "rss", "target": u, "match": words, "why": "feed"} for u in urls],
        }

    if template == "sub":
        sub = args[0]
        words = " ".join(args[1:])
        if not words:
            raise ValueError("sub needs words to look for")
        return {
            "name": f"r/{sub} mentioning {words}",
            "condition": f"r/{sub} posts about {words}",
            "stop_after": 0,
            "sources": [{"kind": "reddit_sub", "target": sub, "match": words, "why": "subreddit"}],
        }

    repo = args[0]
    return {
        "name": f"{repo} activity",
        "condition": f"{repo} has activity",
        "stop_after": 0,
        "sources": [{"kind": "github_repo", "target": repo, "match": "", "why": "repo events"}],
    }


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


async def preview(template: str, args: list[str]) -> dict:
    plan = build_plan(template, args)
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
            "kind": entry["kind"],
            "target": probe["resolved_target"],
            "name": plan["name"],
            "match_rule": entry.get("match") or None,
            "stop_after": int(plan.get("stop_after") or 0),
            "watch_group": group,
        })
    return rows


async def quick_create(text: str) -> dict:
    template, args, provider = await interpret(text)
    result = await preview(template, args)
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
            "warnings": result["warnings"], "provider": provider, "estimates": estimates,
            "template": template, "args": args}


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
