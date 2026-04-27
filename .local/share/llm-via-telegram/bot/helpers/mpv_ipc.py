"""MPV IPC communication via Unix socket."""

import asyncio
import json
import logging

import config

logger = logging.getLogger(__name__)

# Command queue to serialize writes — prevents concurrent socket access
_command_lock = asyncio.Lock()


async def mpv_command(command: str, args: list[str] | None = None) -> dict | str | None:
    """Send a JSON-IPC command to MPV via its Unix socket.

    Args:
        command: MPV command name (e.g., "playlist-next", "pause").
        args: Optional list of arguments.

    Returns:
        Parsed JSON response, plain-text response, or None.

    Raises:
        ConnectionError: If MPV socket is not available or connection fails.
    """
    payload: dict = {"command": [command] + (args or [])}
    data = json.dumps(payload) + "\n"

    async with _command_lock:
        try:
            reader, writer = await asyncio.open_unix_connection(config.MPV_SOCKET)
        except (FileNotFoundError, ConnectionRefusedError, OSError) as exc:
            raise ConnectionError(
                f"Cannot connect to MPV at {config.MPV_SOCKET}. "
                f"Is MPV running with --input-ipc-server={config.MPV_SOCKET}?"
            ) from exc

        try:
            writer.write(data.encode())
            await writer.drain()

            response_line = await asyncio.wait_for(reader.readline(), timeout=5.0)
            if not response_line:
                return None

            response = json.loads(response_line.decode("utf-8", errors="replace"))
            logger.debug("MPV response: %s", response)
            return response.get("data")
        except asyncio.TimeoutError:
            logger.warning("MPV command timed out: %s", command)
            return None
        except (json.JSONDecodeError, OSError) as exc:
            logger.warning("MPV response error: %s", exc)
            return None
        finally:
            writer.close()
            await writer.wait_closed()


async def mpv_get_property(prop: str) -> str | None:
    """Get an MPV property value."""
    result = await mpv_command("get_property", [prop])
    return str(result) if result is not None else None
