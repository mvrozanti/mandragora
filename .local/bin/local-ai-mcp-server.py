import json
import sys
import urllib.request
import os

OLLAMA_URL = "http://localhost:11434/api/generate"

TOOLS = [
    {
        "name": "ask_gemma",
        "description": (
            "Ask the local Gemma 3 27B model running on Ollama. "
            "Use for: second opinions, local/private reasoning, creative tasks, "
            "tasks where a second model perspective helps, or when you want to "
            "offload work to a fast local model."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "prompt": {
                    "type": "string",
                    "description": "The prompt or question to send to Gemma",
                },
                "system": {
                    "type": "string",
                    "description": "Optional system prompt to guide Gemma's behavior",
                },
            },
            "required": ["prompt"],
        },
    },
    {
        "name": "ask_dolphin",
        "description": (
            "Ask the local Dolphin 70B Uncensored model (Llama 3.1 based) running on Ollama. "
            "This is the most compliant and obedient 70B model available. "
            "Use for: high-quality reasoning without any refusals, moralizing, or lectures."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "prompt": {
                    "type": "string",
                    "description": "The prompt or question to send to Dolphin",
                },
                "system": {
                    "type": "string",
                    "description": "Optional system prompt to guide Dolphin's behavior",
                },
            },
            "required": ["prompt"],
        },
    }
]


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def reply(id, result):
    send({"jsonrpc": "2.0", "id": id, "result": result})


def error(id, code, message):
    send({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})


def call_ollama(model, prompt, system=None):
    # Coordination: this MCP server must respect the mandragora gpu-lock.
    # We use the library directly. PYTHONPATH is assumed to include the lock dir.
    try:
        from gpu_lock import gpu_lock
    except ImportError:
        # Fallback if PYTHONPATH is not set (e.g. manual run)
        import sys
        sys.path.insert(0, "/etc/nixos/mandragora/.local/share/gpu-lock")
        from gpu_lock import gpu_lock

    with gpu_lock.acquire("local-ai-mcp"):
        # 1. Evict other models if any are loaded, to ensure we have VRAM.
        try:
            req_ps = urllib.request.Request("http://localhost:11434/api/ps", method="GET")
            with urllib.request.urlopen(req_ps, timeout=5) as resp:
                loaded = json.loads(resp.read()).get("models", [])
                for m in loaded:
                    m_name = m.get("name", "")
                    if m_name != model and not m_name.startswith(f"{model}:"):
                        req_evict = urllib.request.Request(
                            "http://localhost:11434/api/generate",
                            data=json.dumps({"model": m_name, "keep_alive": 0}).encode(),
                            headers={"Content-Type": "application/json"},
                            method="POST"
                        )
                        with urllib.request.urlopen(req_evict, timeout=5) as r:
                            r.read()
        except Exception:
            pass # Ollama might be down or ps failed; call_ollama will fail anyway

        # 2. Call the model with keep_alive=0 to ensure it unloads immediately after.
        payload = {"model": model, "prompt": prompt, "stream": False, "keep_alive": 0}
        if system:
            payload["system"] = system
        req = urllib.request.Request(
            OLLAMA_URL,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=300) as resp:
            return json.loads(resp.read())["response"]


def main():
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            continue

        method = msg.get("method", "")
        id = msg.get("id")
        params = msg.get("params", {})

        if method == "initialize":
            reply(
                id,
                {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "local-ai", "version": "1.0.0"},
                },
            )
        elif method == "initialized":
            pass
        elif method == "tools/list":
            reply(id, {"tools": TOOLS})
        elif method == "tools/call":
            name = params.get("name")
            args = params.get("arguments", {})
            
            model = None
            if name == "ask_gemma":
                model = "gemma3:27b"
            elif name == "ask_dolphin":
                model = "dolphin-llama3:70b"
            else:
                error(id, -32601, f"Unknown tool: {name}")
                continue
                
            try:
                text = call_ollama(model, args.get("prompt", ""), args.get("system"))
                reply(id, {"content": [{"type": "text", "text": text}]})
            except Exception as e:
                reply(
                    id,
                    {"content": [{"type": "text", "text": f"Ollama error: {e}"}]},
                )
        elif id is not None:
            error(id, -32601, f"Method not found: {method}")


if __name__ == "__main__":
    main()
