#!/usr/bin/env bash
set -euo pipefail

key_file="/run/secrets/deepseek/api_key"

if [ ! -r "$key_file" ]; then
    echo "claude-deepseek: cannot read $key_file" >&2
    echo "claude-deepseek: is the sops secret deepseek/api_key provisioned? run mandragora-switch" >&2
    exit 1
fi

unset ANTHROPIC_API_KEY
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
ANTHROPIC_AUTH_TOKEN="$(cat "$key_file")"
export ANTHROPIC_AUTH_TOKEN
export ANTHROPIC_MODEL="deepseek-v4-pro"
export ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro"
export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
export ANTHROPIC_SMALL_FAST_MODEL="deepseek-v4-flash"

exec claude "$@"
