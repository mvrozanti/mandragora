"""Output formatting utilities — truncation and Telegram message limits."""

import logging

logger = logging.getLogger(__name__)

# Telegram text message limit; leave room for Markdown overhead
MAX_MESSAGE_LENGTH = 4000


def truncate(text: str, max_chars: int = MAX_MESSAGE_LENGTH) -> tuple[str, bool]:
    """Truncate text to max_chars. Returns (text, was_truncated)."""
    if len(text) <= max_chars:
        return text, False
    cutoff = max_chars - 50  # room for the truncation notice
    return text[:cutoff] + f"\n\n… _(truncated, {len(text) - cutoff} chars omitted)_", True


def split_messages(text: str, max_length: int = MAX_MESSAGE_LENGTH) -> list[str]:
    """Split text into chunks that each fit within Telegram's message limit.

    Splits on newlines when possible to avoid breaking code blocks.
    """
    if len(text) <= max_length:
        return [text]

    chunks: list[str] = []
    while text:
        if len(text) <= max_length:
            chunks.append(text)
            break

        # Try to split on a newline near the boundary
        split_at = text.rfind("\n", 0, max_length)
        if split_at == -1:
            split_at = max_length

        chunks.append(text[:split_at])
        text = text[split_at:].lstrip("\n")

    if len(chunks) > 1:
        logger.info("Split output into %d messages", len(chunks))
    return chunks


def wrap_code(text: str, lang: str = "") -> str:
    """Wrap text in a Markdown code fence."""
    fence = f"```{lang}" if lang else "```"
    return f"{fence}\n{text}\n```"
