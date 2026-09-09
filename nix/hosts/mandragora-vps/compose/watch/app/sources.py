import asyncio
import html
import os
import re
import time
import xml.etree.ElementTree as ET
from typing import Any

import httpx

USER_AGENT = os.environ.get(
    "WATCH_USER_AGENT",
    "mandragora-watch/0.1 (+https://watch.mvr.ac)",
)
GITHUB_PAT = os.environ.get("GITHUB_PAT", "").strip()
TWITCH_CLIENT_ID = os.environ.get("TWITCH_CLIENT_ID", "").strip()
TWITCH_CLIENT_SECRET = os.environ.get("TWITCH_CLIENT_SECRET", "").strip()

class RateLimited(RuntimeError):
    def __init__(self, message: str, retry_after: float | None = None) -> None:
        super().__init__(message)
        self.retry_after = retry_after


def _retry_after_seconds(response: httpx.Response) -> float | None:
    headers = getattr(response, "headers", None)
    raw = headers.get("Retry-After") if headers else None
    if not raw:
        return None
    try:
        return max(0.0, float(raw))
    except (TypeError, ValueError):
        return None


def _raise_for_throttle(response: httpx.Response, source: str) -> None:
    if response.status_code not in (403, 429):
        return
    wait = _retry_after_seconds(response)
    if response.status_code == 429:
        raise RateLimited(f"{source} rate-limited the request (429)", wait)
    raise RateLimited(
        f"{source} refused the request (403) — rate-limited or IP-blocked; backing off",
        wait,
    )


_YT_CHANNEL_ID_RE = re.compile(r"UC[A-Za-z0-9_-]{22}")
_YT_HANDLE_RE = re.compile(r"^[A-Za-z0-9_.\-]{3,30}$")
_TWITCH_LOGIN_RE = re.compile(r"^[A-Za-z0-9_]{3,25}$")
_TVMAZE_TARGET_RE = re.compile(r"^(.+?):(\d{1,3})$")
_twitch_token_cache: dict[str, Any] = {"token": "", "expires_at": 0.0}
_github_account_type_cache: dict[str, str] = {}


SOURCE_KINDS: dict[str, dict[str, str]] = {
    "github_user": {
        "label": "GitHub user",
        "target_hint": "octocat",
    },
    "github_repo": {
        "label": "GitHub repo",
        "target_hint": "owner/repo",
    },
    "github_release": {
        "label": "GitHub releases (changelog)",
        "target_hint": "hyprwm/hyprland",
    },
    "reddit_user": {
        "label": "Reddit user",
        "target_hint": "spez",
    },
    "reddit_sub": {
        "label": "Subreddit",
        "target_hint": "selfhosted",
    },
    "youtube_channel": {
        "label": "YouTube channel",
        "target_hint": "@mkbhd or UCxxxxxxxxxxxxxxxxxxxx",
    },
    "twitch_stream": {
        "label": "Twitch streamer (live transitions)",
        "target_hint": "shroud",
    },
    "hn_search": {
        "label": "Hacker News search (Algolia)",
        "target_hint": "kindle paperwhite jailbreak",
    },
    "reddit_search": {
        "label": "Reddit cross-sub search",
        "target_hint": "kindle paperwhite jailbreak",
    },
    "rss": {
        "label": "RSS / Atom feed",
        "target_hint": "https://www.mobileread.com/forums/external.php?type=RSS2&forumids=150",
    },
    "tvmaze_season": {
        "label": "TV season status (TVmaze)",
        "target_hint": "severance:3 or 44933:3",
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


REDDIT_MIN_INTERVAL = float(os.environ.get("WATCH_REDDIT_MIN_INTERVAL", "60"))
REDDIT_SUMMARY_MAX = int(os.environ.get("WATCH_REDDIT_SUMMARY_MAX", "4000"))
_REDDIT_HOST_RE = re.compile(r"^https?://([a-z0-9-]+\.)*(reddit\.com|redd\.it)(/|$)", re.I)
_reddit_gate = {"lock": None, "last": 0.0}


def _reddit_headers() -> dict[str, str]:
    return {
        "User-Agent": USER_AGENT,
        "Accept": "application/atom+xml, application/rss+xml, text/xml;q=0.9, */*;q=0.5",
    }


async def _reddit_pace() -> None:
    if _reddit_gate["lock"] is None:
        _reddit_gate["lock"] = asyncio.Lock()
    async with _reddit_gate["lock"]:
        gap = REDDIT_MIN_INTERVAL - (time.monotonic() - _reddit_gate["last"])
        if gap > 0:
            await asyncio.sleep(gap)
        _reddit_gate["last"] = time.monotonic()


def reddit_outbound_link(content_html: str, permalink: str) -> str:
    for href in re.findall(r'href="([^"]+)"', html.unescape(content_html or "")):
        url = html.unescape(href).strip()
        if url.startswith(("http://", "https://")) and not _REDDIT_HOST_RE.match(url):
            return url
    return permalink


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
    elif kind == "github_release":
        if t.count("/") != 1 or " " in t:
            raise ValueError("github_release expects owner/repo")
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
    elif kind == "youtube_channel":
        if _YT_CHANNEL_ID_RE.fullmatch(t):
            return t
        if not _YT_HANDLE_RE.fullmatch(t):
            raise ValueError("youtube_channel expects @handle or UC… channel id")
        return _resolve_youtube_handle(t)
    elif kind == "twitch_stream":
        t = t.lower()
        if not _TWITCH_LOGIN_RE.fullmatch(t):
            raise ValueError("twitch_stream expects a single twitch login")
        return t
    elif kind == "hn_search":
        t = target.strip()
        if not t or len(t) > 200:
            raise ValueError("hn_search expects a 1..200 char query")
        return t
    elif kind == "reddit_search":
        t = target.strip()
        if not t or len(t) > 200:
            raise ValueError("reddit_search expects a 1..200 char query")
        return t
    elif kind == "rss":
        t = target.strip()
        if not (t.startswith("http://") or t.startswith("https://")):
            raise ValueError("rss expects an http(s) URL")
        if len(t) > 500:
            raise ValueError("rss url too long")
        return t
    elif kind == "tvmaze_season":
        return _resolve_tvmaze_target(target.strip())
    else:
        raise ValueError(f"unknown kind: {kind}")
    return t


async def fetch(kind: str, target: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    if kind == "github_user":
        return await _fetch_github_user(target, cursor)
    if kind == "github_repo":
        return await _fetch_github_repo(target, cursor)
    if kind == "github_release":
        return await _fetch_github_releases(target, cursor)
    if kind == "reddit_user":
        return await _fetch_reddit_user(target, cursor)
    if kind == "reddit_sub":
        return await _fetch_reddit_sub(target, cursor)
    if kind == "youtube_channel":
        return await _fetch_youtube_channel(target, cursor)
    if kind == "twitch_stream":
        return await _fetch_twitch_stream(target, cursor)
    if kind == "hn_search":
        return await _fetch_hn_search(target, cursor)
    if kind == "reddit_search":
        return await _fetch_reddit_search(target, cursor)
    if kind == "rss":
        return await _fetch_rss(target, cursor)
    if kind == "tvmaze_season":
        return await _fetch_tvmaze_season(target, cursor)
    raise ValueError(f"unknown kind: {kind}")


async def _github_account_type(login: str) -> str:
    cached = _github_account_type_cache.get(login)
    if cached:
        return cached
    async with httpx.AsyncClient(timeout=15.0, headers=_github_headers()) as c:
        r = await c.get(f"https://api.github.com/users/{login}")
    if r.status_code == 404:
        return "User"
    r.raise_for_status()
    t = (r.json() or {}).get("type") or "User"
    _github_account_type_cache[login] = t
    return t


async def _fetch_github_user(login: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    acct_type = await _github_account_type(login)
    if acct_type == "Organization":
        url = f"https://api.github.com/orgs/{login}/events"
    else:
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


RELEASE_BODY_MAX = int(os.environ.get("WATCH_RELEASE_BODY_MAX", "12000"))


async def _fetch_github_releases(repo: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    url = f"https://api.github.com/repos/{repo}/releases"
    async with httpx.AsyncClient(timeout=20.0, headers=_github_headers()) as c:
        r = await c.get(url, params={"per_page": 30})
    if r.status_code == 404:
        return [], cursor
    r.raise_for_status()
    items = r.json() or []
    cursor_id = int(cursor) if cursor and cursor.isdigit() else None
    newest = cursor_id
    events: list[dict[str, Any]] = []
    for it in items:
        if it.get("draft"):
            continue
        rid = it.get("id")
        if rid is None:
            continue
        rid = int(rid)
        if cursor_id is not None and rid <= cursor_id:
            continue
        tag = it.get("tag_name") or ""
        name = it.get("name") or tag
        pre = " (prerelease)" if it.get("prerelease") else ""
        body = (it.get("body") or "").strip()
        title = f"{repo} {tag}{pre}".strip() if tag else f"{repo}: {name}{pre}"
        events.append({
            "external_id": str(rid),
            "title": title,
            "summary": body[:RELEASE_BODY_MAX],
            "link": it.get("html_url") or f"https://github.com/{repo}/releases",
            "occurred_at": it.get("published_at") or it.get("created_at"),
            "raw": {"id": rid, "tag": tag, "name": name, "prerelease": bool(it.get("prerelease"))},
        })
        if newest is None or rid > newest:
            newest = rid
    events.reverse()
    return events, str(newest) if newest is not None else cursor


async def _fetch_reddit_feed(url: str, params: dict[str, Any], cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    await _reddit_pace()
    async with httpx.AsyncClient(timeout=20.0, headers=_reddit_headers(), follow_redirects=True) as c:
        r = await c.get(url, params=params)
    if r.status_code == 404:
        return [], cursor
    _raise_for_throttle(r, "reddit")
    r.raise_for_status()
    return _parse_reddit_feed(r.text, cursor)


async def _fetch_reddit_user(name: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    return await _fetch_reddit_feed(f"https://www.reddit.com/user/{name}.rss", {"limit": 25}, cursor)


async def _fetch_reddit_sub(name: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    return await _fetch_reddit_feed(f"https://www.reddit.com/r/{name}/new.rss", {"limit": 25}, cursor)


def _parse_reddit_feed(text: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    try:
        root = ET.fromstring(text)
    except ET.ParseError as exc:
        raise RuntimeError(f"reddit feed parse error: {exc}")
    ns = {"a": "http://www.w3.org/2005/Atom"}
    cursor_ts = float(cursor) if cursor else None
    newest_cursor = cursor
    events: list[dict[str, Any]] = []
    for e in root.findall("a:entry", ns):
        id_el = e.find("a:id", ns)
        title_el = e.find("a:title", ns)
        link_el = e.find("a:link", ns)
        content_el = e.find("a:content", ns)
        updated_el = e.find("a:updated", ns)
        if updated_el is None:
            updated_el = e.find("a:published", ns)
        ext_id = (id_el.text if id_el is not None else "") or ""
        permalink = (link_el.get("href") if link_el is not None else "") or ""
        if not ext_id:
            ext_id = permalink
        if not ext_id or ext_id.startswith("t5_"):
            continue
        ts = _parse_rss_date(updated_el.text if updated_el is not None else "")
        if cursor_ts is not None and ts is not None and ts <= cursor_ts:
            continue
        content = (content_el.text if content_el is not None else "") or ""
        title = (title_el.text if title_el is not None else "") or "(untitled)"
        if ext_id.startswith("t1_"):
            title = f"comment: {title}"
        elif ext_id.startswith("t3_"):
            title = f"post: {title}"
        events.append({
            "external_id": ext_id,
            "title": title,
            "summary": _strip_html(html.unescape(content))[:REDDIT_SUMMARY_MAX],
            "link": reddit_outbound_link(content, permalink),
            "occurred_at": _utc_iso(ts) if ts is not None else None,
            "raw": {"id": ext_id, "permalink": permalink},
        })
        if ts is not None and (newest_cursor is None or ts > float(newest_cursor)):
            newest_cursor = str(ts)
    events.reverse()
    return events, newest_cursor


def _utc_iso(epoch: float) -> str:
    from datetime import datetime, timezone
    return datetime.fromtimestamp(float(epoch), tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _resolve_youtube_handle(handle: str) -> str:
    url = f"https://www.youtube.com/@{handle}"
    with httpx.Client(timeout=15.0, headers={"User-Agent": USER_AGENT}, follow_redirects=True) as c:
        r = c.get(url)
    if r.status_code != 200:
        raise ValueError(f"youtube handle lookup failed: HTTP {r.status_code}")
    m = _YT_CHANNEL_ID_RE.search(r.text)
    if not m:
        raise ValueError(f"could not resolve @{handle} to a channel id")
    return m.group(0)


async def _fetch_youtube_channel(channel_id: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    url = "https://www.youtube.com/feeds/videos.xml"
    async with httpx.AsyncClient(timeout=20.0, headers={"User-Agent": USER_AGENT}) as c:
        r = await c.get(url, params={"channel_id": channel_id})
    if r.status_code == 404:
        return [], cursor
    r.raise_for_status()
    return _parse_youtube_feed(r.text, cursor)


def _parse_youtube_feed(xml_text: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    ns = {
        "a": "http://www.w3.org/2005/Atom",
        "yt": "http://www.youtube.com/xml/schemas/2015",
        "media": "http://search.yahoo.com/mrss/",
    }
    root = ET.fromstring(xml_text)
    events: list[dict[str, Any]] = []
    cursor_ts = float(cursor) if cursor else None
    newest_cursor = cursor
    for entry in root.findall("a:entry", ns):
        vid_el = entry.find("yt:videoId", ns)
        title_el = entry.find("a:title", ns)
        pub_el = entry.find("a:published", ns)
        if vid_el is None or title_el is None or pub_el is None:
            continue
        vid = vid_el.text or ""
        if not vid:
            continue
        from datetime import datetime
        pub_dt = datetime.fromisoformat((pub_el.text or "").replace("Z", "+00:00"))
        pub_ts = pub_dt.timestamp()
        if cursor_ts is not None and pub_ts <= cursor_ts:
            continue
        author_el = entry.find("a:author/a:name", ns)
        author = (author_el.text if author_el is not None else "") or ""
        group = entry.find("media:group", ns)
        summary = ""
        if group is not None:
            desc_el = group.find("media:description", ns)
            if desc_el is not None and desc_el.text:
                summary = desc_el.text[:280]
        events.append({
            "external_id": vid,
            "title": f"{author}: {title_el.text or vid}".strip(),
            "summary": summary,
            "link": f"https://www.youtube.com/watch?v={vid}",
            "occurred_at": _utc_iso(pub_ts),
            "raw": {"video_id": vid, "published": pub_el.text, "author": author},
        })
        if newest_cursor is None or pub_ts > float(newest_cursor):
            newest_cursor = str(pub_ts)
    events.reverse()
    return events, newest_cursor


async def _twitch_token() -> str:
    if not (TWITCH_CLIENT_ID and TWITCH_CLIENT_SECRET):
        raise RuntimeError("TWITCH_CLIENT_ID / TWITCH_CLIENT_SECRET not configured")
    now = time.time()
    if _twitch_token_cache["token"] and now < float(_twitch_token_cache["expires_at"]) - 3600:
        return str(_twitch_token_cache["token"])
    async with httpx.AsyncClient(timeout=15.0) as c:
        r = await c.post(
            "https://id.twitch.tv/oauth2/token",
            params={
                "client_id": TWITCH_CLIENT_ID,
                "client_secret": TWITCH_CLIENT_SECRET,
                "grant_type": "client_credentials",
            },
        )
    r.raise_for_status()
    doc = r.json()
    tok = doc.get("access_token") or ""
    expires_in = int(doc.get("expires_in") or 0)
    _twitch_token_cache["token"] = tok
    _twitch_token_cache["expires_at"] = now + expires_in
    return tok


async def _fetch_twitch_stream(login: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    tok = await _twitch_token()
    headers = {
        "User-Agent": USER_AGENT,
        "Client-Id": TWITCH_CLIENT_ID,
        "Authorization": f"Bearer {tok}",
    }
    async with httpx.AsyncClient(timeout=20.0, headers=headers) as c:
        r = await c.get("https://api.twitch.tv/helix/streams", params={"user_login": login})
        if r.status_code == 401:
            _twitch_token_cache["token"] = ""
            _twitch_token_cache["expires_at"] = 0.0
            tok = await _twitch_token()
            headers["Authorization"] = f"Bearer {tok}"
            r = await c.get(
                "https://api.twitch.tv/helix/streams",
                params={"user_login": login},
                headers=headers,
            )
    r.raise_for_status()
    data = (r.json() or {}).get("data") or []
    if not data:
        return [], ""
    stream = data[0]
    stream_id = str(stream.get("id") or "")
    if not stream_id:
        return [], cursor or ""
    if cursor and cursor == stream_id:
        return [], stream_id
    title = stream.get("title") or ""
    game = stream.get("game_name") or ""
    started_at = stream.get("started_at") or ""
    event = {
        "external_id": stream_id,
        "title": f"{login} live: {title}".strip(),
        "summary": game,
        "link": f"https://twitch.tv/{login}",
        "occurred_at": started_at,
        "raw": stream,
    }
    return [event], stream_id


TVMAZE_API = "https://api.tvmaze.com"


def _resolve_tvmaze_target(target: str) -> str:
    m = _TVMAZE_TARGET_RE.match(target)
    if not m:
        raise ValueError("tvmaze_season expects <show>:<season>, e.g. severance:3 or 44933:3")
    show, number = m.group(1).strip(), int(m.group(2))
    if number < 1:
        raise ValueError("tvmaze_season expects a season number >= 1")
    if not show:
        raise ValueError("tvmaze_season expects a show name or tvmaze id")
    if show.isdigit():
        return f"{int(show)}:{number}"
    with httpx.Client(timeout=15.0, headers={"User-Agent": USER_AGENT}) as c:
        r = c.get(f"{TVMAZE_API}/search/shows", params={"q": show})
    if r.status_code != 200:
        raise ValueError(f"tvmaze show lookup failed: HTTP {r.status_code}")
    hits = r.json() or []
    if not hits:
        raise ValueError(f"tvmaze has no show matching {show!r}")
    return f"{int(hits[0]['show']['id'])}:{number}"


def _parse_tvmaze_target(target: str) -> tuple[int, int]:
    show, _, number = target.partition(":")
    return int(show), int(number)


def tvmaze_state(season: dict[str, Any] | None, today: str) -> str:
    if season is None:
        return "absent"
    premiere = str(season.get("premiereDate") or "").strip()
    if premiere:
        return f"aired:{premiere}" if premiere <= today else f"dated:{premiere}"
    order = season.get("episodeOrder")
    return f"listed:eps={order}" if order else "listed"


def tvmaze_headline(show_name: str, number: int, state: str) -> str:
    head, _, detail = state.partition(":")
    if head == "absent":
        return f"{show_name} season {number} is not listed on TVmaze"
    if head == "aired":
        return f"{show_name} season {number} premiered {detail}"
    if head == "dated":
        return f"{show_name} season {number} premiere dated {detail}"
    if detail.startswith("eps="):
        return f"{show_name} season {number} ordered — {detail[4:]} episodes, no premiere date yet"
    return f"{show_name} season {number} listed — no premiere date yet"


async def _fetch_tvmaze_season(target: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    show_id, number = _parse_tvmaze_target(target)
    async with httpx.AsyncClient(timeout=20.0, headers={"User-Agent": USER_AGENT}) as c:
        r = await c.get(f"{TVMAZE_API}/shows/{show_id}", params={"embed": "seasons"})
    if r.status_code == 404:
        raise ValueError(f"tvmaze show {show_id} not found")
    _raise_for_throttle(r, "tvmaze")
    r.raise_for_status()
    doc = r.json() or {}
    show_name = doc.get("name") or f"show {show_id}"
    seasons = ((doc.get("_embedded") or {}).get("seasons")) or []
    season = next((s for s in seasons if s.get("number") == number), None)
    today = time.strftime("%Y-%m-%d", time.gmtime())
    state = tvmaze_state(season, today)
    if cursor == state:
        return [], state
    channel = (doc.get("network") or doc.get("webChannel") or {}).get("name") or ""
    summary_bits = [b for b in (channel, f"show status: {doc.get('status') or 'unknown'}") if b]
    event = {
        "external_id": f"{show_id}:{number}:{state}",
        "title": tvmaze_headline(show_name, number, state),
        "summary": " · ".join(summary_bits),
        "link": (season or {}).get("url") or doc.get("url") or f"https://www.tvmaze.com/shows/{show_id}",
        "occurred_at": _utc_iso(time.time()),
        "raw": {"state": state, "season": season, "show": show_name},
    }
    return [event], state


async def _fetch_hn_search(query: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    params: dict[str, Any] = {"query": query, "tags": "story", "hitsPerPage": 30}
    if cursor:
        try:
            params["numericFilters"] = f"created_at_i>{int(float(cursor))}"
        except ValueError:
            pass
    async with httpx.AsyncClient(timeout=20.0, headers={"User-Agent": USER_AGENT}) as c:
        r = await c.get("https://hn.algolia.com/api/v1/search_by_date", params=params)
    r.raise_for_status()
    doc = r.json() or {}
    hits = doc.get("hits") or []
    events: list[dict[str, Any]] = []
    newest_cursor = cursor
    cursor_ts = float(cursor) if cursor else None
    for h in hits:
        oid = str(h.get("objectID") or "")
        ts = h.get("created_at_i")
        if not oid or ts is None:
            continue
        if cursor_ts is not None and float(ts) <= cursor_ts:
            continue
        title = h.get("title") or h.get("story_title") or "(untitled)"
        url = h.get("url") or f"https://news.ycombinator.com/item?id={oid}"
        events.append({
            "external_id": oid,
            "title": f"HN: {title}",
            "summary": (h.get("story_text") or "")[:280] if h.get("story_text") else "",
            "link": url,
            "occurred_at": _utc_iso(float(ts)),
            "raw": h,
        })
        if newest_cursor is None or float(ts) > float(newest_cursor):
            newest_cursor = str(ts)
    events.reverse()
    return events, newest_cursor


async def _fetch_reddit_search(query: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    params = {"q": query, "sort": "new", "restrict_sr": "0", "limit": 25}
    return await _fetch_reddit_feed("https://www.reddit.com/search.rss", params, cursor)


async def _fetch_rss(url: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    async with httpx.AsyncClient(timeout=20.0, headers={"User-Agent": USER_AGENT}, follow_redirects=True) as c:
        r = await c.get(url)
    r.raise_for_status()
    return _parse_feed(r.text, cursor)


def _parse_feed(text: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    try:
        root = ET.fromstring(text)
    except ET.ParseError as exc:
        raise RuntimeError(f"feed parse error: {exc}")
    tag = root.tag.split("}", 1)[-1]
    cursor_ts = float(cursor) if cursor else None
    events: list[dict[str, Any]] = []
    newest_cursor = cursor
    if tag == "rss":
        channel = root.find("channel")
        items = channel.findall("item") if channel is not None else []
        for it in items:
            guid_el = it.find("guid")
            link_el = it.find("link")
            title_el = it.find("title")
            pub_el = it.find("pubDate")
            desc_el = it.find("description")
            link = (link_el.text if link_el is not None else "") or ""
            guid = (guid_el.text if guid_el is not None else "") or link
            if not guid:
                continue
            ts = _parse_rss_date(pub_el.text if pub_el is not None else "")
            if cursor_ts is not None and ts is not None and ts <= cursor_ts:
                continue
            events.append({
                "external_id": guid,
                "title": (title_el.text if title_el is not None else "") or "(untitled)",
                "summary": _strip_html((desc_el.text if desc_el is not None else "") or "")[:280],
                "link": link,
                "occurred_at": _utc_iso(ts) if ts is not None else None,
                "raw": {"guid": guid, "pubDate": pub_el.text if pub_el is not None else None},
            })
            if ts is not None and (newest_cursor is None or ts > float(newest_cursor)):
                newest_cursor = str(ts)
    else:
        ns = {"a": "http://www.w3.org/2005/Atom"}
        entries = root.findall("a:entry", ns)
        for e in entries:
            id_el = e.find("a:id", ns)
            title_el = e.find("a:title", ns)
            updated_el = e.find("a:updated", ns)
            if updated_el is None:
                updated_el = e.find("a:published", ns)
            link_el = e.find("a:link", ns)
            summary_el = e.find("a:summary", ns)
            if summary_el is None:
                summary_el = e.find("a:content", ns)
            ext_id = (id_el.text if id_el is not None else "") or ""
            link = link_el.get("href") if link_el is not None else ""
            if not ext_id:
                ext_id = link
            if not ext_id:
                continue
            ts = None
            if updated_el is not None and updated_el.text:
                try:
                    from datetime import datetime
                    ts = datetime.fromisoformat(updated_el.text.replace("Z", "+00:00")).timestamp()
                except ValueError:
                    ts = None
            if cursor_ts is not None and ts is not None and ts <= cursor_ts:
                continue
            events.append({
                "external_id": ext_id,
                "title": (title_el.text if title_el is not None else "") or "(untitled)",
                "summary": _strip_html((summary_el.text if summary_el is not None else "") or "")[:280],
                "link": link or "",
                "occurred_at": _utc_iso(ts) if ts is not None else None,
                "raw": {"id": ext_id},
            })
            if ts is not None and (newest_cursor is None or ts > float(newest_cursor)):
                newest_cursor = str(ts)
    events.reverse()
    return events, newest_cursor


def _parse_rss_date(s: str) -> float | None:
    if not s:
        return None
    from email.utils import parsedate_to_datetime
    try:
        return parsedate_to_datetime(s).timestamp()
    except (TypeError, ValueError):
        pass
    try:
        from datetime import datetime
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def _strip_html(s: str) -> str:
    return re.sub(r"<[^>]+>", "", s or "").strip()
