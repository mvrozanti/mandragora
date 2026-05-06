"""Cross-process GPU lease coordination via flock.

Two clients on the same GPU (im-gen Flux, llm-via-telegram Ollama) cannot
both run kernels at once without thrashing VRAM. This module provides a
single shared mutex with non-blocking acquire: a running holder is never
interrupted; new arrivals fail fast with information about who is in
there so the caller can decide what to do.

Semantics
---------
- One holder at a time. Mutual exclusion via fcntl LOCK_EX | LOCK_NB on
  a file in /dev/shm (RAM-backed; auto-clears on reboot).
- Sidecar JSON file records the holder's PID, name, start time, and
  expected_seconds.
- If the lock is held when you call `acquire`, it raises `GpuBusy`
  carrying the holder dict. Running work is not signalled; cooperation
  is via "respect the holder, come back later", not preemption.

Usage (sync)
------------
    from gpu_lock import gpu_lock, GpuBusy

    try:
        with gpu_lock.acquire("im-gen", expected_seconds=60):
            run_flux_generation()
    except GpuBusy as busy:
        print(f"GPU busy with {busy.holder['name']}")

Usage (async)
-------------
    try:
        async with gpu_lock.acquire_async("im-gen", expected_seconds=60):
            await loop.run_in_executor(None, run_flux_generation)
    except GpuBusy as busy:
        await reply(f"GPU busy with {busy.holder['name']}")
"""
from __future__ import annotations

import contextlib
import errno
import fcntl
import json
import logging
import os
import time
from pathlib import Path
from typing import Iterator

log = logging.getLogger("gpu_lock")

LOCK_DIR = Path(os.environ.get("GPU_LOCK_DIR", "/dev/shm/gpu-lock"))
LOCK_FILE = LOCK_DIR / "gpu.lock"
HOLDER_FILE = LOCK_DIR / "gpu.lock.holder"


class GpuBusy(Exception):
    """Raised when the GPU lock is held by another process.

    The `holder` attribute contains the current holder's metadata
    (pid, name, since, expected_seconds) or None if the holder file
    could not be read.
    """

    def __init__(self, holder: dict | None) -> None:
        self.holder = holder
        if holder:
            remaining = self.expected_remaining()
            tail = f", ~{remaining:.0f}s remaining" if remaining is not None else ""
            super().__init__(
                f"GPU held by {holder.get('name', '?')} (pid={holder.get('pid', '?')}){tail}"
            )
        else:
            super().__init__("GPU is busy")

    def expected_remaining(self) -> float | None:
        if not self.holder:
            return None
        since = self.holder.get("since")
        expected = self.holder.get("expected_seconds")
        if since is None or expected is None:
            return None
        return max(0.0, since + expected - time.time())


class _GpuLock:
    def __init__(self) -> None:
        self._fd: int | None = None
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

    def current_holder(self) -> dict | None:
        return self._read_holder()

    @contextlib.contextmanager
    def acquire(
        self,
        name: str,
        expected_seconds: float | None = None,
    ) -> Iterator[None]:
        """Try to acquire the GPU lock without blocking. Raises GpuBusy if held."""
        self._ensure_dir()
        fd = os.open(str(LOCK_FILE), os.O_CREAT | os.O_RDWR, 0o666)

        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            holder = self._read_holder()
            os.close(fd)
            raise GpuBusy(holder) from None
        except BaseException:
            os.close(fd)
            raise

        self._fd = fd
        self._held_by_us = True
        self._name = name
        self._since = time.time()
        self._write_holder(name, expected_seconds)

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

    @contextlib.asynccontextmanager
    async def acquire_async(
        self,
        name: str,
        expected_seconds: float | None = None,
    ):
        """Async wrapper around the non-blocking acquire."""
        cm = self.acquire(name, expected_seconds=expected_seconds)
        cm.__enter__()
        try:
            yield
        finally:
            cm.__exit__(None, None, None)


gpu_lock = _GpuLock()


def cli_status() -> int:
    """Print current holder (for ad-hoc inspection)."""
    holder = gpu_lock.current_holder()
    if holder:
        held_for = time.time() - holder.get("since", time.time())
        expected = holder.get("expected_seconds")
        eta = ""
        if expected is not None:
            remaining = max(0.0, holder.get("since", time.time()) + expected - time.time())
            eta = f" expected_remaining={remaining:.1f}s"
        print(
            f"HOLDER: pid={holder['pid']} name={holder['name']} held_for={held_for:.1f}s{eta}"
        )
    else:
        print("HOLDER: (none)")
    return 0


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "status":
        sys.exit(cli_status())
    print(f"usage: {sys.argv[0]} status", file=sys.stderr)
    sys.exit(2)
