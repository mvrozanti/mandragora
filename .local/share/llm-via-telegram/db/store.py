"""SQLite persistence layer for prompts and registered commands."""

import logging
import sqlite3

import config

logger = logging.getLogger(__name__)


def _get_connection() -> sqlite3.Connection:
    """Get a database connection with WAL mode enabled."""
    conn = sqlite3.connect(config.DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    """Create tables if they don't exist."""
    conn = _get_connection()
    try:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS prompts (
                name TEXT PRIMARY KEY,
                system_instruction TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS registered_commands (
                name TEXT PRIMARY KEY,
                sequence TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        conn.commit()
        logger.info("Database initialized at %s", config.DB_PATH)
    finally:
        conn.close()


# ── Prompt registration ──────────────────────────────────────────


def save_prompt(name: str, system_instruction: str) -> None:
    """Save or overwrite a named prompt."""
    conn = _get_connection()
    try:
        conn.execute(
            "INSERT OR REPLACE INTO prompts (name, system_instruction) VALUES (?, ?)",
            (name, system_instruction),
        )
        conn.commit()
    finally:
        conn.close()


def get_prompt(name: str) -> str | None:
    """Retrieve a named prompt's system instruction, or None."""
    conn = _get_connection()
    try:
        row = conn.execute("SELECT system_instruction FROM prompts WHERE name = ?", (name,)).fetchone()
        return row["system_instruction"] if row else None
    finally:
        conn.close()


def list_prompts() -> list[str]:
    """Return all registered prompt names."""
    conn = _get_connection()
    try:
        rows = conn.execute("SELECT name FROM prompts ORDER BY name").fetchall()
        return [r["name"] for r in rows]
    finally:
        conn.close()


def delete_prompt(name: str) -> bool:
    """Delete a prompt by name. Returns True if one was deleted."""
    conn = _get_connection()
    try:
        cur = conn.execute("DELETE FROM prompts WHERE name = ?", (name,))
        conn.commit()
        return cur.rowcount > 0
    finally:
        conn.close()


# ── Registered commands ──────────────────────────────────────────


def save_command_entry(name: str, sequence: str) -> None:
    """Save or overwrite a registered command."""
    conn = _get_connection()
    try:
        conn.execute(
            "INSERT OR REPLACE INTO registered_commands (name, sequence) VALUES (?, ?)",
            (name, sequence),
        )
        conn.commit()
    finally:
        conn.close()


def get_command_entry(name: str) -> str | None:
    """Retrieve a registered command sequence, or None."""
    conn = _get_connection()
    try:
        row = conn.execute(
            "SELECT sequence FROM registered_commands WHERE name = ?", (name,)
        ).fetchone()
        return row["sequence"] if row else None
    finally:
        conn.close()


def list_commands() -> list[tuple[str, str]]:
    """Return all registered commands as (name, sequence) pairs."""
    conn = _get_connection()
    try:
        rows = conn.execute(
            "SELECT name, sequence FROM registered_commands ORDER BY name"
        ).fetchall()
        return [(r["name"], r["sequence"]) for r in rows]
    finally:
        conn.close()


def delete_command_entry(name: str) -> bool:
    """Delete a registered command. Returns True if one was deleted."""
    conn = _get_connection()
    try:
        cur = conn.execute(
            "DELETE FROM registered_commands WHERE name = ?", (name,)
        )
        conn.commit()
        return cur.rowcount > 0
    finally:
        conn.close()
