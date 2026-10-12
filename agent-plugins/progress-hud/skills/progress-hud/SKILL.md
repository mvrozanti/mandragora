---
name: progress-hud
description: Use before running any Bash command that may take more than about ten seconds — builds, rebuilds, downloads, syncs, test suites, batch loops — and when writing a script or loop that will. The statusline draws one progress bar per running command from the tail of that command's own output (its newest `NN%`, `n/m` or `n of m`), so the command has to be run in a way that keeps those lines flowing. Loads the rules for picking flags, shaping loops, and staying inside the three-bar budget.
---

# progress-hud

The statusline shows one row per Bash command that is still running, in the
foreground or the background: a bar, the elapsed time and the command's last
output line. The bar is **parsed** from the output when the newest line
carries `NN%`, `n/m` or `n of m`; otherwise it is **estimated** from earlier
runs of the same command; otherwise it bounces. Nothing is sent to you; the
HUD reads the command's output file directly. Your only job is to not hide
the progress.

## Keep the progress stream flowing

For anything that may run longer than about ten seconds:

- Let output reach stdout or stderr unfiltered. `| tail`, `| head`,
  `| grep` without `--line-buffered`, `$(…)`, `> /dev/null` and
  `--quiet` all leave the bar blind. Both streams are captured, so
  progress written to stderr is fine.
- Ask tools for machine-readable progress: `rsync --info=progress2`,
  `curl -#`, `wget --progress=dot:mega`, `pip --progress-bar on`,
  `docker compose … --progress plain`, `pytest -q` (its `[ 42%]`
  suffix), `cargo build` (`Compiling …` plus `[n/m]`), `git clone
  --progress`.
- Carriage-return redraws are fine: each `\r` segment counts as a line
  and the newest one wins.
- In your own loops print the step on its own line, `printf '%d/%d
  %s\n' "$i" "$n" "$item"`, or a percentage. One line per step is
  enough; more is noise in the transcript and no gain on the bar.
- Repeat long commands with the same text. The ETA comes from the median
  of earlier runs of the same normalised command (`cd …`, env
  assignments, `rtk`, `sudo`, `timeout` and `time` are stripped), so a
  random temp path or a changed flag starts a fresh history.
- Background or foreground makes no difference to the bar. Use
  `run_in_background` when the command will outlive your next step, so
  you keep working while it runs.

## Stay quiet

- The HUD shows at most three bars (`--max-rows` in the statusLine
  command); extra commands collapse to `+N more running`. Do not fan out
  background commands to get more bars, and do not read a task's output
  file just to report a percentage: the HUD already shows it.
- Do not narrate progress in chat. Say what the command does when you
  start it and what came out when it ends.
- A bar that reads `quiet 45s` means the command has written nothing for
  that long. Decide whether it is stuck before it finishes, not after.
