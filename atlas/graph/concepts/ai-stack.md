---
type: concept
tags: [concept, ai]
---

# Local AI stack

Ollama running locally on the RTX 5070 Ti, plus a thin layer of wrappers and MCP servers that make the models reachable from CLI, TUI, and agentic tools.

Gated on `mandragora.hardware.gpu.vramGB >= 16` from [[nvidia]].

## Touched by

- [[../modules/core/ai-local]] — Ollama service + script wrappers
- [[../modules/user/skills]] — BMAD skill ecosystem on top
- [[../modules/user/bots]] — Telegram image-gen bot
- [[../scripts/gemma]] — everyday CLI for the local LLM
- [[../scripts/local-ai-mcp-server]] — MCP exposure for Crush
- [[../packages/claude-code]] — the agentic CLI host
- [[../packages/rtk]] — token-reduction proxy
- [[../packages/bot-python]] — bot Python env
- [[../configs/claude]], [[../configs/crush]] — clients

See: [[skill-ecosystem]], [[../../architecture]]
