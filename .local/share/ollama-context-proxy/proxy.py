import json
import os
import re
import sys

import aiohttp
from aiohttp import ClientSession, ClientTimeout, web

UPSTREAM = os.environ.get("OLLAMA_UPSTREAM", "http://127.0.0.1:11434").rstrip("/")
LISTEN_HOST = os.environ.get("LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "11435"))
PROMPT_PATH = os.environ["MVR_SYSTEM_PROMPT_FILE"]

_IMPORT_LINE = re.compile(r"^@\S+\s*$")


def _load_prompt(path: str) -> str:
    with open(path) as fh:
        lines = fh.read().splitlines()
    kept = [ln for ln in lines if not _IMPORT_LINE.match(ln)]
    return "\n".join(kept).strip()


SYSTEM_PROMPT = _load_prompt(PROMPT_PATH)
SEP = "\n\n---\n\n"

INJECT_CHAT = {"/api/chat", "/v1/chat/completions"}
INJECT_GEN = {"/api/generate"}
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length",
}


def inject_chat(data: dict) -> dict:
    msgs = data.get("messages")
    if not isinstance(msgs, list):
        return data
    first = msgs[0] if msgs else None
    if isinstance(first, dict) and first.get("role") == "system":
        existing = first.get("content")
        if isinstance(existing, str):
            first["content"] = SYSTEM_PROMPT + SEP + existing
            return data
    msgs.insert(0, {"role": "system", "content": SYSTEM_PROMPT})
    data["messages"] = msgs
    return data


def inject_gen(data: dict) -> dict:
    existing = data.get("system")
    if isinstance(existing, str) and existing.strip():
        data["system"] = SYSTEM_PROMPT + SEP + existing
    else:
        data["system"] = SYSTEM_PROMPT
    return data


def inject(path: str, body: bytes) -> bytes:
    try:
        data = json.loads(body)
    except Exception as exc:
        print(f"ollama-context-proxy: skip injection (bad json): {exc}", file=sys.stderr)
        return body
    if not isinstance(data, dict):
        return body
    if path in INJECT_CHAT:
        data = inject_chat(data)
    elif path in INJECT_GEN:
        data = inject_gen(data)
    else:
        return body
    return json.dumps(data).encode()


async def proxy(request: web.Request) -> web.StreamResponse:
    body = await request.read()
    if request.method == "POST" and request.path in (INJECT_CHAT | INJECT_GEN) and body:
        body = inject(request.path, body)

    headers = {k: v for k, v in request.headers.items() if k.lower() not in HOP_BY_HOP}
    url = UPSTREAM + request.rel_url.path_qs

    timeout = ClientTimeout(total=None, sock_read=None, sock_connect=30)
    try:
        async with ClientSession(timeout=timeout, auto_decompress=False) as session:
            async with session.request(request.method, url, headers=headers, data=body, allow_redirects=False) as upstream:
                resp_headers = {k: v for k, v in upstream.headers.items() if k.lower() not in HOP_BY_HOP}
                resp = web.StreamResponse(status=upstream.status, reason=upstream.reason, headers=resp_headers)
                await resp.prepare(request)
                async for chunk in upstream.content.iter_any():
                    await resp.write(chunk)
                await resp.write_eof()
                return resp
    except aiohttp.ClientError as exc:
        print(f"ollama-context-proxy: upstream error: {exc}", file=sys.stderr)
        return web.json_response({"error": f"upstream unreachable: {exc}"}, status=502)


def main() -> None:
    app = web.Application(client_max_size=1024 * 1024 * 1024)
    app.router.add_route("*", "/{tail:.*}", proxy)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None)


if __name__ == "__main__":
    main()
