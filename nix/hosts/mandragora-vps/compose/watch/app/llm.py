import json
import logging
import os

import httpx

log = logging.getLogger("watch.llm")

DEEPSEEK_KEY = os.environ.get("WATCH_LLM_DEEPSEEK_KEY", "").strip()
DEEPSEEK_URL = os.environ.get("WATCH_LLM_DEEPSEEK_URL", "https://api.deepseek.com").strip().rstrip("/")
DEEPSEEK_MODEL = os.environ.get("WATCH_LLM_DEEPSEEK_MODEL", "deepseek-chat").strip()

ANTHROPIC_KEY = os.environ.get("WATCH_LLM_ANTHROPIC_KEY", "").strip()
ANTHROPIC_URL = os.environ.get("WATCH_LLM_ANTHROPIC_URL", "https://api.anthropic.com").strip().rstrip("/")
ANTHROPIC_MODEL = os.environ.get("WATCH_LLM_ANTHROPIC_MODEL", "claude-sonnet-5").strip()
ANTHROPIC_VERSION = "2023-06-01"

TIMEOUT = float(os.environ.get("WATCH_LLM_TIMEOUT", "90"))
MAX_TOKENS = int(os.environ.get("WATCH_LLM_MAX_TOKENS", "600"))

QUOTA_SIGNALS = ("quota", "rate limit", "rate-limit", "resource_exhausted", "too many requests")


class NoProviderAvailable(RuntimeError):
    pass


class ProviderFailed(RuntimeError):
    pass


def _quota_like(status: int, body: str) -> bool:
    return status == 429 or any(sig in body.lower() for sig in QUOTA_SIGNALS)


async def _deepseek(system: str, prompt: str) -> str:
    payload = {
        "model": DEEPSEEK_MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.0,
        "max_tokens": MAX_TOKENS,
        "response_format": {"type": "json_object"},
        "stream": False,
    }
    async with httpx.AsyncClient(timeout=TIMEOUT) as c:
        r = await c.post(
            f"{DEEPSEEK_URL}/chat/completions",
            json=payload,
            headers={"Authorization": f"Bearer {DEEPSEEK_KEY}"},
        )
    if r.status_code >= 400:
        raise ProviderFailed(f"deepseek http {r.status_code}: {r.text[:200]}")
    doc = r.json()
    choices = doc.get("choices") or []
    text = (choices[0].get("message", {}).get("content") if choices else "") or ""
    if not text:
        raise ProviderFailed(f"deepseek empty response: {json.dumps(doc)[:200]}")
    return text


async def _anthropic(system: str, prompt: str) -> str:
    payload = {
        "model": ANTHROPIC_MODEL,
        "max_tokens": MAX_TOKENS,
        "temperature": 0.0,
        "system": system,
        "messages": [{"role": "user", "content": prompt}],
    }
    async with httpx.AsyncClient(timeout=TIMEOUT) as c:
        r = await c.post(
            f"{ANTHROPIC_URL}/v1/messages",
            json=payload,
            headers={
                "x-api-key": ANTHROPIC_KEY,
                "anthropic-version": ANTHROPIC_VERSION,
                "content-type": "application/json",
            },
        )
    if r.status_code >= 400:
        raise ProviderFailed(f"anthropic http {r.status_code}: {r.text[:200]}")
    doc = r.json()
    blocks = doc.get("content") or []
    text = "".join(b.get("text", "") for b in blocks if b.get("type") == "text")
    if not text:
        raise ProviderFailed(f"anthropic empty response: {json.dumps(doc)[:200]}")
    return text


PROVIDERS = (
    ("deepseek", lambda: bool(DEEPSEEK_KEY), _deepseek),
    ("anthropic", lambda: bool(ANTHROPIC_KEY), _anthropic),
)


def available() -> list[str]:
    return [name for name, ready, _ in PROVIDERS if ready()]


async def complete(system: str, prompt: str) -> tuple[str, str]:
    ready = available()
    if not ready:
        raise NoProviderAvailable(
            "no model provider configured — set WATCH_LLM_DEEPSEEK_KEY "
            "(or WATCH_LLM_ANTHROPIC_KEY) in the container's .env"
        )
    problems = []
    for name, is_ready, call in PROVIDERS:
        if not is_ready():
            continue
        try:
            return await call(system, prompt), name
        except ProviderFailed as exc:
            problems.append(f"{name}: {exc}")
            log.warning("provider %s failed, trying next: %s", name, exc)
        except Exception as exc:
            problems.append(f"{name}: {type(exc).__name__}: {exc}")
            log.warning("provider %s errored, trying next: %s", name, exc)
    raise NoProviderAvailable("every configured provider failed — " + " · ".join(problems))
