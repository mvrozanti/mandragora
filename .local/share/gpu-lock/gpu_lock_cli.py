"""CLI wrapper around gpu_lock for any-language opt-in callers.

Subcommands
-----------
    gpu-lock run --name <name> --expect <s> -- <cmd> [args...]
        Try to acquire the lock without blocking. If held, exit 75
        (EX_TEMPFAIL) and print the holder JSON to stderr. Otherwise
        run cmd to completion and release on exit.

    gpu-lock status
        Print the current holder (or "(none)").
"""
from __future__ import annotations

import argparse
import json
import signal
import subprocess
import sys

from gpu_lock import gpu_lock, cli_status, GpuBusy


EX_TEMPFAIL = 75


def _run(args: argparse.Namespace) -> int:
    if not args.cmd:
        print("error: missing command after --", file=sys.stderr)
        return 2

    try:
        with gpu_lock.acquire(args.name, expected_seconds=args.expect):
            child = subprocess.Popen(args.cmd)

            def forward_term(signum, _frame):
                if child.poll() is None:
                    child.send_signal(signum)

            signal.signal(signal.SIGTERM, forward_term)
            signal.signal(signal.SIGINT, forward_term)

            return child.wait()
    except GpuBusy as busy:
        payload = {"error": "gpu-busy", "holder": busy.holder}
        print(json.dumps(payload), file=sys.stderr)
        return EX_TEMPFAIL


def main() -> int:
    p = argparse.ArgumentParser(prog="gpu-lock")
    sub = p.add_subparsers(dest="subcommand", required=True)

    run = sub.add_parser("run", help="Acquire lock then run a command")
    run.add_argument("--name", required=True)
    run.add_argument("--expect", type=float, default=60.0,
                     help="expected seconds the GPU will be held (advisory)")
    run.add_argument("cmd", nargs=argparse.REMAINDER)

    sub.add_parser("status", help="Show current holder")

    args = p.parse_args()
    if args.subcommand == "run":
        if args.cmd and args.cmd[0] == "--":
            args.cmd = args.cmd[1:]
        return _run(args)
    if args.subcommand == "status":
        return cli_status()
    return 2


if __name__ == "__main__":
    sys.exit(main())
