"""Async subprocess wrappers for shell command execution."""

import asyncio
import logging
import os
from collections.abc import Sequence

logger = logging.getLogger(__name__)

# Truncate output beyond this many characters
MAX_OUTPUT_CHARS = 4000


def _merge_env(env: dict[str, str] | None) -> dict[str, str] | None:
    """Merge custom env into the current process environment."""
    if env is None:
        return None
    return {**os.environ, **env}


async def run_shell(
    cmd: str | Sequence[str],
    timeout: int = 120,
    env: dict[str, str] | None = None,
    stdin_input: str | bytes | None = None,
    cwd: str | None = None,
) -> tuple[int, str, str]:
    """Run a shell command asynchronously.

    Args:
        cmd: Command string (shell=True) or argument list.
        timeout: Max seconds to wait before killing the process.
        env: Optional environment dict merged on top of os.environ.
        stdin_input: Optional data to pipe to stdin.
        cwd: Optional working directory. Defaults to current directory.

    Returns:
        (returncode, stdout, stderr)
    """
    merged = _merge_env(env)
    stdin_data = stdin_input.encode() if isinstance(stdin_input, str) else stdin_input
    if isinstance(cmd, str):
        proc = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            stdin=asyncio.subprocess.PIPE if stdin_input is not None else None,
            env=merged,
            cwd=cwd,
        )
    else:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            stdin=asyncio.subprocess.PIPE if stdin_input is not None else None,
            env=merged,
            cwd=cwd,
        )

    try:
        stdout_bytes, stderr_bytes = await asyncio.wait_for(
            proc.communicate(stdin_data), timeout=timeout
        )
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        logger.warning("Command timed out after %ds: %s", timeout, cmd)
        return -1, "", f"Command timed out after {timeout}s"

    stdout = stdout_bytes.decode("utf-8", errors="replace")
    stderr = stderr_bytes.decode("utf-8", errors="replace")

    logger.debug(
        "Command %s exited with %d",
        cmd if isinstance(cmd, str) else cmd[0],
        proc.returncode,
    )

    return proc.returncode or 0, stdout, stderr
