import asyncio
import logging
from typing import Any

import httpx
from bs4 import BeautifulSoup
from ddgs import DDGS

logger = logging.getLogger(__name__)

_USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0 Safari/537.36"
)
_FETCH_TIMEOUT = 15.0
_FETCH_MAX_BYTES = 4 * 1024 * 1024
_TEXT_MAX_CHARS = 8000
_DROP_TAGS = ("script", "style", "noscript", "template", "svg", "nav", "footer", "header", "aside", "form")


def _ddgs_text_sync(query: str, max_results: int) -> list[dict[str, Any]]:
    with DDGS() as ddgs:
        return list(ddgs.text(query, max_results=max_results))


async def web_search(query: str, max_results: int = 5) -> str:
    if not query.strip():
        return "Error: empty query"
    max_results = max(1, min(max_results, 10))
    try:
        results = await asyncio.to_thread(_ddgs_text_sync, query, max_results)
    except Exception as exc:
        logger.exception("ddgs failed")
        return f"Error: search failed: {type(exc).__name__}: {exc}"
    if not results:
        return f"No results for: {query}"
    lines: list[str] = []
    for i, r in enumerate(results, 1):
        title = (r.get("title") or "").strip()
        url = (r.get("href") or r.get("url") or "").strip()
        snippet = (r.get("body") or "").strip()
        lines.append(f"[{i}] {title}\n    {url}\n    {snippet}")
    return "\n\n".join(lines)


def _extract_text(html: str) -> str:
    soup = BeautifulSoup(html, "lxml")
    for tag in soup(_DROP_TAGS):
        tag.decompose()
    main = soup.find("main") or soup.find("article") or soup.body or soup
    text = main.get_text(separator="\n", strip=True)
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    out: list[str] = []
    prev = ""
    for ln in lines:
        if ln == prev:
            continue
        out.append(ln)
        prev = ln
    return "\n".join(out)


async def fetch_url(url: str, max_chars: int = _TEXT_MAX_CHARS) -> str:
    url = url.strip()
    if not url:
        return "Error: empty url"
    if not (url.startswith("http://") or url.startswith("https://")):
        url = "https://" + url
    max_chars = max(500, min(max_chars, 32000))
    try:
        async with httpx.AsyncClient(
            timeout=_FETCH_TIMEOUT,
            follow_redirects=True,
            headers={"User-Agent": _USER_AGENT, "Accept": "text/html,*/*;q=0.8"},
        ) as client:
            resp = await client.get(url)
    except httpx.HTTPError as exc:
        return f"Error: {type(exc).__name__}: {exc}"

    final_url = str(resp.url)
    ctype = resp.headers.get("content-type", "").lower()
    body = resp.content[:_FETCH_MAX_BYTES]

    if "html" in ctype or "<html" in body[:512].lower().decode(errors="replace"):
        try:
            text = _extract_text(body.decode(resp.encoding or "utf-8", errors="replace"))
        except Exception:
            logger.exception("html extract failed")
            text = body.decode("utf-8", errors="replace")
    else:
        text = body.decode("utf-8", errors="replace")

    header = f"URL: {final_url}\nStatus: {resp.status_code}\nContent-Type: {ctype}\n\n"
    if len(text) > max_chars:
        head = text[: max_chars // 2]
        tail = text[-max_chars // 2 :]
        omitted = len(text) - len(head) - len(tail)
        text = f"{head}\n\n[... {omitted} chars truncated ...]\n\n{tail}"
    return header + text
