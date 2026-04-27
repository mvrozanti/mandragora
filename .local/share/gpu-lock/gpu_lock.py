"""Cross-process GPU lease coordination via flock + SIGUSR1.

Two clients on the same GPU (im-gen Flux, llm-via-telegram Ollama) cannot
both run kernels at once without thrashing VRAM. This module provides a
single shared mutex with cooperative preemption.

Semantics
---------
- One holder at a time. Mutual exclusion via fcntl LOCK_EX on a file in
  /dev/shm (RAM-backed; auto-clears on reboot).
- Sidecar JSON file records the holder's PID, name, and start time so
  waiters can ask "who's in there?" before deciding what to do.
- Waiters call `request_yield(reason)` to politely ask the holder to wrap
  up. Implemented by sending SIGUSR1 to the holder PID. The holder's
  registered yield handler sets a flag the application can poll
  (`yield_requested()`), or runs an optional callback.
- Whether the holder actually yields is its own contract; this module
  only delivers the request.

Usage (sync)
------------
    from gpu_lock import gpu_lock

    with gpu_lock.acquire("im-gen", expected_seconds=60):
        run_flux_generation()

Usage (async, non-blocking acquire on the event loop)
-----------------------------------------------------
    async with gpu_lock.acquire_async("im-gen", expected_seconds=60):
        await loop.run_in_executor(None, run_flux_generation)

Cooperative yield in the holder
-------------------------------
    with gpu_lock.acquire("im-gen", expected_seconds=60):
        for step in range(steps):
            if gpu_lock.yield_requested():
                raise GpuYieldRequested("preempted by waiter")
            run_one_step()
"""
from __future__ import annotations

import contextlib
import errno
import fcntl
import json
import logging
import os
import signal
import threading
import time
from pathlib import Path
from typing import Callable, Iterator

log = logging.getLogger("gpu_lock")

LOCK_DIR = Path(os.environ.get("GPU_LOCK_DIR", "/dev/shm/gpu-lock"))
LOCK_FILE = LOCK_DIR / "gpu.lock"
HOLDER_FILE = LOCK_DIR / "gpu.lock.holder"
WAITERS_FILE = LOCK_DIR / "gpu.lock.waiters"


class GpuYieldRequested(Exception):
    """Raised by the holder when it observes a yield request and chooses to abort."""


class _GpuLock:
    def __init__(self) -> None:
        self._fd: int | None = None
        self._yield_flag = threading.Event()
        self._yield_reason: str | None = None
        self._yield_callbacks: list[Callable[[str], None]] = []
        self._handler_installed = False
        self._held_by_us = False
        self._name: str | None = None
        self._since: float | None = None

    def _ensure_dir(self) -> None:
        LOCK_DIR.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(LOCK_DIR, 0o1777)
        except PermissionError:
            pass

    def _read_holder(self) -> dict | None:
        try:
            return json.loads(HOLDER_FILE.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    def _write_holder(self, name: str, expected_seconds: float | None) -> None:
        payload = {
            "pid": os.getpid(),
            "name": name,
            "since": time.time(),
            "expected_seconds": expected_seconds,
        }
        HOLDER_FILE.write_text(json.dumps(payload))

    def _clear_holder(self) -> None:
        try:
            HOLDER_FILE.unlink()
        except FileNotFoundError:
            pass

    def _signal_handler(self, signum, frame):
        if not self._held_by_us:
            return
        reason = "(no reason provided)"
        try:
            waiters = json.loads(WAITERS_FILE.read_text())
            if waiters:
                reason = waiters[-1].get("reason", reason)
        except (FileNotFoundError, json.JSONDecodeError, IndexError):
            pass
        self._yield_reason = reason
        self._yield_flag.set()
        log.info("yield requested: %s", reason)
        for cb in list(self._yield_callbacks):
            try:
                cb(reason)
            except Exception:
                log.exception("yield callback raised")

    def install_signal_handler(self) -> None:
        """Install the SIGUSR1 handler. Must be called from the main thread.

        Idempotent. Called automatically by `acquire` and `acquire_async` (the
        latter from the asyncio thread before delegating to an executor)."""
        if self._handler_installed:
            return
        try:
            signal.signal(signal.SIGUSR1, self._signal_handler)
            self._handler_installed = True
        except ValueError:
            log.warning("install_signal_handler called off the main thread; "
                        "yield requests will be ignored")

    def _append_waiter(self, name: str, reason: str) -> None:
        WAITERS_FILE.parent.mkdir(parents=True, exist_ok=True)
        try:
            current = json.loads(WAITERS_FILE.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            current = []
        current.append({"pid": os.getpid(), "name": name, "reason": reason, "since": time.time()})
        WAITERS_FILE.write_text(json.dumps(current))

    def _remove_waiter(self) -> None:
        try:
            current = json.loads(WAITERS_FILE.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return
        current = [w for w in current if w.get("pid") != os.getpid()]
        if current:
            WAITERS_FILE.write_text(json.dumps(current))
        else:
            try:
                WAITERS_FILE.unlink()
            except FileNotFoundError:
                pass

    def request_yield(self, holder_pid: int, reason: str) -> bool:
        """Send a polite yield request to the current holder. Returns True if signal was delivered."""
        try:
            os.kill(holder_pid, signal.SIGUSR1)
            log.info("sent SIGUSR1 to PID %d (%s)", holder_pid, reason)
            return True
        except ProcessLookupError:
            log.warning("holder PID %d gone before yield could be requested", holder_pid)
            return False
        except PermissionError:
            log.warning("no permission to signal PID %d", holder_pid)
            return False

    def yield_requested(self) -> bool:
        return self._yield_flag.is_set()

    def yield_reason(self) -> str | None:
        return self._yield_reason

    def on_yield(self, callback: Callable[[str], None]) -> None:
        """Register a callback fired when SIGUSR1 arrives while we hold the lock."""
        self._yield_callbacks.append(callback)

    def current_holder(self) -> dict | None:
        return self._read_holder()

    @contextlib.contextmanager
    def acquire(
        self,
        name: str,
        expected_seconds: float | None = None,
        timeout: float | None = None,
        polite: bool = True,
    ) -> Iterator[None]:
        """Block until we hold the GPU lock. Politely asks the current holder to yield."""
        self._ensure_dir()
        fd = os.open(str(LOCK_FILE), os.O_CREAT | os.O_RDWR, 0o666)

        self._append_waiter(name, reason=f"{name} wants the GPU")

        if polite:
            holder = self._read_holder()
            if holder and holder.get("pid") and holder["pid"] != os.getpid():
                self.request_yield(holder["pid"], reason=f"{name} wants the GPU")

        try:
            if timeout is None:
                fcntl.flock(fd, fcntl.LOCK_EX)
            else:
                deadline = time.time() + timeout
                while True:
                    try:
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError:
                        if time.time() >= deadline:
                            raise TimeoutError(
                                f"could not acquire GPU lock within {timeout}s"
                            )
                        time.sleep(0.25)
        except BaseException:
            os.close(fd)
            self._remove_waiter()
            raise

        self._fd = fd
        self._held_by_us = True
        self._name = name
        self._since = time.time()
        self._yield_flag.clear()
        self._yield_reason = None
        self._remove_waiter()
        self._write_holder(name, expected_seconds)
        self.install_signal_handler()

        log.info("acquired GPU lock as %s (pid=%d)", name, os.getpid())
        try:
            yield
        finally:
            self.release()

    def release(self) -> None:
        if not self._held_by_us:
            return
        self._clear_holder()
        try:
            fcntl.flock(self._fd, fcntl.LOCK_UN)
        except OSError as e:
            if e.errno != errno.EBADF:
                raise
        try:
            os.close(self._fd)
        except OSError:
            pass
        log.info(
            "released GPU lock (held %.1fs as %s)",
            time.time() - (self._since or time.time()),
            self._name,
        )
        self._fd = None
        self._held_by_us = False
        self._name = None
        self._since = None
        self._yield_callbacks.clear()
        self._yield_flag.clear()
        self._yield_reason = None

    @contextlib.asynccontextmanager
    async def acquire_async(
        self,
        name: str,
        expected_seconds: float | None = None,
        timeout: float | None = None,
        polite: bool = True,
    ):
        """Async wrapper — runs the blocking acquire in a worker thread so the event loop stays responsive."""
        import asyncio
        self.install_signal_handler()  # must run in main thread (asyncio thread)
        loop = asyncio.get_running_loop()
        cm = self.acquire(name, expected_seconds=expected_seconds, timeout=timeout, polite=polite)
        await loop.run_in_executor(None, cm.__enter__)
        try:
            yield
        finally:
            await loop.run_in_executor(None, lambda: cm.__exit__(None, None, None))


gpu_lock = _GpuLock()


def cli_status() -> int:
    """Print current holder + waiters (for ad-hoc inspection)."""
    holder = gpu_lock.current_holder()
    if holder:
        held_for = time.time() - holder.get("since", time.time())
        print(f"HOLDER: pid={holder['pid']} name={holder['name']} held_for={held_for:.1f}s")
    else:
        print("HOLDER: (none)")
    try:
        waiters = json.loads(WAITERS_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        waiters = []
    if waiters:
        print(f"WAITERS: {len(waiters)}")
        for w in waiters:
            wait_time = time.time() - w.get("since", time.time())
            print(f"  pid={w['pid']} name={w['name']} waiting={wait_time:.1f}s")
    else:
        print("WAITERS: (none)")
    return 0


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "status":
        sys.exit(cli_status())
    print(f"usage: {sys.argv[0]} status", file=sys.stderr)
    sys.exit(2)
