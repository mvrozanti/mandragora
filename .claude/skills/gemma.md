# Skill: Gemma — Local Model Consultation

## What this does

Sends a prompt to the local **Gemma 3 27B** model running on Ollama via the `ask_gemma` MCP tool.
Gemma runs fully on GPU (RTX 5070 Ti, ~15.2 GB VRAM). No network requests, no cost, no rate limits.

## When to use

- You want a **second opinion** on a plan, code, or reasoning
- The task is **private** (user's personal data, secrets context)
- You need **parallel work**: offload a sub-task to Gemma while you do something else
- You want to test how a **smaller/different model** would respond to something
- The user asks you to consult, compare, or delegate to the local model

## How to use

Call the `ask_gemma` tool from the `gemma` MCP server:

```
tool: ask_gemma
arguments:
  prompt: "<your question or task>"
  system: "<optional system prompt>"   # omit if not needed
```

## Examples

Ask for a code review:
```
ask_gemma(prompt="Review this Python function for bugs:\n\n```python\ndef foo(x):\n    return x * x\n```")
```

Get a second opinion on a Nix expression:
```
ask_gemma(
  prompt="Is this NixOS module correct? ...",
  system="You are an expert in NixOS and the Nix language."
)
```

## Limits

- Context window: Gemma 3 27B supports up to 128K tokens
- No tool use inside Gemma (it's a raw generate call)
- Streaming is disabled — response arrives as one block
- Timeout: 180 seconds

## TUI access

The user can run `gemma` in a terminal to get an oterm-based TUI chat interface,
pre-configured to use gemma3:27b with its own isolated session history.
