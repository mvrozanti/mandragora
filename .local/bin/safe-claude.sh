#!/usr/bin/env bash
set -euo pipefail

# safe-claude: run claude inside a bubblewrap jail.
# - cwd bound rw (so edits land); everything else minimal
# - $HOME = empty tmpfs; only ~/.claude/.credentials.json from host bound ro
# - repo-local .claude/ masked with tmpfs (no rogue hooks)
# - host ~/.claude memory/sessions/settings NOT exposed
# - network shared by default (Anthropic API); --no-net to cut

NET_SHARE=1
RO_CWD=0
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
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
  CRED_ARGS=(--ro-bind "$HOME/.claude/.credentials.json" "$HOME/.claude/.credentials.json")
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
