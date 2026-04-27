"""MPV media control: /mpv <action>."""

import logging

from telegram import Update
from telegram.ext import ContextTypes

from bot.helpers import formatter, mpv_ipc

logger = logging.getLogger(__name__)


# -- Command handlers --


async def cmd_mpv(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Control MPV via IPC: /mpv <action>.

    Actions: pause, stop, playlist-next, playlist-prev, seek <seconds>,
             volume <0-100>, loadfile <url>, property <name>
    """
    if not context.args:
        await update.message.reply_text(
            "Usage: /mpv <action>\n"
            "Actions: pause, stop, playlist-next, playlist-prev, "
            "seek <seconds>, volume <0-100>, loadfile <url>, property <name>"
        )
        return

    action = context.args[0].lower()
    arg = " ".join(context.args[1:]) if len(context.args) > 1 else None

    try:
        if action == "pause":
            await mpv_ipc.mpv_command("cycle", ["pause"])
            is_paused = await mpv_ipc.mpv_get_property("pause")
            status = "Paused" if is_paused == "true" or is_paused is True else "Playing"
            await update.message.reply_text(status)

        elif action == "stop":
            await mpv_ipc.mpv_command("stop")
            await update.message.reply_text("Stopped.")

        elif action == "playlist-next":
            await mpv_ipc.mpv_command("playlist-next")
            await update.message.reply_text("Next track.")

        elif action == "playlist-prev":
            await mpv_ipc.mpv_command("playlist-prev")
            await update.message.reply_text("Previous track.")

        elif action == "seek":
            if not arg:
                await update.message.reply_text(
                    "Usage: /mpv seek <seconds>"
                )
                return
            await mpv_ipc.mpv_command("seek", [arg])
            await update.message.reply_text(f"Seeked {arg}s.")

        elif action == "volume":
            if not arg:
                current = await mpv_ipc.mpv_get_property("volume")
                await update.message.reply_text(f"Volume: {current}")
                return
            await mpv_ipc.mpv_command("set_property", ["volume", arg])
            await update.message.reply_text(f"Volume set to {arg}.")

        elif action == "loadfile":
            if not arg:
                await update.message.reply_text(
                    "Usage: /mpv loadfile <url or path>"
                )
                return
            await mpv_ipc.mpv_command("loadfile", [arg])
            await update.message.reply_text(f"Loaded: {arg}")

        elif action == "property":
            if not arg:
                await update.message.reply_text(
                    "Usage: /mpv property <name>"
                )
                return
            value = await mpv_ipc.mpv_get_property(arg)
            if value is not None:
                await update.message.reply_text(
                    f"{arg} = {value}"
                )
            else:
                await update.message.reply_text(
                    f"Property '{arg}' not found."
                )

        else:
            # Try as a raw command for extensibility
            result = await mpv_ipc.mpv_command(
                action, context.args[1:] if len(context.args) > 1 else []
            )
            if result is not None:
                for chunk in formatter.split_messages(str(result)):
                    await update.message.reply_text(formatter.wrap_code(chunk))
            else:
                await update.message.reply_text(
                    f"Unknown action: {action}"
                )

    except ConnectionError as exc:
        await update.message.reply_text(str(exc))
    except Exception as exc:
        logger.exception("MPV command failed")
        await update.message.reply_text(f"MPV command failed: {exc}")
