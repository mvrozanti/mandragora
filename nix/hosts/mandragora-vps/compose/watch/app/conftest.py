import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))


@pytest.fixture(autouse=True)
def no_reddit_pacing(monkeypatch):
    import sources

    monkeypatch.setattr(sources, "REDDIT_MIN_INTERVAL", 0.0)


@pytest.fixture
def db(tmp_path, monkeypatch):
    monkeypatch.setenv("WATCH_DATA_DIR", str(tmp_path))
    import main

    monkeypatch.setattr(main, "DATA_DIR", tmp_path)
    monkeypatch.setattr(main, "DB_PATH", tmp_path / "watch.db")
    main.init_db()
    return main.conn


@pytest.fixture
def make_watcher(db):
    def _make(kind="hn_search", target="electrum", name=None, ai_spec="spec", push=1, requires_ack=0,
              reminder_interval=3600, enabled=1):
        import main

        c = db()
        c.execute(
            "INSERT INTO watchers (kind, target, name, created_at, enabled, requires_ack, reminder_interval, ai_spec, push) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (kind, target, name or f"{kind}:{target}", main.now_iso(), enabled, requires_ack, reminder_interval, ai_spec, push),
        )
        row = c.execute("SELECT id FROM watchers WHERE kind = ? AND target = ?", (kind, target)).fetchone()
        c.close()
        return row["id"]

    return _make


@pytest.fixture
def make_event(db):
    def _make(watcher_id, external_id="e1", title="title", verdict=None, claim=None, link="https://example.invalid/a",
              last_reminder_at=None, acked_at=None, raw=None, received_at=None, subject=None, incident=None):
        import main

        c = db()
        c.execute(
            "INSERT INTO events (watcher_id, external_id, title, summary, link, occurred_at, received_at, raw, "
            "acked_at, last_reminder_at, ai_verdict, ai_claim, ai_subject, ai_incident) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (watcher_id, external_id, title, "summary", link, main.now_iso(), received_at or main.now_iso(),
             raw, acked_at, last_reminder_at, verdict, claim, subject, incident),
        )
        row = c.execute(
            "SELECT id FROM events WHERE watcher_id = ? AND external_id = ?", (watcher_id, external_id)
        ).fetchone()
        c.close()
        return row["id"]

    return _make


@pytest.fixture
def captured_sends(monkeypatch):
    sent = []

    async def fake_push(watcher, event):
        sent.append(event["id"])
        return True

    import poller

    monkeypatch.setattr(poller.tg, "push_event", fake_push)
    monkeypatch.setattr(poller.tg, "enabled", lambda: True)
    monkeypatch.setattr(poller, "WEBHOOK_URL", "")
    return sent
