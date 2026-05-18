#!/usr/bin/env python3
import argparse
import hashlib
import html
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
import tomllib
from pathlib import Path

import feedparser

XDG_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
XDG_DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
CONFIG_DIR = XDG_CONFIG / "rss-menu"
CONFIG_PATH = CONFIG_DIR / "config.toml"
DATA_DIR = XDG_DATA / "rss-menu"
DB_PATH = DATA_DIR / "state.db"
WAYBAR_SIGNAL = "SIGRTMIN+10"

DEFAULT_CONFIG = """\
poll_interval_minutes = 15
max_items_per_feed = 20

[[feeds]]
name = "NixOS news"
url = "https://nixos.org/blog/announcements-rss.xml"

[[feeds]]
name = "Hacker News (front page)"
url = "https://hnrss.org/frontpage"

[[feeds]]
name = "LWN headlines"
url = "https://lwn.net/headlines/newrss"
"""


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_PATH.write_text(DEFAULT_CONFIG)
    with CONFIG_PATH.open("rb") as fh:
        return tomllib.load(fh)


def db() -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            feed_name TEXT NOT NULL,
            feed_url TEXT NOT NULL,
            entry_url TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT,
            published_ts INTEGER,
            fetched_ts INTEGER NOT NULL,
            urgency INTEGER DEFAULT -1,
            verdict_reason TEXT,
            read INTEGER DEFAULT 0,
            notified INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_items_unread
            ON items(read, urgency, published_ts);
        """
    )
    conn.commit()
    return conn


def item_id(feed_url: str, entry) -> str:
    raw = entry.get("id") or entry.get("link") or entry.get("title", "")
    return hashlib.sha1(f"{feed_url}|{raw}".encode("utf-8", "replace")).hexdigest()


_HTML_TAG_RE = re.compile(r"<[^>]+>")


def entry_summary(entry) -> str:
    raw = entry.get("summary") or entry.get("description") or ""
    text = _HTML_TAG_RE.sub(" ", raw)
    text = html.unescape(text)
    text = " ".join(text.split())
    return text[:600]


def published_ts(entry) -> int | None:
    for key in ("published_parsed", "updated_parsed"):
        v = entry.get(key)
        if v:
            try:
                return int(time.mktime(v))
            except (TypeError, ValueError):
                continue
    return None


def refresh_waybar() -> None:
    subprocess.run(
        ["pkill", "--signal", WAYBAR_SIGNAL, "waybar"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def cmd_poll(args) -> int:
    cfg = load_config()
    max_per_feed = int(cfg.get("max_items_per_feed", 20))
    conn = db()
    new_total = 0
    for feed in cfg.get("feeds", []):
        try:
            parsed = feedparser.parse(feed["url"])
        except Exception as e:
            print(f"feed error {feed['name']}: {e}", file=sys.stderr)
            continue
        for entry in parsed.entries[:max_per_feed]:
            iid = item_id(feed["url"], entry)
            row = conn.execute("SELECT 1 FROM items WHERE id=?", (iid,)).fetchone()
            if row:
                continue
            title = (entry.get("title") or "(untitled)").strip()
            summary = entry_summary(entry)
            link = entry.get("link") or ""
            conn.execute(
                """INSERT INTO items
                   (id, feed_name, feed_url, entry_url, title, summary,
                    published_ts, fetched_ts, urgency, verdict_reason)
                   VALUES (?,?,?,?,?,?,?,?,?,?)""",
                (
                    iid,
                    feed["name"],
                    feed["url"],
                    link,
                    title,
                    summary,
                    published_ts(entry),
                    int(time.time()),
                    1,
                    "",
                ),
            )
            new_total += 1
        conn.commit()
    print(f"new={new_total}")
    refresh_waybar()
    return 0


def waybar_payload() -> dict:
    if not DB_PATH.exists():
        return {"text": "", "tooltip": "rss-menu not yet polled", "class": "empty"}
    conn = db()
    unread = conn.execute("SELECT COUNT(*) FROM items WHERE read=0").fetchone()[0]
    urgent = conn.execute(
        "SELECT COUNT(*) FROM items WHERE read=0 AND urgency>=2"
    ).fetchone()[0]
    top = conn.execute(
        """SELECT feed_name, title, urgency FROM items
           WHERE read=0
           ORDER BY urgency DESC, COALESCE(published_ts, fetched_ts) DESC
           LIMIT 8"""
    ).fetchall()
    icon = ""
    if unread == 0:
        text = icon
        cls = "empty"
    elif urgent > 0:
        text = icon
        cls = "urgent"
    else:
        text = icon
        cls = "unread"
    tooltip_lines = [f"{unread} unread, {urgent} notable"]
    for feed_name, title, urgency in top:
        marker = "" if urgency >= 3 else ("" if urgency >= 2 else "·")
        tooltip_lines.append(f"{marker} {feed_name}: {title}")
    tooltip = "\n".join(tooltip_lines)
    return {"text": text, "tooltip": tooltip, "class": cls, "alt": cls}


def cmd_waybar(args) -> int:
    print(json.dumps(waybar_payload()), flush=True)
    return 0


def rofi_pick(rows) -> str | None:
    if not rows:
        rows = [("__empty__", "no unread items — press enter to close", 0)]
    lines = []
    for iid, label, urgency in rows:
        prefix = "" if urgency >= 3 else ("" if urgency >= 2 else " ")
        lines.append(f"{prefix} {label}\x00info\x1f{iid}")
    theme = Path.home() / ".config/rofi/themes/menu.rasi"
    proc = subprocess.run(
        [
            "rofi",
            "-dmenu",
            "-i",
            "-p",
            "rss",
            "-theme",
            str(theme),
            "-theme-str",
            "window { width: 46%; } listview { lines: 14; }",
            "-format",
            "i:s",
            "-kb-custom-1",
            "Alt+a",
            "-kb-custom-2",
            "Alt+r",
            "-mesg",
            "<b>Enter</b> open · <b>Alt+a</b> mark all read · <b>Alt+r</b> refresh",
        ],
        input="\n".join(lines),
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode == 10:
        return "__mark_all__"
    if proc.returncode == 11:
        return "__refresh__"
    if proc.returncode != 0:
        return None
    out = proc.stdout.strip()
    if not out:
        return None
    idx_str, _, _label = out.partition(":")
    try:
        idx = int(idx_str)
    except ValueError:
        return None
    if idx < 0 or idx >= len(rows):
        return None
    return rows[idx][0]


def cmd_pick(args) -> int:
    conn = db()
    where = "WHERE read=0" if not args.all else ""
    rows = conn.execute(
        f"""SELECT id, feed_name, title, urgency, COALESCE(published_ts, fetched_ts) AS ts
            FROM items
            {where}
            ORDER BY urgency DESC, ts DESC
            LIMIT 200"""
    ).fetchall()
    formatted = [(r[0], f"[{r[1]}] {r[2]}", r[3]) for r in rows]
    selection = rofi_pick(formatted)
    if selection is None:
        return 0
    if selection == "__empty__":
        return 0
    if selection == "__mark_all__":
        conn.execute("UPDATE items SET read=1 WHERE read=0")
        conn.commit()
        refresh_waybar()
        return 0
    if selection == "__refresh__":
        subprocess.Popen(
            ["systemctl", "--user", "start", "rss-menu-poll.service"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return 0
    row = conn.execute(
        "SELECT entry_url FROM items WHERE id=?", (selection,)
    ).fetchone()
    if not row or not row[0]:
        return 0
    subprocess.Popen(
        ["xdg-open", row[0]],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    conn.execute("UPDATE items SET read=1 WHERE id=?", (selection,))
    conn.commit()
    refresh_waybar()
    return 0


def cmd_mark_all_read(args) -> int:
    conn = db()
    conn.execute("UPDATE items SET read=1 WHERE read=0")
    conn.commit()
    refresh_waybar()
    return 0


def cmd_edit_config(args) -> int:
    load_config()  # materialize default
    editor = os.environ.get("EDITOR", "nvim")
    os.execvp(editor, [editor, str(CONFIG_PATH)])


def main() -> int:
    p = argparse.ArgumentParser(prog="rss-menu")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("poll").set_defaults(func=cmd_poll)
    sub.add_parser("waybar").set_defaults(func=cmd_waybar)
    pick = sub.add_parser("pick")
    pick.add_argument("--all", action="store_true", help="include already-read items")
    pick.set_defaults(func=cmd_pick)
    sub.add_parser("mark-all-read").set_defaults(func=cmd_mark_all_read)
    sub.add_parser("edit-config").set_defaults(func=cmd_edit_config)
    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
