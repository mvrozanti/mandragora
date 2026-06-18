import asyncio
import ipaddress
import re
import socket
import time
from collections import deque
from dataclasses import dataclass, field
from html import unescape
from urllib.parse import urljoin, urlparse, urldefrag
from urllib.robotparser import RobotFileParser

import httpx
from bs4 import BeautifulSoup

USER_AGENT = "mandragora-spider/1.0 (+https://spider.mvr.ac)"

EMAIL_RE = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")
PHONE_RE = re.compile(r"(?:(?:\+|00)\d{1,3}[\s.\-]?)?(?:\(\d{1,4}\)[\s.\-]?)?\d{2,4}(?:[\s.\-]?\d{2,4}){1,4}")

EXTRACTORS = {
    "email": EMAIL_RE,
    "phone": PHONE_RE,
}

SCOPE_HOST = "host"
SCOPE_DOMAIN = "domain"
SCOPE_ANY = "any"

MAX_DEPTH_CAP = 99
MAX_PAGES_CAP = 2000
CONCURRENCY_CAP = 16


def _registrable(host: str) -> str:
    parts = host.split(".")
    if len(parts) <= 2:
        return host
    return ".".join(parts[-2:])


def _host_is_blocked(host: str) -> bool:
    try:
        infos = socket.getaddrinfo(host, None)
    except Exception:
        return True
    for info in infos:
        try:
            ip = ipaddress.ip_address(info[4][0])
        except ValueError:
            return True
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_reserved
            or ip.is_multicast
            or ip.is_unspecified
        ):
            return True
    return False


@dataclass
class Options:
    start_url: str
    terms: list = field(default_factory=list)
    use_regex: bool = False
    case_insensitive: bool = True
    match_html: bool = False
    scope: str = SCOPE_HOST
    max_depth: int = 2
    max_pages: int = 200
    concurrency: int = 6
    respect_robots: bool = True
    timeout: float = 15.0
    extractors: list = field(default_factory=list)
    custom_regex: str = ""
    check_broken: bool = False

    def clamp(self):
        self.max_depth = max(0, min(int(self.max_depth), MAX_DEPTH_CAP))
        self.max_pages = max(1, min(int(self.max_pages), MAX_PAGES_CAP))
        self.concurrency = max(1, min(int(self.concurrency), CONCURRENCY_CAP))
        self.timeout = max(3.0, min(float(self.timeout), 30.0))


def _compile_terms(opts: Options):
    flags = re.IGNORECASE if opts.case_insensitive else 0
    pats = []
    for t in opts.terms:
        t = t.strip()
        if not t:
            continue
        pats.append(re.compile(t if opts.use_regex else re.escape(t), flags))
    return pats


def _snippet(text: str, m: re.Match, pad: int = 60) -> str:
    s = max(0, m.start() - pad)
    e = min(len(text), m.end() + pad)
    frag = text[s:e].replace("\n", " ").strip()
    return ("…" if s > 0 else "") + frag + ("…" if e < len(text) else "")


def _in_scope(start_host: str, link_host: str, scope: str) -> bool:
    if scope == SCOPE_ANY:
        return True
    if scope == SCOPE_HOST:
        return link_host == start_host
    return _registrable(link_host) == _registrable(start_host)


class Spider:
    def __init__(self, opts: Options):
        opts.clamp()
        self.opts = opts
        self.term_pats = _compile_terms(opts)
        self.custom_pat = None
        if opts.custom_regex.strip():
            flags = re.IGNORECASE if opts.case_insensitive else 0
            self.custom_pat = re.compile(opts.custom_regex.strip(), flags)
        self.start = urldefrag(opts.start_url)[0]
        self.start_host = urlparse(self.start).hostname or ""
        self.seen = set()
        self.queued = 0
        self.robots = {}
        self.stats = {
            "pages_crawled": 0,
            "matches": 0,
            "links_seen": 0,
            "broken": 0,
            "errors": 0,
        }
        self._bg = set()
        self._checked = set()
        self._stop = False

    async def _robot_ok(self, client, url: str) -> bool:
        if not self.opts.respect_robots:
            return True
        p = urlparse(url)
        base = f"{p.scheme}://{p.netloc}"
        rp = self.robots.get(base)
        if rp is None:
            rp = RobotFileParser()
            try:
                r = await client.get(base + "/robots.txt")
                if r.status_code == 200:
                    rp.parse(r.text.splitlines())
                else:
                    rp.parse([])
            except Exception:
                rp.parse([])
            self.robots[base] = rp
        try:
            return rp.can_fetch(USER_AGENT, url)
        except Exception:
            return True

    def _match(self, text: str, html: str):
        hay = html if self.opts.match_html else text
        snippets = []
        if not self.term_pats:
            return False, snippets
        for pat in self.term_pats:
            m = pat.search(hay)
            if not m:
                return False, []
            snippets.append({"term": pat.pattern, "snippet": _snippet(hay, m)})
        return True, snippets

    def _extract(self, text: str, html: str):
        out = {}
        for name in self.opts.extractors:
            pat = EXTRACTORS.get(name)
            if pat:
                hits = sorted(set(pat.findall(text)))
                if hits:
                    out[name] = hits[:200]
        if self.custom_pat:
            hits = sorted({m.group(0) for m in self.custom_pat.finditer(html)})
            if hits:
                out["custom"] = hits[:200]
        return out

    async def run(self):
        limits = httpx.Limits(max_connections=self.opts.concurrency * 2)
        async with httpx.AsyncClient(
            headers={"User-Agent": USER_AGENT},
            timeout=self.opts.timeout,
            follow_redirects=False,
            limits=limits,
        ) as client:
            queue = asyncio.Queue()
            out = asyncio.Queue()

            if _host_is_blocked(self.start_host):
                yield {"type": "error", "url": self.start, "error": "start host resolves to a private/blocked address"}
                yield {"type": "done", "stats": self.stats}
                return

            self.seen.add(self.start)
            self.queued = 1
            await queue.put((self.start, 0))

            sem = asyncio.Semaphore(self.opts.concurrency)
            active = {"n": 0}

            async def worker():
                while True:
                    try:
                        url, depth = await asyncio.wait_for(queue.get(), timeout=0.3)
                    except asyncio.TimeoutError:
                        if active["n"] == 0 and queue.empty():
                            return
                        continue
                    active["n"] += 1
                    try:
                        async with sem:
                            await self._visit(client, url, depth, queue, out)
                    finally:
                        active["n"] -= 1
                        queue.task_done()

            workers = [asyncio.create_task(worker()) for _ in range(self.opts.concurrency)]

            async def joiner():
                await asyncio.gather(*workers)
                while self._bg:
                    await asyncio.gather(*list(self._bg), return_exceptions=True)
                await out.put(None)

            jtask = asyncio.create_task(joiner())

            while True:
                ev = await out.get()
                if ev is None:
                    break
                yield ev

            await jtask
            yield {"type": "done", "stats": self.stats}

    async def _follow_redirect(self, client, resp, url):
        loc = resp.headers.get("location")
        if not loc:
            return None
        nxt = urljoin(url, loc)
        host = urlparse(nxt).hostname or ""
        if urlparse(nxt).scheme not in ("http", "https") or _host_is_blocked(host):
            return None
        return nxt

    async def _visit(self, client, url, depth, queue, out):
        if self.stats["pages_crawled"] >= self.opts.max_pages:
            return
        if not await self._robot_ok(client, url):
            await out.put({"type": "skip", "url": url, "reason": "robots"})
            return
        cur = url
        try:
            resp = None
            for _ in range(5):
                resp = await client.get(cur)
                if resp.status_code in (301, 302, 303, 307, 308):
                    nxt = await self._follow_redirect(client, resp, cur)
                    if not nxt:
                        break
                    cur = nxt
                    continue
                break
        except Exception as e:
            self.stats["errors"] += 1
            await out.put({"type": "error", "url": url, "error": str(e)[:200]})
            return

        self.stats["pages_crawled"] += 1
        status = resp.status_code
        ctype = resp.headers.get("content-type", "")

        if "html" not in ctype.lower():
            await out.put({"type": "page", "url": cur, "status": status, "depth": depth, "title": "", "html_page": False, "matched": False, "snippets": [], "extracted": {}})
            return

        html = resp.text
        soup = BeautifulSoup(html, "html.parser")
        for tag in soup(["script", "style", "noscript"]):
            tag.decompose()
        title = (soup.title.string.strip() if soup.title and soup.title.string else "")
        text = re.sub(r"\s+", " ", soup.get_text(" ")).strip()

        matched, snippets = self._match(text, html)
        if matched:
            self.stats["matches"] += 1
        extracted = self._extract(text, html)

        await out.put({
            "type": "page",
            "url": cur,
            "status": status,
            "depth": depth,
            "title": title[:200],
            "html_page": True,
            "matched": matched,
            "snippets": snippets[:5],
            "extracted": extracted,
        })

        links = []
        for a in soup.find_all("a", href=True):
            nxt = urldefrag(urljoin(cur, a["href"]))[0]
            p = urlparse(nxt)
            if p.scheme not in ("http", "https"):
                continue
            links.append((nxt, a.get_text(" ").strip()[:120]))

        for nxt, anchor in links:
            self.stats["links_seen"] += 1
            host = urlparse(nxt).hostname or ""
            in_scope = _in_scope(self.start_host, host, self.opts.scope)

            if self.opts.check_broken and nxt not in self._checked:
                self._checked.add(nxt)
                t = asyncio.create_task(self._check_link(client, nxt, cur, anchor, out))
                self._bg.add(t)
                t.add_done_callback(self._bg.discard)

            if depth >= self.opts.max_depth:
                continue
            if not in_scope:
                continue
            if nxt in self.seen:
                continue
            if self.queued >= self.opts.max_pages:
                continue
            if _host_is_blocked(host):
                continue
            self.seen.add(nxt)
            self.queued += 1
            await queue.put((nxt, depth + 1))

    async def _check_link(self, client, url, src, anchor, out):
        host = urlparse(url).hostname or ""
        if _host_is_blocked(host):
            return
        try:
            r = await client.head(url)
            if r.status_code >= 400 or r.status_code in (405,):
                r = await client.get(url)
            if r.status_code >= 400:
                self.stats["broken"] += 1
                await out.put({"type": "broken", "url": url, "status": r.status_code, "from": src, "anchor": anchor})
        except Exception as e:
            self.stats["broken"] += 1
            await out.put({"type": "broken", "url": url, "status": 0, "from": src, "anchor": anchor, "error": str(e)[:120]})
