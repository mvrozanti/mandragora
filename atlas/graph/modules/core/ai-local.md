---
type: module
layer: core
tags: [module, core, ai, nvidia]
path: modules/core/ai-local.nix
---

# ai-local.nix

The local AI stack — Ollama + the agentic wrapper scripts. Gates on VRAM.

## Role
- Defines `mandragora.hardware.gpu.vramGB` consumer; asserts `>= 16` when agentic enabled.
- Wraps [[../../scripts/gemma]] and [[../../scripts/local-ai-mcp-server]] as Python derivations under `mkPythonBin`.
- Enables `services.ollama` + persistent `/persistent/var/lib/private/ollama` state (via [[impermanence]]).

## Connections
- Up: [[../_index|Modules]]
- Consumes: [[graphics]] (`config.mandragora.hardware.gpu`)
- Pairs with: [[impermanence]] (Ollama state survives), [[monitoring]] (GPU metrics)
- Scripts: [[../../scripts/gemma]], [[../../scripts/local-ai-mcp-server]]
- Touches: [[../../concepts/ai-stack]], [[../../concepts/nvidia]]
