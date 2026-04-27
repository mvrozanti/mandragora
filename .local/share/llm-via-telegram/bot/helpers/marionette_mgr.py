"""Firefox/Marionette connection manager with automatic heal logic.

Tracks session state: alive / dead.
On any operation when dead, auto-heals (kill all firefox, relaunch with --marionette).
"""

import asyncio
import logging
import os

import config

logger = logging.getLogger(__name__)

# Module-level state
_session = None  # Marionette session object
_is_alive: bool = False


def is_alive() -> bool:
    """Return whether the Marionette session is considered alive."""
    return _is_alive


async def _get_browser() -> object | None:
    """Get or restore a Marionette browser session.

    Returns the session object, or None if healing failed.
    """
    global _session, _is_alive

    if _is_alive and _session is not None:
        # Quick liveness check
        try:
            _ = _session.session_id
            return _session
        except Exception:
            _is_alive = False
            _session = None

    # Healed
    logger.info("Marionette session is dead or missing — healing Firefox")
    success = await _heal_firefox()
    if not success:
        return None

    await asyncio.sleep(2)
    try:
        from marionette_driver.marionette import Marionette
        _session = Marionette("localhost", port=2828)
        _session.start_session()
        _is_alive = True
        logger.info("Firefox healed and reconnected")
        return _session
    except Exception as exc:
        logger.error("Heal failed — cannot reconnect: %s", exc)
        _is_alive = False
        _session = None
        return None


async def _heal_firefox() -> bool:
    """Kill all Firefox processes and relaunch with --marionette."""
    # Kill existing instances
    try:
        proc = await asyncio.create_subprocess_exec(
            "pkill", "-9", "-f", "firefox",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await proc.wait()
        logger.info("Killed all Firefox processes")
    except (FileNotFoundError, OSError) as exc:
        logger.warning("Could not kill Firefox: %s", exc)

    # Relaunch
    env = {**os.environ, **config.x11_env()}
    try:
        proc = await asyncio.create_subprocess_exec(
            "firefox", "--marionette", "--no-remote", env=env,
        )
        logger.info("Firefox relaunched with --marionette (pid=%d)", proc.pid)
        return True
    except FileNotFoundError:
        logger.error("Firefox binary not found. Is Firefox installed?")
        return False
    except OSError as exc:
        logger.error("Failed to launch Firefox: %s", exc)
        return False


async def ensure_browser() -> str | None:
    """Ensure a browser session is alive. Returns error string or None."""
    browser = await _get_browser()
    if browser is None:
        return "Could not connect to Firefox, even after healing."
    return None


async def kill_session() -> None:
    """Kill the Marionette session and all Firefox processes."""
    global _session, _is_alive
    _session = None
    _is_alive = False
    try:
        proc = await asyncio.create_subprocess_exec(
            "pkill", "-9", "-f", "firefox",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await proc.wait()
        logger.info("Firefox session killed by user")
    except (FileNotFoundError, OSError) as exc:
        logger.warning("Could not kill Firefox: %s", exc)


async def open_url(url: str) -> str | None:
    """Navigate to a URL. Returns error string or None."""
    err = await ensure_browser()
    if err:
        return err
    try:
        _session.navigate(url)
        return None
    except Exception as exc:
        _is_alive = False
        return f"Error opening URL: {exc}"


async def eval_js(js_code: str) -> str | None:
    """Execute JavaScript in the current tab. Returns result or error string."""
    err = await ensure_browser()
    if err:
        return err
    try:
        result = _session.execute_script(f"return {js_code}", sandbox=None)
        return str(result)
    except Exception as exc:
        _is_alive = False
        return f"Error executing JS: {exc}"


async def get_url() -> str | None:
    """Get the current page URL. Returns result or error string."""
    err = await ensure_browser()
    if err:
        return err
    try:
        return _session.get_url()
    except Exception as exc:
        _is_alive = False
        return f"Error getting URL: {exc}"


async def get_title() -> str | None:
    """Get the current page title. Returns result or error string."""
    err = await ensure_browser()
    if err:
        return err
    try:
        return _session.title
    except Exception as exc:
        _is_alive = False
        return f"Error getting title: {exc}"
