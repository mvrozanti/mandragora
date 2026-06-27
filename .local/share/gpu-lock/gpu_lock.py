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
import inspect
import json
import logging
import os
import time
from pathlib import Path
from typing import Callable, Iterator

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


class _Lease:
    """Handle for one held GPU lease. Owns its own fd; release is idempotent."""

    def __init__(
        self,
        fd: int,
        name: str,
        since: float,
        expected_seconds: float | None,
        clear_holder: Callable[[], None],
    ) -> None:
        self._fd = fd
        self.name = name
        self.since = since
        self.expected_seconds = expected_seconds
        self._clear_holder = clear_holder
        self._released = False

    @property
    def held(self) -> bool:
        return not self._released

    def release(self) -> None:
        if self._released:
            return
        self._released = True
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
        log.info("released GPU lock (held %.1fs as %s)", time.time() - self.since, self.name)


class _GpuLock:
    def _ensure_dir(self) -> None:
        LOCK_DIR.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(LOCK_DIR, 0o1777)
        except PermissionError:
            pass

    def _read_holder(self) -> dict | None:
        try:
            holder = json.loads(HOLDER_FILE.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None
        pid = holder.get("pid")
        if isinstance(pid, int):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                self._clear_holder()
                return None
            except PermissionError:
                pass
        return holder

    def _write_holder(self, name: str, expected_seconds: float | None, since: float) -> None:
        payload = {
            "pid": os.getpid(),
            "name": name,
            "since": since,
            "expected_seconds": expected_seconds,
        }
        tmp = HOLDER_FILE.with_name(f"{HOLDER_FILE.name}.{os.getpid()}.tmp")
        tmp.write_text(json.dumps(payload))
        os.replace(tmp, HOLDER_FILE)

    def _clear_holder(self) -> None:
        try:
            HOLDER_FILE.unlink()
        except FileNotFoundError:
            pass

    def current_holder(self) -> dict | None:
        return self._read_holder()

    def _open_locked(self, name: str, expected_seconds: float | None) -> _Lease:
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
        since = time.time()
        try:
            self._write_holder(name, expected_seconds, since)
        except BaseException:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            except OSError:
                pass
            os.close(fd)
            raise
        log.info("acquired GPU lock as %s (pid=%d)", name, os.getpid())
        return _Lease(fd, name, since, expected_seconds, self._clear_holder)

    @contextlib.contextmanager
    def acquire(
        self,
        name: str,
        expected_seconds: float | None = None,
        on_release: Callable[[], object] | None = None,
    ) -> Iterator[_Lease]:
        """Acquire the GPU lock without blocking. Raises GpuBusy if held.

        Yields a `_Lease`. The lock is intentionally non-reentrant: a nested
        acquire in the same process raises GpuBusy rather than silently
        re-entering, so two concurrent async tasks each fail fast instead of
        sharing one lease. `on_release`, if given, runs just before release.
        """
        lease = self._open_locked(name, expected_seconds)
        try:
            yield lease
        finally:
            if on_release is not None:
                try:
                    on_release()
                except Exception:
                    log.exception("on_release hook failed for %s", name)
            lease.release()

    @contextlib.asynccontextmanager
    async def acquire_async(
        self,
        name: str,
        expected_seconds: float | None = None,
        on_release: Callable[[], object] | None = None,
    ):
        """Async wrapper around the non-blocking acquire.

        `on_release` may be sync or return an awaitable; it runs (awaited if
        needed) just before the lock is released.
        """
        lease = self._open_locked(name, expected_seconds)
        try:
            yield lease
        finally:
            if on_release is not None:
                try:
                    result = on_release()
                    if inspect.isawaitable(result):
                        await result
                except Exception:
                    log.exception("on_release hook failed for %s", name)
            lease.release()


gpu_lock = _GpuLock()


def _holder_with_derived() -> dict | None:
    holder = gpu_lock.current_holder()
    if not holder:
        return None
    since = holder.get("since")
    expected = holder.get("expected_seconds")
    now = time.time()
    if isinstance(since, (int, float)):
        holder["held_for"] = max(0.0, now - since)
        if isinstance(expected, (int, float)):
            holder["expected_remaining"] = max(0.0, since + expected - now)
    return holder


def cli_status(as_json: bool = False) -> int:
    """Print current holder (for ad-hoc inspection)."""
    holder = _holder_with_derived()
    if as_json:
        print(json.dumps({"holder": holder}))
        return 0
    if holder:
        eta = ""
        if "expected_remaining" in holder:
            eta = f" expected_remaining={holder['expected_remaining']:.1f}s"
        print(
            f"HOLDER: pid={holder['pid']} name={holder['name']} "
            f"held_for={holder.get('held_for', 0.0):.1f}s{eta}"
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
