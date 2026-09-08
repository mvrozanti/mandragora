import asyncio
import json

import pytest

import poller


def _last_reminder(db, event_id):
    c = db()
    row = c.execute("SELECT last_reminder_at FROM events WHERE id = ?", (event_id,)).fetchone()
    c.close()
    return row["last_reminder_at"]


@pytest.mark.parametrize(
    "verdict,should_push",
    [("GO", True), ("UNCLEAR", False), ("NO", False), (None, False)],
)
def test_only_go_pushes(db, make_watcher, make_event, captured_sends, verdict, should_push):
    wid = make_watcher()
    eid = make_event(wid, verdict=verdict)
    asyncio.run(poller._push_pending(db))
    assert (eid in captured_sends) is should_push
    assert (_last_reminder(db, eid) is not None) is should_push


def test_spec_less_watcher_pushes_without_verdict(db, make_watcher, make_event, captured_sends):
    wid = make_watcher(ai_spec=None)
    eid = make_event(wid)
    asyncio.run(poller._push_pending(db))
    assert captured_sends == [eid]


def test_muted_watcher_never_pushes(db, make_watcher, make_event, captured_sends):
    wid = make_watcher(push=0)
    make_event(wid, verdict="GO")
    asyncio.run(poller._push_pending(db))
    assert captured_sends == []


def test_disabled_watcher_never_pushes(db, make_watcher, make_event, captured_sends):
    wid = make_watcher(enabled=0)
    make_event(wid, verdict="GO")
    asyncio.run(poller._push_pending(db))
    assert captured_sends == []


def test_acked_event_never_pushes(db, make_watcher, make_event, captured_sends):
    import main

    wid = make_watcher()
    make_event(wid, verdict="GO", acked_at=main.now_iso())
    asyncio.run(poller._push_pending(db))
    assert captured_sends == []


def test_prerelease_is_skipped(db, make_watcher, make_event, captured_sends):
    wid = make_watcher(kind="github_release", target="spesmilo/electrum", ai_spec=None)
    make_event(wid, raw=json.dumps({"prerelease": True}))
    asyncio.run(poller._push_pending(db))
    assert captured_sends == []


def test_failed_send_is_retried_not_burned(db, make_watcher, make_event, monkeypatch):
    attempts = []

    async def failing_push(watcher, event):
        attempts.append(event["id"])
        return False

    monkeypatch.setattr(poller.tg, "push_event", failing_push)
    monkeypatch.setattr(poller.tg, "enabled", lambda: True)
    monkeypatch.setattr(poller, "WEBHOOK_URL", "")
    wid = make_watcher()
    eid = make_event(wid, verdict="GO")
    asyncio.run(poller._push_pending(db))
    assert _last_reminder(db, eid) is None
    asyncio.run(poller._push_pending(db))
    assert attempts == [eid, eid]


def test_unconfigured_telegram_does_not_burn_backlog(db, make_watcher, make_event, monkeypatch):
    sent = []

    async def disabled_push(watcher, event):
        sent.append(event["id"])
        return False

    monkeypatch.setattr(poller.tg, "push_event", disabled_push)
    monkeypatch.setattr(poller.tg, "enabled", lambda: False)
    monkeypatch.setattr(poller, "WEBHOOK_URL", "")
    wid = make_watcher()
    eid = make_event(wid, verdict="GO")
    asyncio.run(poller._push_pending(db))
    assert sent == []
    assert _last_reminder(db, eid) is not None


def test_reminder_only_repeats_for_ack_watchers(db, make_watcher, make_event, captured_sends):
    wid = make_watcher(requires_ack=0)
    eid = make_event(wid, verdict="GO")
    asyncio.run(poller._push_pending(db))
    asyncio.run(poller._push_pending(db))
    assert captured_sends == [eid]


def test_ack_watcher_reminds_when_interval_elapsed(db, make_watcher, make_event, captured_sends):
    wid = make_watcher(requires_ack=1, reminder_interval=60)
    eid = make_event(wid, verdict="GO", last_reminder_at="2020-01-01T00:00:00Z")
    asyncio.run(poller._push_pending(db))
    assert captured_sends == [eid]


def test_ack_watcher_holds_inside_interval(db, make_watcher, make_event, captured_sends):
    import main

    wid = make_watcher(requires_ack=1, reminder_interval=86400)
    make_event(wid, verdict="GO", last_reminder_at=main.now_iso())
    asyncio.run(poller._push_pending(db))
    assert captured_sends == []


def test_confirmed_push_records_last_push_at(db, make_watcher, make_event, captured_sends):
    import stats

    wid = make_watcher()
    make_event(wid, verdict="GO")
    asyncio.run(poller._push_pending(db))
    assert stats.get_meta(db, "last_push_at") is not None
