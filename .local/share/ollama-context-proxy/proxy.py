import json
import os
import sys

from aiohttp import ClientSession, ClientTimeout, web

UPSTREAM = os.environ.get("OLLAMA_UPSTREAM", "http://127.0.0.1:11434").rstrip("/")
LISTEN_HOST = os.environ.get("LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "11435"))
PROMPT_PATH = os.environ["MVR_SYSTEM_PROMPT_FILE"]
DEFAULT_THINK = os.environ.get("MVR_DEFAULT_THINK", "true").lower() == "true"

with open(PROMPT_PATH) as fh:
    SYSTEM_PROMPT = fh.read()

INJECT_PATHS = {"/api/chat", "/v1/chat/completions"}
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length",
}
THINK_CMDS = (
    ("/nothink", False),
    ("/no_think", False),
    ("/think", True),
)


def _apply_think_cmd(text: str):
    stripped = text.lstrip()
    low = stripped.lower()
    for prefix, value in THINK_CMDS:
        if low.startswith(prefix):
            rest = stripped[len(prefix):]
            if not rest or rest[0].isspace():
                return value, rest.lstrip()
    return None, None


def inject(body: bytes):
    try:
        data = json.loads(body)
    except Exception as exc:
        print(f"ollama-context-proxy: skip injection (bad json): {exc}", file=sys.stderr)
        return body, DEFAULT_THINK

    think_state = DEFAULT_THINK
    msgs = data.get("messages")
    if isinstance(msgs, list):
        if not msgs or msgs[0].get("role") != "system":
            msgs.insert(0, {"role": "system", "content": SYSTEM_PROMPT})

        for msg in msgs:
            if msg.get("role") != "user":
                continue
            content = msg.get("content")
            if not isinstance(content, str):
                continue
            value, rewritten = _apply_think_cmd(content)
            if value is not None:
                think_state = value
                msg["content"] = rewritten

        data["think"] = think_state
        data["messages"] = msgs

    return json.dumps(data).encode(), think_state


def strip_thinking_line(line: bytes) -> bytes:
    if not line.strip():
        return line
    try:
        obj = json.loads(line)
    except Exception:
        return line
    msg = obj.get("message")
    if isinstance(msg, dict):
        for key in ("thinking", "reasoning", "reasoning_content"):
            msg.pop(key, None)
    for choice in obj.get("choices", []) or []:
        delta = choice.get("delta") or {}
        for key in ("thinking", "reasoning", "reasoning_content"):
            delta.pop(key, None)
    return json.dumps(obj).encode()


async def stream_passthrough(upstream, resp):
    async for chunk in upstream.content.iter_any():
        await resp.write(chunk)


async def stream_strip_thinking(upstream, resp):
    buffer = b""
    async for chunk in upstream.content.iter_any():
        buffer += chunk
        while b"\n" in buffer:
            line, buffer = buffer.split(b"\n", 1)
            await resp.write(strip_thinking_line(line) + b"\n")
    if buffer:
        await resp.write(strip_thinking_line(buffer))


async def proxy(request: web.Request) -> web.StreamResponse:
    body = await request.read()
    think_state = DEFAULT_THINK
    if request.method == "POST" and request.path in INJECT_PATHS and body:
        body, think_state = inject(body)

    headers = {k: v for k, v in request.headers.items() if k.lower() not in HOP_BY_HOP}
    url = UPSTREAM + request.rel_url.path_qs

    timeout = ClientTimeout(total=None, sock_read=None, sock_connect=30)
    async with ClientSession(timeout=timeout, auto_decompress=False) as session:
        async with session.request(request.method, url, headers=headers, data=body, allow_redirects=False) as upstream:
            resp_headers = {k: v for k, v in upstream.headers.items() if k.lower() not in HOP_BY_HOP}
            resp = web.StreamResponse(status=upstream.status, reason=upstream.reason, headers=resp_headers)
            await resp.prepare(request)
            should_strip = (not think_state) and request.path in INJECT_PATHS and upstream.status == 200
            if should_strip:
                await stream_strip_thinking(upstream, resp)
            else:
                await stream_passthrough(upstream, resp)
            await resp.write_eof()
            return resp


def main() -> None:
    app = web.Application(client_max_size=1024 * 1024 * 1024)
    app.router.add_route("*", "/{tail:.*}", proxy)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None)


if __name__ == "__main__":
    main()
