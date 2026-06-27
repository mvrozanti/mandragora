# claudecodebrowser stack — diagnostic order

ClaudeCodeBrowser is a 3-layer system. The layers fail **independently**
and **none of them flags the others**. Every prior debug-loop where
"the browser tools don't work" cost real time because the agent
concluded "browser dead" from one layer's signal and didn't check
the other two.

## The layers

```
┌────────────────────────────────────────────────────────────┐
│ Layer A: Claude Code session ↔ MCP transport              │
│   - schema registration; ToolSearch surfaces the deferred  │
│     tool names                                             │
│   - latched per session — if it goes down mid-session the  │
│     harness DOES NOT auto-restore the tools                │
└────────────────────────────────────────────────────────────┘
                          │ stdio JSON-RPC
                          ▼
┌────────────────────────────────────────────────────────────┐
│ Layer B: claudecodebrowser-mcp ↔ local HTTP server        │
│   - python stdio_wrapper.py → http://127.0.0.1:8765        │
│   - this is what `claude mcp list` health-checks           │
│   - `✓ Connected` here proves NOTHING about A or C         │
└────────────────────────────────────────────────────────────┘
                          │ HTTP + X-API-Key
                          ▼
┌────────────────────────────────────────────────────────────┐
│ Layer C: HTTP server ↔ Firefox extension                  │
│   - native-messaging host (~/.mozilla/native-messaging-     │
│     hosts/claudecodebrowser.json) ↔ extension XPI          │
│   - extension green badge ONLY reflects extension-internal │
│     state — NOT whether the extension is currently feeding │
│     the HTTP server                                        │
│   - if this is broken: HTTP `/health` returns              │
│     `"browsers_connected": 0`                              │
└────────────────────────────────────────────────────────────┘
```

## Diagnostic order

Run all three. Layers can be green out-of-order — don't stop early.

### 1. Layer A — session ToolSearch

```
ToolSearch query="select:mcp__claudecodebrowser__browser_get_tabs"
```

- Returns the schema: A is up.
- "No matching deferred tools found": A is **latched dead**. No
  command you can run from inside this session restores it. You
  must restart the Claude Code session (`/resume` preserves the
  transcript).
- If the session is new and ToolSearch still fails: skip to step 2.

### 2. Layer B — MCP transport health

```bash
claude mcp list
claude mcp get claudecodebrowser
```

`Status: ✓ Connected` → Layer B is up. **This says nothing about C.**

If `Status: ✗` or absent: the stdio wrapper or its Python deps are
broken. Inspect `/nix/store/.../mcp-server/stdio_wrapper.py` and the
process tree.

### 3. Layer C — HTTP server + extension link

```bash
TOKEN=$(cat ~/.claudecodebrowser/api_token)
curl -sf http://127.0.0.1:8765/health -H "X-API-Key: $TOKEN"
```

Check the `browsers_connected` field in the JSON:

- `"browsers_connected": ≥1` → C is up. End-to-end works (assuming
  A and B were also up).
- `"browsers_connected": 0` → extension is NOT currently piped into
  the server, no matter what its green badge says. Fix: reload the
  extension in Firefox (`about:addons` → ClaudeCodeBrowser →
  disable + re-enable). If that fails, restart Firefox. If THAT
  fails, restart the native-host process.

## Common false conclusions to avoid

| Signal | Wrong conclusion | Right conclusion |
|---|---|---|
| Extension badge green | "browser MCP works" | Only proves the extension thinks it loaded. Says nothing about whether it's talking to the HTTP server right now. |
| `claude mcp list` ✓ Connected | "tools should work" | Layer B is up. The session's deferred-tool table (A) may still be stale, and the extension's link (C) may be broken. |
| `system-reminder` says "MCP server disconnected" | "the server is dead" | The **harness's view** of layer A is dead. Layer B + C may be perfectly fine. Restart the session to re-evaluate A. |
| Tools worked an hour ago, don't now, nothing changed | "broken install" | Most likely: session latched A in the dead state when the extension reloaded briefly. Restart the Claude Code session. |

## Source paths (NixOS install, as of 2026-05-27)

- Binary symlink: `/run/current-system/sw/bin/claudecodebrowser-mcp`
- Real path: `/nix/store/*-claudecodebrowser-mcp/bin/claudecodebrowser-mcp`
- Source: `/nix/store/21k0b33qjchw83p54lsgynf4vfd93sj1-source/`
  - `mcp-server/stdio_wrapper.py` — Layer B
  - `native-host/claudecodebrowser_host.py` — Layer C server side
  - `extension/` — XPI source for Layer C client side
  - `agent/browser_agent.py` — high-level python client that goes
    through the same HTTP at 127.0.0.1:8765, so it is **NOT a
    bypass** when C is broken
- API token: `~/.claudecodebrowser/api_token`
- HTTP port: `8765` (override with `CLAUDE_BROWSER_HTTP_PORT`)
- Native-messaging manifest:
  `~/.mozilla/native-messaging-hosts/claudecodebrowser.json`

## When the user says "the extension says connected"

That is **Layer C client-side state** and is necessary but not
sufficient. Verify the full chain — A via ToolSearch, B via
`claude mcp list`, C via curl `/health` — before either claiming
the tools work or claiming they don't. Cite which layer failed.
