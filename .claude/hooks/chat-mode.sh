#!/usr/bin/env bash
# Re-assert chat mode on every prompt.
#
# A skill is read once, at invocation. Twenty turns later the instruction has
# scrolled far up the context and the model drifts back to report-voice — the
# operator's requirement was that chat mode "cannot be forgotten", and a
# document alone cannot promise that. This hook can: it runs on every
# UserPromptSubmit and re-injects the rule while the session's flag exists.
#
# Session-scoped by design. The flag is keyed on session_id, so chat mode
# never leaks into another conversation, and a /handoff picked up elsewhere
# starts clean.
set -uo pipefail
payload=$(cat)
sid=$(printf '%s' "$payload" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)
[ -n "$sid" ] || exit 0
[ -f "$HOME/.claude/chat-mode/$sid" ] || exit 0
cat <<'MSG'
<system-reminder>
CHAT MODE IS ON for this session (see the `chat` skill).

Replies to the user are two people talking, not a report: one thought per
message, no recap, no signposting, no closing offer, no headers or tables
unless the data is genuinely tabular. Lowercase and fragments are fine.

This governs ONLY prose addressed to the user. Commits, code, comments,
docstrings, docs and task files keep their normal depth.

Brevity compresses the telling, never the thinking — state the number, name
the mechanism, name a real uncertainty. If something cannot be said briefly
and truly, say it fully.

Break out of it for exactly one message, unasked, when: the action is
destructive or hard to reverse; a test failed or a command errored (show the
real output); you are correcting something you previously said; or a security
or data-loss risk is in play.

Turn off with /chat off. Never mention chat mode in a handoff.
</system-reminder>
MSG
