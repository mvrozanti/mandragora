#!/usr/bin/env python3
import json
import re
import shlex
import sys

VALUE_SHORT = set("dgGPstuUFr")
VALUE_LONG = {"delimiter", "pgroup", "group", "parent", "session", "terminal", "euid", "uid", "pidfile", "runstates", "ns", "nslist", "signal", "env", "cgroup"}
SEGMENT_END = re.compile(r"[|;&\n`)]")
COMMAND_WORD = re.compile(
    r"(?:^|[;&|(`{\n!]|\$\(|\b(?:then|do|else|if|while|until|sudo|xargs|exec|timeout\s+\S+|watch(?:\s+-\S+)*))\s*"
    r"(?:[\w./-]*/)?(pgrep|pkill)(?![\w-])"
)
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_]\w*)\1[^\n]*\n.*?\n[ \t]*\2[ \t]*(?=\n|$)", re.S)


def split_segment(segment: str) -> list[str]:
    for attempt in (segment, segment.rstrip("'\" "), segment.replace("'", "").replace('"', "")):
        try:
            return shlex.split(attempt)
        except ValueError:
            continue
    return segment.split()


def full_patterns(command: str) -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    for match in COMMAND_WORD.finditer(command):
        rest = command[match.end():]
        cut = SEGMENT_END.search(rest)
        args = split_segment(rest[: cut.start()] if cut else rest)
        full = exact = False
        pattern = None
        i = 0
        while i < len(args):
            arg = args[i]
            if pattern is None and arg == "--":
                pattern = args[i + 1] if i + 1 < len(args) else None
                break
            if arg.startswith("--"):
                name = arg[2:].split("=", 1)[0]
                if name == "full":
                    full = True
                elif name == "exact":
                    exact = True
                elif name in VALUE_LONG and "=" not in arg:
                    i += 1
            elif arg.startswith("-") and len(arg) > 1:
                if match.group(1) == "pkill" and re.fullmatch(r"-(\d+|[A-Z]+[A-Z0-9]*)", arg):
                    i += 1
                    continue
                for k, ch in enumerate(arg[1:], start=1):
                    if ch == "f":
                        full = True
                    elif ch == "x":
                        exact = True
                    elif ch in VALUE_SHORT:
                        if k == len(arg) - 1:
                            i += 1
                        break
            elif pattern is None:
                pattern = arg
            i += 1
        if full and not exact and pattern:
            found.append((match.group(1), pattern))
    return found


def self_matches(command: str) -> list[tuple[str, str]]:
    hits = []
    for tool, pattern in full_patterns(HEREDOC.sub("", command)):
        try:
            if re.search(pattern, command):
                hits.append((tool, pattern))
        except re.error:
            continue
    return hits


def deny(reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}))


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    command = (payload.get("tool_input") or {}).get("command") or ""
    hits = self_matches(command)
    if not hits:
        return 0
    tool, pattern = hits[0]
    reason = (
        f"Blocked: `{tool} -f '{pattern}'` would match its own shell. Every Bash call runs as "
        f"`zsh -c '<the whole command>'`, and that text contains a match for '{pattern}', so "
        f"{'pgrep always reports a hit' if tool == 'pgrep' else 'pkill would kill this very shell'}. "
        "Make the pattern unable to match its own text: bracket one character (`[m]andragora-switch`) "
        "and keep the plain word out of the rest of the command, or match process names with "
        "`ps -eo comm`. Never wait for another mandragora-switch: call `mandragora-switch` bare, "
        "it queues behind its own flock and names the holder if it gives up."
    )
    deny(reason)
    return 0


if __name__ == "__main__":
    sys.exit(main())
