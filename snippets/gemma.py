import os
import sqlite3
from pathlib import Path

data_dir = (
    Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "oterm-gemma"
)
os.environ["OTERM_DATA_DIR"] = str(data_dir)
data_dir.mkdir(parents=True, exist_ok=True)

db_path = data_dir / "store.db"
is_new = not db_path.exists()
conn = sqlite3.connect(db_path)

if is_new:
    conn.executescript("""
        CREATE TABLE chat (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            model TEXT NOT NULL,
            system TEXT,
            format TEXT,
            parameters TEXT DEFAULT '{}',
            keep_alive INTEGER DEFAULT 5,
            tools TEXT DEFAULT '[]',
            thinking BOOLEAN DEFAULT 0
        );
        CREATE TABLE message (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id INTEGER NOT NULL,
            author TEXT NOT NULL,
            text TEXT NOT NULL,
            images TEXT DEFAULT '[]',
            FOREIGN KEY(chat_id) REFERENCES chat(id) ON DELETE CASCADE
        );
        PRAGMA user_version = 3591;
    """)
    conn.execute(
        "INSERT INTO chat (name, model, system, format, keep_alive) VALUES (?, ?, ?, ?, ?)",
        ("gemma", "gemma3:27b", "", "", 5),
    )

try:
    conn.execute("UPDATE chat SET format = '' WHERE format IS NULL")
    conn.execute("UPDATE chat SET system = '' WHERE system IS NULL")
except sqlite3.OperationalError:
    pass

conn.commit()
conn.close()

os.execvp("oterm", ["oterm"])
