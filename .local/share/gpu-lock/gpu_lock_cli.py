"""CLI wrapper around gpu_lock for any-language opt-in callers.

Subcommands
-----------
    gpu-lock run --name <name> --expect <s> [--wait <s>] -- <cmd> [args...]
        Try to acquire the lock. Without --wait, fail fast: if held,
        exit 75 (EX_TEMPFAIL) and print the holder JSON to stderr.
        With --wait <s>, poll (with backoff) up to <s> seconds for a
        free lock before giving up. Otherwise run cmd to completion
        and release on exit.

    gpu-lock status [--json]
        Print the current holder (or "(none)"). --json emits
        {"holder": {...}|null} with derived held_for/expected_remaining.
"""
from __future__ import annotations

import argparse
import json
import signal
import subprocess
import sys
import time

from gpu_lock import gpu_lock, cli_status, GpuBusy


EX_TEMPFAIL = 75


def _acquire(name: str, expect: float, wait: float):
    deadline = time.monotonic() + wait
    backoff = 0.5
    while True:
        try:
            cm = gpu_lock.acquire(name, expected_seconds=expect)
            cm.__enter__()
            return cm
        except GpuBusy:
            if wait <= 0 or time.monotonic() >= deadline:
                raise
            remaining = deadline - time.monotonic()
            time.sleep(min(backoff, max(0.0, remaining)))
            backoff = min(backoff * 1.5, 5.0)


def _run(args: argparse.Namespace) -> int:
    if not args.cmd:
        print("error: missing command after --", file=sys.stderr)
        return 2

    try:
        cm = _acquire(args.name, args.expect, args.wait)
    except GpuBusy as busy:
        payload = {"error": "gpu-busy", "holder": busy.holder}
        print(json.dumps(payload), file=sys.stderr)
        return EX_TEMPFAIL

    try:
        child = subprocess.Popen(args.cmd)

        def forward_term(signum, _frame):
            if child.poll() is None:
                child.send_signal(signum)

        signal.signal(signal.SIGTERM, forward_term)
        signal.signal(signal.SIGINT, forward_term)

        return child.wait()
    finally:
        cm.__exit__(None, None, None)


def main() -> int:
    p = argparse.ArgumentParser(prog="gpu-lock")
    sub = p.add_subparsers(dest="subcommand", required=True)

    run = sub.add_parser("run", help="Acquire lock then run a command")
    run.add_argument("--name", required=True)
    run.add_argument("--expect", type=float, default=60.0,
                     help="expected seconds the GPU will be held (advisory)")
    run.add_argument("--wait", type=float, default=0.0,
                     help="seconds to wait for a busy lock before giving up (0 = fail fast)")
    run.add_argument("cmd", nargs=argparse.REMAINDER)

    status = sub.add_parser("status", help="Show current holder")
    status.add_argument("--json", action="store_true", help="emit holder as JSON")

    args = p.parse_args()
    if args.subcommand == "run":
        if args.cmd and args.cmd[0] == "--":
            args.cmd = args.cmd[1:]
        return _run(args)
    if args.subcommand == "status":
        return cli_status(as_json=args.json)
    return 2


if __name__ == "__main__":
    sys.exit(main())
