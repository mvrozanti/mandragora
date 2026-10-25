# Past conversations are found through a derived full-text index, not the picker

Date: 2026-10-25. Status: accepted.

## Context

Finding where a phrase or subject was discussed with Claude Code meant
remembering the directory, opening the picker there and reading sessions
one by one. Two facts pinned before any design: `cleanupPeriodDays`
defaulted to 30 and nothing overrode it, so `history.jsonl` named 1,573
sessions while 268 transcripts remained on disk; and `claude --resume`
never changes the working directory, so any cross-directory finder has
to reopen the session where it lived. The built-in picker widens to all
projects with Ctrl+A but filters only names, titles and first prompts,
and the transcript format is documented as unstable.

## Axis

Where does the searchable record of a past conversation live, and who
turns a remembered phrase into a running session?

## Directions considered

| Direction | Answer to the axis |
|---|---|
| Today | Claude's picker index, scoped to the directory you started in |
| Learn the picker | the same index widened with Ctrl+A and fed names |
| Your prompts are the index | `history.jsonl`, fuzzy, prompts only |
| Grep the raw log | the transcripts themselves, ripgrep per keystroke |
| **Index it** | a derived FTS5 index that keeps the text after the transcript is gone |
| Sessions become notes | a Haiku-written note per session; the finder searches notes |
| Keep them alive in tmux | the running process; windows named by title |

Eight scenarios were traced through each: an exact phrase, a subject
worded differently, resuming into the right directory, a transcript
past retention, a release renaming a field, ten times the history,
text Claude said, and a session missing from results.

## Decision

`claude-find`: one SQLite FTS5 file at `~/.local/share/claude-find/index.db`
with one row per user or assistant turn (porter stemming), one row per
session (cwd, title, dates, whether a transcript still exists). The
indexer runs on every launch, incrementally by mtime, and ingests
`history.jsonl` prompts for sessions with no transcript, so the five
months cleanup already deleted are searchable though not resumable.
The finder is fzf in disabled mode reloading a ranked query per
keystroke, with a preview of the matching turns. Enter runs
`claude-reopen`, which opens a tmux window at the session's original
cwd running `claude --resume`. Retention is set to 90 days by a
home-manager activation step that merges `cleanupPeriodDays` into
`~/.claude/settings.json`; the index keeps the text past that.
Measured: full build 2.3 s for the transcripts, 14 MB with history,
queries under 60 ms end to end including interpreter start.

## Accepted consequences

- **Gives up:** a second copy of the text that can go stale; privacy:
  every conversation in one greppable 14 MB file under `~/.local/share`.
- **Undo:** delete `index.db` and the package; raw transcripts untouched.
  Two-way door.
- **Operates:** one file to back up; a parser to patch when a release
  changes the format. The finder's header says "index N session(s)
  behind" and `claude-find doctor` names the sessions, so the failure
  is loud.

## Acceptance tests

Run against the live index, from any directory:

1. `claude-find query -- gitignore with a slash` lists the
   slither-io-simulator checkpoint session first.
2. `claude-find query -- kindle power drain` lists "Kindle battery
   efficiency" first.
3. `claude-find query --here ~/Projects/btc-math-addresses -- chess`
   lists only sessions under that directory, and Enter in the UI opens
   a tmux window whose cwd is that directory.
4. `claude-find query -- hyprland impermanence` includes a row marked
   `†` dated 2026-04, a session whose transcript no longer exists.
5. After a release changes the record shape, `claude-find doctor`
   reports "indexed but no text extracted" for the new sessions and the
   UI header says so.
6. `claude-find query -- oomd SIGKILL` lists sessions where only the
   assistant used those words.
7. `claude-find doctor` with a transcript deliberately touched reports
   one stale session; `claude-find index` clears it.
