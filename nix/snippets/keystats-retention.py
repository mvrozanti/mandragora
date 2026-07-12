#!/usr/bin/env python3
import os
import re
import sys
import time
from pathlib import Path

import sqlcipher3

DB_PATH = Path(os.environ["KEYSTATS_DB_PATH"])
DB_KEY_FILE = Path(os.environ["KEYSTATS_DB_KEY_FILE"])

TEXT_DB_KEY_FILE = os.environ.get("KEYSTATS_TEXT_DB_KEY_FILE", "").strip()
TEXT_DB_PATH = os.environ.get("KEYSTATS_TEXT_DB_PATH", "").strip()
TEXT_ENABLED = bool(TEXT_DB_KEY_FILE and TEXT_DB_PATH)

RAW_RETENTION_DAYS = int(os.environ.get("KEYSTATS_RAW_RETENTION_DAYS", "90"))
WORD_DECAY_DAYS = int(os.environ.get("KEYSTATS_WORD_DECAY_DAYS", "30"))
HEX_RE = re.compile(r"[0-9a-fA-F]{64}")


def load_key(path: Path) -> str:
    raw = path.read_text().strip()
    if not HEX_RE.fullmatch(raw):
        sys.exit(f"keystats-retention: db key at {path} must be 64 hex chars")
    return raw


def keyed(conn, key_hex: str) -> None:
    cur = conn.cursor()
    cur.execute(f"PRAGMA key = \"x'{key_hex}'\"")
    cur.execute("PRAGMA cipher_compatibility = 4")


def prune_stats(now: int) -> None:
    cutoff_minute = now // 60 - RAW_RETENTION_DAYS * 24 * 60
    cutoff_epoch = now - RAW_RETENTION_DAYS * 86400
    conn = sqlcipher3.connect(str(DB_PATH))
    try:
        keyed(conn, load_key(DB_KEY_FILE))
        cur = conn.cursor()
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS wpm_daily(
              day_epoch INTEGER PRIMARY KEY,
              chars INTEGER NOT NULL,
              words INTEGER NOT NULL
            )
            """
        )
        cur.execute(
            "INSERT INTO wpm_daily(day_epoch, chars, words) "
            "SELECT (minute_epoch / 1440) * 1440 AS day_epoch, "
            "SUM(chars), SUM(words) FROM wpm_bucket "
            "WHERE minute_epoch < ? GROUP BY day_epoch "
            "ON CONFLICT(day_epoch) DO UPDATE SET chars = excluded.chars, words = excluded.words",
            (cutoff_minute,),
        )
        rolled = cur.rowcount
        cur.execute("DELETE FROM wpm_bucket WHERE minute_epoch < ?", (cutoff_minute,))
        deleted_minutes = cur.rowcount
        cur.execute("DELETE FROM session WHERE end_epoch < ?", (cutoff_epoch,))
        deleted_sessions = cur.rowcount
        conn.commit()
        cur.execute("VACUUM")
        print(
            f"keystats-retention: stats rolled_days={rolled} "
            f"pruned_minutes={deleted_minutes} pruned_sessions={deleted_sessions} "
            f"retention_days={RAW_RETENTION_DAYS}",
            file=sys.stderr,
        )
    finally:
        conn.close()


def prune_text(now: int) -> None:
    if not TEXT_ENABLED or not Path(TEXT_DB_PATH).exists():
        return
    decay_cutoff = now - WORD_DECAY_DAYS * 86400
    cand_cutoff_day = now // 86400 - RAW_RETENTION_DAYS
    conn = sqlcipher3.connect(TEXT_DB_PATH)
    try:
        keyed(conn, load_key(Path(TEXT_DB_KEY_FILE)))
        cur = conn.cursor()
        cur.execute(
            "UPDATE word_count SET count = count / 2 WHERE last_seen < ?",
            (decay_cutoff,),
        )
        cur.execute("DELETE FROM word_count WHERE count = 0")
        decayed = cur.rowcount
        cur.execute("DELETE FROM word_candidate WHERE day < ?", (cand_cutoff_day,))
        pruned_candidates = cur.rowcount
        conn.commit()
        cur.execute("VACUUM")
        print(
            f"keystats-retention: text decayed_dropped={decayed} "
            f"pruned_candidates={pruned_candidates} decay_days={WORD_DECAY_DAYS} "
            f"retention_days={RAW_RETENTION_DAYS}",
            file=sys.stderr,
        )
    finally:
        conn.close()


def main() -> None:
    now = int(time.time())
    prune_stats(now)
    prune_text(now)


if __name__ == "__main__":
    main()
