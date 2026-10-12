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
4. The HUD shows at most three bars and folds the rest into `+N more running`. Add `--max-rows N` after `statusline.py\"` only when the user asks for a different budget.
5. The bars are drawn in the `rise` style by default: braille cells that fill bottom-up over a dotted floor. Add `--style NAME` after `statusline.py\"` to pick another: `dots` (a lit dot matrix), `rail` (a fill riding a dotted rail), `graph` (a chart of the command's output over its run), `field` (plan-progress's twinkling dot field, two rows per command), `today` (eighth-blocks), `ruler` (eighth-blocks with quarter ticks), `digits` (the number first, then a thin line), `segments` (twenty countable squares), `countdown` (time left and the end time), or `history` (the run against its past durations). `field` takes its accent from a kitty colour file when given `--palette FILE`, such as a theme generator's output; otherwise it uses a default violet.
6. Verify: `echo '{"session_id":"t"}' | <the command>` exits 0.
7. Make sure the plugin is enabled (`claude plugin install progress-hud@<marketplace>`): its `progress-hud` skill is what tells Claude to keep long commands' progress lines flowing.
