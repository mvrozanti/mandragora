"""Regression tests for the gpu_lock library + CLI.

Self-contained, no test framework: run `python3 test_gpu_lock.py`. Exits 0
when every check passes, non-zero on the first failure. Uses a throwaway
GPU_LOCK_DIR so it never touches the real /dev/shm lock.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import subprocess
import sys
import tempfile

logging.disable(logging.CRITICAL)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
LOCK_DIR = tempfile.mkdtemp(prefix="gpu-lock-test-")
os.environ["GPU_LOCK_DIR"] = LOCK_DIR

import gpu_lock as gl

HOLDER = os.path.join(LOCK_DIR, "gpu.lock.holder")


def _no_tmp_files() -> bool:
    return not any(n.endswith(".tmp") for n in os.listdir(LOCK_DIR))


def test_acquire_yields_lease_and_holder() -> None:
    with gl.gpu_lock.acquire("t1", expected_seconds=5) as lease:
        assert isinstance(lease, gl._Lease) and lease.held and lease.name == "t1"
        h = json.loads(open(HOLDER).read())
        assert h["name"] == "t1" and h["expected_seconds"] == 5
        assert _no_tmp_files(), "atomic write left a .tmp file"


def test_holder_cleared_on_release() -> None:
    with gl.gpu_lock.acquire("t2"):
        pass
    assert not os.path.exists(HOLDER)


def test_nested_is_non_reentrant() -> None:
    with gl.gpu_lock.acquire("outer"):
        try:
            with gl.gpu_lock.acquire("inner"):
                raise AssertionError("nested acquire should raise GpuBusy")
        except gl.GpuBusy as busy:
            assert busy.holder and busy.holder["name"] == "outer"


def test_double_release_idempotent() -> None:
    cm = gl.gpu_lock.acquire("d")
    lease = cm.__enter__()
    lease.release()
    lease.release()
    assert not lease.held
    cm.__exit__(None, None, None)


def test_sync_on_release_fires() -> None:
    calls = []
    with gl.gpu_lock.acquire("s", on_release=lambda: calls.append("x")):
        pass
    assert calls == ["x"]


def test_on_release_exception_swallowed() -> None:
    def boom():
        raise RuntimeError("hook boom")

    with gl.gpu_lock.acquire("e", on_release=boom):
        pass
    assert not os.path.exists(HOLDER)
    with gl.gpu_lock.acquire("after"):
        pass


def test_async_on_release_and_nested() -> None:
    async def run() -> None:
        flag = []

        async def hook():
            await asyncio.sleep(0.01)
            flag.append("a")

        async with gl.gpu_lock.acquire_async("as", on_release=hook):
            pass
        assert flag == ["a"]

        async with gl.gpu_lock.acquire_async("ao"):
            try:
                async with gl.gpu_lock.acquire_async("ai"):
                    raise AssertionError("async nested should raise")
            except gl.GpuBusy:
                pass

    asyncio.run(run())


def test_holder_write_failure_is_non_fatal() -> None:
    original = gl.gpu_lock._write_holder

    def explode(*_a, **_k):
        raise OSError("simulated holder-write failure")

    gl.gpu_lock._write_holder = explode
    try:
        acquired = False
        with gl.gpu_lock.acquire("nf"):
            acquired = True
            assert gl.gpu_lock.current_holder() is None
        assert acquired, "lock must still be granted when holder metadata fails"
        assert _no_tmp_files(), "failed holder write left a .tmp file"
    finally:
        gl.gpu_lock._write_holder = original
    with gl.gpu_lock.acquire("recover"):
        pass


def test_current_holder_and_derived() -> None:
    assert gl.gpu_lock.current_holder() is None
    with gl.gpu_lock.acquire("ch", expected_seconds=9):
        h = gl._holder_with_derived()
        assert h["name"] == "ch"
        assert "held_for" in h and "expected_remaining" in h
    assert gl.gpu_lock.current_holder() is None


def _cli(*argv, env_extra=None):
    env = {**os.environ, "PYTHONPATH": HERE, "GPU_LOCK_DIR": LOCK_DIR}
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        [sys.executable, os.path.join(HERE, "gpu_lock_cli.py"), *argv],
        capture_output=True, text=True, env=env,
    )


def test_cli_status_json_free() -> None:
    out = _cli("status", "--json")
    assert out.returncode == 0
    assert json.loads(out.stdout) == {"holder": None}


def test_cli_run_free_succeeds() -> None:
    out = _cli("run", "--name", "clitest", "--expect", "2", "--", "true")
    assert out.returncode == 0, out.stderr


def test_cli_run_wait_times_out_when_busy() -> None:
    with gl.gpu_lock.acquire("holder-test", expected_seconds=10):
        status = _cli("status", "--json")
        assert json.loads(status.stdout)["holder"]["name"] == "holder-test"

        busy = _cli("run", "--name", "waiter", "--wait", "1", "--", "true")
        assert busy.returncode == 75, f"expected 75, got {busy.returncode}"
        assert json.loads(busy.stderr)["error"] == "gpu-busy"

        ff = _cli("run", "--name", "ff", "--", "true")
        assert ff.returncode == 75


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"ok   {t.__name__}")
        except Exception as exc:
            failed += 1
            print(f"FAIL {t.__name__}: {exc!r}")
    print(f"\n{len(tests) - failed}/{len(tests)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        import shutil
        shutil.rmtree(LOCK_DIR, ignore_errors=True)
