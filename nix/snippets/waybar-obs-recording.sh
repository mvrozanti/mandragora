#!/usr/bin/env bash
obs_pid=$(pgrep -x obs)
[[ -z "$obs_pid" ]] && exit 0
if pgrep -P "$obs_pid" -f "ffmpeg" >/dev/null 2>&1; then
  printf '{"text": "⏺", "class": "recording"}\n'
else
  echo ""
fi
