#!/usr/bin/env bash
set -euo pipefail

# safe-claude: run claude inside a bubblewrap jail.
# - cwd bound rw (so edits land); everything else minimal
# - $HOME = empty tmpfs; only ~/.claude/.credentials.json from host bound ro
# - repo-local .claude/ masked with tmpfs (no rogue hooks)
# - host ~/.claude memory/sessions/settings NOT exposed
# - network shared by default (Anthropic API); --no-net to cut

usage() {
  cat <<'EOF'
safe-claude — run `claude` inside a bubblewrap jail for untrusted repos.

Usage: safe-claude [safe-claude-opts] [--] [claude args...]

safe-claude options:
  --no-net       Disable network namespace (offline; no Anthropic API).
  --ro           Bind cwd read-only (review mode; claude cannot write).
  -h, --help     Show this help and exit. Does NOT forward to claude;
                 use `safe-claude -- --help` for claude's own help.

Sandbox model:
  - cwd bound rw (or ro with --ro); nothing else writable on host
  - $HOME is an ephemeral tmpfs
  - ~/.claude/.credentials.json bound ro (auth survives)
  - ~/.claude.json copied in (skips onboarding); writes discarded on exit
  - repo-local .claude/ masked with tmpfs (rogue hooks dead)
  - MCP forced empty via --strict-mcp-config
  - host ~/.claude memory/sessions/settings/projects NOT exposed
EOF
}

NET_SHARE=1
RO_CWD=0
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    --no-net)   NET_SHARE=0; shift ;;
    --ro)       RO_CWD=1; shift ;;
    --)         shift; EXTRA_ARGS+=("$@"); break ;;
    *)          EXTRA_ARGS+=("$1"); shift ;;
  esac
done

if ! command -v bwrap >/dev/null; then
  echo "safe-claude: bwrap not on PATH" >&2; exit 1
fi
if ! command -v claude >/dev/null; then
  echo "safe-claude: claude not on PATH" >&2; exit 1
fi

CLAUDE_BIN="$(readlink -f "$(command -v claude)")"
SBX_HOME="$(mktemp -d -t safe-claude-home.XXXXXX)"
MCP_EMPTY="$(mktemp -t safe-claude-mcp.XXXXXX.json)"
echo '{"mcpServers":{}}' > "$MCP_EMPTY"
trap 'rm -rf "$SBX_HOME" "$MCP_EMPTY"' EXIT

CWD_BIND=(--bind "$PWD" "$PWD")
if [[ "$RO_CWD" == 1 ]]; then
  CWD_BIND=(--ro-bind "$PWD" "$PWD")
fi

NET_ARGS=(--share-net)
if [[ "$NET_SHARE" == 0 ]]; then
  NET_ARGS=(--unshare-net)
fi

CRED_ARGS=()
if [[ -f "$HOME/.claude/.credentials.json" ]]; then
  CRED_ARGS+=(--ro-bind "$HOME/.claude/.credentials.json" "$HOME/.claude/.credentials.json")
fi
if [[ -f "$HOME/.claude.json" ]]; then
  mkdir -p "$SBX_HOME"
  cp "$HOME/.claude.json" "$SBX_HOME/.claude.json"
  chmod u+w "$SBX_HOME/.claude.json"
fi

exec bwrap \
  --ro-bind /nix /nix \
  --ro-bind /etc /etc \
  --ro-bind /run/current-system /run/current-system \
  --ro-bind /run/wrappers /run/wrappers \
  --dir /run/user/"$(id -u)" \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --tmpfs "$HOME" \
  --bind "$SBX_HOME" "$HOME" \
  --tmpfs "$HOME/.claude" \
  "${CRED_ARGS[@]}" \
  --ro-bind "$MCP_EMPTY" "$HOME/.mcp-empty.json" \
  "${CWD_BIND[@]}" \
  --tmpfs "$PWD/.claude" \
  --chdir "$PWD" \
  --unshare-all "${NET_ARGS[@]}" \
  --die-with-parent \
  --new-session \
  --clearenv \
  --setenv HOME "$HOME" \
  --setenv USER "${USER:-m}" \
  --setenv PATH "/run/current-system/sw/bin:/run/wrappers/bin" \
  --setenv TERM "${TERM:-xterm-256color}" \
  --setenv LANG "${LANG:-C.UTF-8}" \
  --setenv ANTHROPIC_API_KEY "${ANTHROPIC_API_KEY:-}" \
  "$CLAUDE_BIN" --strict-mcp-config --mcp-config "$HOME/.mcp-empty.json" "${EXTRA_ARGS[@]}"
