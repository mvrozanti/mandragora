"""CLI wrapper around gpu_lock for any-language opt-in callers.

Subcommands
-----------
    gpu-lock run --name <name> --expect <s> [--on-yield {sigusr1,sigterm,kill}]
                 [--timeout <s>] -- <cmd> [args...]
        Acquire the lock, run cmd, release on exit. Forwards a yield request
        from another waiter to the child process.

    gpu-lock status
        Print current holder and waiters.

    gpu-lock yield [pid] [--reason <text>]
        Send SIGUSR1 to the current lock holder (or to the given pid).
"""
from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time

from gpu_lock import gpu_lock, cli_status


SIGNAL_BY_NAME = {
    "sigusr1": signal.SIGUSR1,
    "sigterm": signal.SIGTERM,
    "kill": signal.SIGKILL,
}


def _run(args: argparse.Namespace) -> int:
    if not args.cmd:
        print("error: missing command after --", file=sys.stderr)
        return 2

    yield_signal = SIGNAL_BY_NAME[args.on_yield]
    child: subprocess.Popen | None = None

    def forward_yield(reason: str) -> None:
        if child and child.poll() is None:
            print(f"gpu-lock: yield requested ({reason}), sending {args.on_yield} to pid={child.pid}",
                  file=sys.stderr)
            try:
                child.send_signal(yield_signal)
            except ProcessLookupError:
                pass

    gpu_lock.on_yield(forward_yield)

    timeout = args.timeout if args.timeout > 0 else None
    with gpu_lock.acquire(args.name, expected_seconds=args.expect, timeout=timeout):
        child = subprocess.Popen(args.cmd)

        def forward_term(signum, _frame):
            if child and child.poll() is None:
                child.send_signal(signum)

        signal.signal(signal.SIGTERM, forward_term)
        signal.signal(signal.SIGINT, forward_term)

        return child.wait()


def _yield(args: argparse.Namespace) -> int:
    pid = args.pid
    if pid is None:
        holder = gpu_lock.current_holder()
        if not holder:
            print("gpu-lock: no current holder", file=sys.stderr)
            return 1
        pid = holder["pid"]
    ok = gpu_lock.request_yield(pid, args.reason)
    return 0 if ok else 1


def main() -> int:
    p = argparse.ArgumentParser(prog="gpu-lock")
    sub = p.add_subparsers(dest="subcommand", required=True)

    run = sub.add_parser("run", help="Acquire lock then run a command")
    run.add_argument("--name", required=True)
    run.add_argument("--expect", type=float, default=60.0,
                     help="expected seconds the GPU will be held (advisory)")
    run.add_argument("--on-yield", choices=list(SIGNAL_BY_NAME), default="sigusr1")
    run.add_argument("--timeout", type=float, default=0.0,
                     help="abort acquisition after N seconds (0 = wait forever)")
    run.add_argument("cmd", nargs=argparse.REMAINDER)

    sub.add_parser("status", help="Show current holder and waiters")

    y = sub.add_parser("yield", help="Send a yield request to the current holder")
    y.add_argument("pid", nargs="?", type=int, default=None)
    y.add_argument("--reason", default="manual yield request")

    args = p.parse_args()
    if args.subcommand == "run":
        if args.cmd and args.cmd[0] == "--":
            args.cmd = args.cmd[1:]
        return _run(args)
    if args.subcommand == "status":
        return cli_status()
    if args.subcommand == "yield":
        return _yield(args)
    return 2


if __name__ == "__main__":
    sys.exit(main())
