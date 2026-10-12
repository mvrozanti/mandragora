---
description: Point the Claude Code statusline at progress-hud
---

Wire progress-hud into the user's statusline. It needs Linux (`/proc`) and `python3` on `PATH`; it has no other dependencies.

1. Read `~/.claude/settings.json` and change only the `statusLine` key.
2. Set it to:

   ```json
   "statusLine": {
     "type": "command",
     "command": "sh -c 'exec python3 -S \"$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/*/progress-hud/*/ | sort -V | tail -1)scripts/statusline.py\"'",
     "refreshInterval": 1
   }
   ```

   `refreshInterval` is what keeps the bars moving while a command runs, because no other statusline trigger fires during a long tool call.
3. When the previous `statusLine.command` was not claude-hud, keep its output by adding `--wrap '<previous command>'` after `statusline.py\"`. claude-hud needs no flag: progress-hud runs it when it is installed. `--wrap ''` shows the bars alone.
4. Verify: `echo '{"session_id":"t"}' | <the command>` exits 0.
