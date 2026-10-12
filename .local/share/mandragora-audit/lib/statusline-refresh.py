#!/usr/bin/env python3
import json
import os
import sys

SCRIPT = "progress-hud/scripts/statusline.py"


def problems(path):
    with open(path) as f:
        block = json.load(f).get("statusLine")
    if not isinstance(block, dict):
        return None
    command = str(block.get("command", ""))
    if SCRIPT not in command:
        return None
    found = []
    interval = block.get("refreshInterval")
    if isinstance(interval, bool) or not isinstance(interval, (int, float)) or interval < 1:
        found.append(f"{path}: statusLine.refreshInterval must be >= 1; nothing else re-runs the statusline during a tool call")
    for word in command.split():
        if word.endswith(SCRIPT) and word.startswith("/") and not os.path.exists(word):
            found.append(f"{path}: statusLine.command points at {word}, which does not exist")
    return found


def main():
    failures, checked = [], 0
    for path in sys.argv[1:]:
        try:
            found = problems(path)
        except (OSError, ValueError) as error:
            found = [f"{path}: {error}"]
        if found is None:
            continue
        checked += 1
        failures.extend(found)
    if failures:
        sys.exit("\n".join(failures))
    print(f"{checked} progress-hud statusLine declaration(s) keep their refreshInterval")


if __name__ == "__main__":
    main()
