import json
import os
import sys

from aiohttp import ClientSession, ClientTimeout, web

UPSTREAM = os.environ.get("OLLAMA_UPSTREAM", "http://127.0.0.1:11434").rstrip("/")
LISTEN_HOST = os.environ.get("LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "11435"))
PROMPT_PATH = os.environ["MVR_SYSTEM_PROMPT_FILE"]

with open(PROMPT_PATH) as fh:
    SYSTEM_PROMPT = fh.read()

INJECT_PATHS = {"/api/chat", "/v1/chat/completions"}
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length",
}


def inject(body: bytes) -> bytes:
    try:
        data = json.loads(body)
    except Exception as exc:
        print(f"ollama-context-proxy: skip injection (bad json): {exc}", file=sys.stderr)
        return body
    msgs = data.get("messages")
    if not isinstance(msgs, list):
        return body
    if msgs and msgs[0].get("role") == "system":
        return body
    msgs.insert(0, {"role": "system", "content": SYSTEM_PROMPT})
    data["messages"] = msgs
    return json.dumps(data).encode()


async def proxy(request: web.Request) -> web.StreamResponse:
    body = await request.read()
    if request.method == "POST" and request.path in INJECT_PATHS and body:
        body = inject(body)

    headers = {k: v for k, v in request.headers.items() if k.lower() not in HOP_BY_HOP}
    url = UPSTREAM + request.rel_url.path_qs

    timeout = ClientTimeout(total=None, sock_read=None, sock_connect=30)
    async with ClientSession(timeout=timeout, auto_decompress=False) as session:
        async with session.request(request.method, url, headers=headers, data=body, allow_redirects=False) as upstream:
            resp_headers = {k: v for k, v in upstream.headers.items() if k.lower() not in HOP_BY_HOP}
            resp = web.StreamResponse(status=upstream.status, reason=upstream.reason, headers=resp_headers)
            await resp.prepare(request)
            async for chunk in upstream.content.iter_any():
                await resp.write(chunk)
            await resp.write_eof()
            return resp


def main() -> None:
    app = web.Application(client_max_size=1024 * 1024 * 1024)
    app.router.add_route("*", "/{tail:.*}", proxy)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None)


if __name__ == "__main__":
    main()
