import os
from typing import Any

import httpx

USER_AGENT = os.environ.get(
    "WATCH_USER_AGENT",
    "mandragora-watch/0.1 (+https://watch.mvr.ac)",
)
GITHUB_PAT = os.environ.get("GITHUB_PAT", "").strip()


SOURCE_KINDS: dict[str, dict[str, str]] = {
    "github_user": {
        "label": "GitHub user",
        "target_hint": "octocat",
    },
    "github_repo": {
        "label": "GitHub repo",
        "target_hint": "owner/repo",
    },
    "reddit_user": {
        "label": "Reddit user",
        "target_hint": "spez",
    },
    "reddit_sub": {
        "label": "Subreddit",
        "target_hint": "selfhosted",
    },
}


def _github_headers() -> dict[str, str]:
    h = {
        "User-Agent": USER_AGENT,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if GITHUB_PAT:
        h["Authorization"] = f"Bearer {GITHUB_PAT}"
    return h


def _reddit_headers() -> dict[str, str]:
    return {
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
    }


def validate_target(kind: str, target: str) -> str:
    t = target.strip().lstrip("@/").rstrip("/")
    if not t:
        raise ValueError("empty target")
    if kind == "github_user":
        if "/" in t or " " in t:
            raise ValueError("github_user expects a single login")
    elif kind == "github_repo":
        if t.count("/") != 1 or " " in t:
            raise ValueError("github_repo expects owner/repo")
    elif kind == "reddit_user":
        if t.lower().startswith("u/"):
            t = t[2:]
        if "/" in t or " " in t:
            raise ValueError("reddit_user expects a single username")
    elif kind == "reddit_sub":
        if t.lower().startswith("r/"):
            t = t[2:]
        if "/" in t or " " in t:
            raise ValueError("reddit_sub expects a single subreddit")
    else:
        raise ValueError(f"unknown kind: {kind}")
    return t


async def fetch(kind: str, target: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    if kind == "github_user":
        return await _fetch_github_user(target, cursor)
    if kind == "github_repo":
        return await _fetch_github_repo(target, cursor)
    if kind == "reddit_user":
        return await _fetch_reddit_user(target, cursor)
    if kind == "reddit_sub":
        return await _fetch_reddit_sub(target, cursor)
    raise ValueError(f"unknown kind: {kind}")


async def _fetch_github_user(login: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    url = f"https://api.github.com/users/{login}/events/public"
    async with httpx.AsyncClient(timeout=20.0, headers=_github_headers()) as c:
        r = await c.get(url, params={"per_page": 30})
    if r.status_code == 404:
        return [], cursor
    r.raise_for_status()
    items = r.json() or []
    events: list[dict[str, Any]] = []
    newest_cursor = cursor
    for it in items:
        eid = str(it.get("id") or "")
        if not eid:
            continue
        if cursor is not None and eid <= cursor:
            continue
        events.append(_normalize_github_event(login, it))
        if newest_cursor is None or eid > newest_cursor:
            newest_cursor = eid
    events.reverse()
    return events, newest_cursor


def _normalize_github_event(login: str, it: dict[str, Any]) -> dict[str, Any]:
    etype = it.get("type") or "Event"
    repo = (it.get("repo") or {}).get("name") or ""
    payload = it.get("payload") or {}
    title = f"{login} {etype} {repo}".strip()
    summary = ""
    link = f"https://github.com/{repo}" if repo else f"https://github.com/{login}"
    if etype == "PushEvent":
        commits = payload.get("commits") or []
        msgs = [c.get("message", "").splitlines()[0] for c in commits[:3]]
        summary = " | ".join(m for m in msgs if m)
    elif etype == "IssuesEvent":
        issue = payload.get("issue") or {}
        title = f"{login} {payload.get('action','')} issue: {issue.get('title','')}"
        link = issue.get("html_url", link)
    elif etype == "PullRequestEvent":
        pr = payload.get("pull_request") or {}
        title = f"{login} {payload.get('action','')} PR: {pr.get('title','')}"
        link = pr.get("html_url", link)
    elif etype == "IssueCommentEvent":
        issue = payload.get("issue") or {}
        title = f"{login} commented on: {issue.get('title','')}"
        link = (payload.get("comment") or {}).get("html_url", link)
    elif etype == "ReleaseEvent":
        rel = payload.get("release") or {}
        title = f"{login} released {rel.get('tag_name','')} in {repo}"
        link = rel.get("html_url", link)
    elif etype == "WatchEvent":
        title = f"{login} starred {repo}"
    elif etype == "ForkEvent":
        forkee = payload.get("forkee") or {}
        title = f"{login} forked {repo}"
        link = forkee.get("html_url", link)
    elif etype == "CreateEvent":
        title = f"{login} created {payload.get('ref_type','')} in {repo}"
    return {
        "external_id": str(it.get("id")),
        "title": title.strip(),
        "summary": summary,
        "link": link,
        "occurred_at": it.get("created_at"),
        "raw": it,
    }


async def _fetch_github_repo(repo: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    url = f"https://api.github.com/repos/{repo}/events"
    async with httpx.AsyncClient(timeout=20.0, headers=_github_headers()) as c:
        r = await c.get(url, params={"per_page": 30})
    if r.status_code == 404:
        return [], cursor
    r.raise_for_status()
    items = r.json() or []
    events: list[dict[str, Any]] = []
    newest_cursor = cursor
    for it in items:
        eid = str(it.get("id") or "")
        if not eid:
            continue
        if cursor is not None and eid <= cursor:
            continue
        actor = (it.get("actor") or {}).get("login") or ""
        events.append(_normalize_github_event(actor or repo, it))
        if newest_cursor is None or eid > newest_cursor:
            newest_cursor = eid
    events.reverse()
    return events, newest_cursor


async def _fetch_reddit_user(name: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    url = f"https://www.reddit.com/user/{name}.json"
    async with httpx.AsyncClient(timeout=20.0, headers=_reddit_headers()) as c:
        r = await c.get(url, params={"limit": 25, "raw_json": 1})
    if r.status_code in (404, 403):
        return [], cursor
    r.raise_for_status()
    return _parse_reddit_listing(r.json(), cursor)


async def _fetch_reddit_sub(name: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    url = f"https://www.reddit.com/r/{name}/new.json"
    async with httpx.AsyncClient(timeout=20.0, headers=_reddit_headers()) as c:
        r = await c.get(url, params={"limit": 25, "raw_json": 1})
    if r.status_code in (404, 403):
        return [], cursor
    r.raise_for_status()
    return _parse_reddit_listing(r.json(), cursor)


def _parse_reddit_listing(doc: dict[str, Any], cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    children = ((doc or {}).get("data") or {}).get("children") or []
    events: list[dict[str, Any]] = []
    newest_cursor = cursor
    cursor_ts = float(cursor) if cursor else None
    for ch in children:
        d = ch.get("data") or {}
        fullname = d.get("name") or ""
        created = d.get("created_utc")
        if not fullname or created is None:
            continue
        if cursor_ts is not None and float(created) <= cursor_ts:
            continue
        kind = ch.get("kind")
        permalink = d.get("permalink") or ""
        link = f"https://www.reddit.com{permalink}" if permalink else (d.get("url") or "")
        if kind == "t3":
            title = f"post: {d.get('title','')}"
            summary = (d.get("selftext") or "")[:280]
        elif kind == "t1":
            title = f"comment in r/{d.get('subreddit','')}: {d.get('link_title','')}"
            summary = (d.get("body") or "")[:280]
        else:
            title = d.get("title") or fullname
            summary = ""
        events.append({
            "external_id": fullname,
            "title": title,
            "summary": summary,
            "link": link,
            "occurred_at": _utc_iso(created),
            "raw": d,
        })
        if newest_cursor is None or float(created) > float(newest_cursor):
            newest_cursor = str(created)
    events.reverse()
    return events, newest_cursor


def _utc_iso(epoch: float) -> str:
    from datetime import datetime, timezone
    return datetime.fromtimestamp(float(epoch), tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
