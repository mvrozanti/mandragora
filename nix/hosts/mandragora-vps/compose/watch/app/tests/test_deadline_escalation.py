import asyncio
from datetime import datetime, timedelta, timezone

import pytest

import judge
import poller


def _hours_ago(hours):
    moment = datetime.now(timezone.utc) - timedelta(hours=hours)
    return moment.isoformat(timespec="seconds").replace("+00:00", "Z")


def _row(db, event_id):
    c = db()
    row = c.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
    c.close()
    return row


def _set_must_mention(db, watcher_id, literals):
    c = db()
    c.execute("UPDATE watchers SET must_mention = ? WHERE id = ?", (literals, watcher_id))
    c.close()


def test_fresh_unjudged_event_is_left_alone(db, make_watcher, make_event):
    wid = make_watcher()
    eid = make_event(wid)
    stats = asyncio.run(judge.sweep_deadline(db))
    assert stats == {"escalated": 0, "rejected": 0, "errors": 0}
    assert _row(db, eid)["escalated_at"] is None


def test_stale_unjudged_event_without_a_literal_gate_escalates(db, make_watcher, make_event):
    wid = make_watcher()
    eid = make_event(wid, received_at=_hours_ago(48))
    stats = asyncio.run(judge.sweep_deadline(db))
    assert stats["escalated"] == 1
    row = _row(db, eid)
    assert row["escalated_at"] is not None
    assert row["ai_verdict"] is None
    assert "unjudged after" in row["ai_reason"]


def test_stale_event_failing_its_literal_gate_is_rejected_not_escalated(
    db, make_watcher, make_event, monkeypatch
):
    async def no_fetch(url):
        return "", None

    monkeypatch.setattr(judge, "fetch_link", no_fetch)
    wid = make_watcher()
    _set_must_mention(db, wid, "electrum")
    eid = make_event(wid, title="CZ warns bitcoin holders after wallet exploit", received_at=_hours_ago(48))
    stats = asyncio.run(judge.sweep_deadline(db))
    assert stats == {"escalated": 0, "rejected": 1, "errors": 0}
    row = _row(db, eid)
    assert row["escalated_at"] is None
    assert row["ai_verdict"] == "NO"
    assert "electrum" in row["ai_reason"]


def test_stale_event_passing_its_literal_gate_escalates(db, make_watcher, make_event, monkeypatch):
    async def no_fetch(url):
        return "", None

    monkeypatch.setattr(judge, "fetch_link", no_fetch)
    wid = make_watcher()
    _set_must_mention(db, wid, "electrum")
    eid = make_event(wid, title="Electrum wallets under siege", received_at=_hours_ago(48))
    stats = asyncio.run(judge.sweep_deadline(db))
    assert stats["escalated"] == 1
    assert _row(db, eid)["escalated_at"] is not None


def test_literal_gate_reads_the_fetched_body(db, make_watcher, make_event, monkeypatch):
    async def body_fetch(url):
        return "halfway down the article it mentions electrum", None

    monkeypatch.setattr(judge, "fetch_link", body_fetch)
    wid = make_watcher()
    _set_must_mention(db, wid, "electrum")
    eid = make_event(wid, title="Wallet drained in sweep", received_at=_hours_ago(48))
    asyncio.run(judge.sweep_deadline(db))
    assert _row(db, eid)["escalated_at"] is not None


def test_judged_event_is_never_escalated(db, make_watcher, make_event):
    wid = make_watcher()
    eid = make_event(wid, verdict="NO", received_at=_hours_ago(48))
    stats = asyncio.run(judge.sweep_deadline(db))
    assert stats["escalated"] == 0
    assert _row(db, eid)["escalated_at"] is None


def test_sweep_is_idempotent(db, make_watcher, make_event):
    wid = make_watcher()
    make_event(wid, received_at=_hours_ago(48))
    asyncio.run(judge.sweep_deadline(db))
    again = asyncio.run(judge.sweep_deadline(db))
    assert again["escalated"] == 0


def test_disabled_watcher_is_not_swept(db, make_watcher, make_event):
    wid = make_watcher(enabled=0)
    eid = make_event(wid, received_at=_hours_ago(48))
    asyncio.run(judge.sweep_deadline(db))
    assert _row(db, eid)["escalated_at"] is None


def test_escalated_event_pushes(db, make_watcher, make_event, captured_sends):
    wid = make_watcher()
    eid = make_event(wid, received_at=_hours_ago(48))
    asyncio.run(judge.sweep_deadline(db))
    asyncio.run(poller._push_pending(db))
    assert captured_sends == [eid]


def test_escalated_event_carries_the_unjudged_badge(monkeypatch):
    import telegram as tg

    sent = {}

    async def fake_post(method, payload):
        sent.update(payload)
        return {"ok": True}

    monkeypatch.setattr(tg, "_post", fake_post)
    monkeypatch.setattr(tg, "BOT_TOKEN", "x")
    monkeypatch.setattr(tg, "ALLOWED_CHAT_IDS", {1})
    watcher = {"id": 1, "kind": "rss", "target": "t", "name": "n", "requires_ack": 0}
    event = {"id": 2, "title": "something", "ai_verdict": None, "escalated_at": "2026-09-09T00:00:00Z"}
    assert asyncio.run(tg.push_event(watcher, event))
    assert "⚪ UNJUDGED" in sent["text"]


def test_deadline_of_zero_disables_the_sweep(db, make_watcher, make_event, monkeypatch):
    monkeypatch.setattr(judge, "DEADLINE_HOURS", 0)
    wid = make_watcher()
    eid = make_event(wid, received_at=_hours_ago(999))
    stats = asyncio.run(judge.sweep_deadline(db))
    assert stats["escalated"] == 0
    assert _row(db, eid)["escalated_at"] is None


@pytest.mark.parametrize("verdict", ["GO", "NO"])
def test_prune_keeps_unjudged_events_but_trims_judged_ones(db, make_watcher, make_event, verdict):
    wid = make_watcher()
    for i in range(6):
        make_event(wid, external_id=f"judged{i}", verdict=verdict)
    held = [make_event(wid, external_id=f"held{i}") for i in range(3)]
    c = db()
    import os

    os.environ["WATCH_MAX_EVENTS_PER_WATCHER"] = "4"
    try:
        poller._prune(c, wid)
        rows = {r["external_id"] for r in c.execute("SELECT external_id FROM events WHERE watcher_id = ?", (wid,))}
    finally:
        os.environ.pop("WATCH_MAX_EVENTS_PER_WATCHER", None)
        c.close()
    assert {f"held{i}" for i in range(3)} <= rows
    assert len(held) == 3
    assert "judged0" not in rows


def test_sweep_holds_while_the_model_loop_is_producing_verdicts(
    db, make_watcher, make_event, monkeypatch
):
    monkeypatch.setattr(judge, "JUDGE_ENABLED", True)
    wid = make_watcher()
    stale = make_event(wid, external_id="stale", received_at=_hours_ago(48))
    c = db()
    c.execute(
        "UPDATE events SET ai_verdict = 'NO', ai_judged_at = ? WHERE id = ?",
        (judge._now_iso(), make_event(wid, external_id="justjudged")),
    )
    c.close()
    stats = asyncio.run(judge.sweep_deadline(db))
    assert stats["escalated"] == 0
    assert _row(db, stale)["escalated_at"] is None


def test_sweep_resumes_once_the_model_loop_goes_quiet(db, make_watcher, make_event, monkeypatch):
    monkeypatch.setattr(judge, "JUDGE_ENABLED", True)
    wid = make_watcher()
    stale = make_event(wid, external_id="stale", received_at=_hours_ago(48))
    c = db()
    c.execute(
        "UPDATE events SET ai_verdict = 'NO', ai_judged_at = ? WHERE id = ?",
        (_hours_ago(6), make_event(wid, external_id="judgedlongago")),
    )
    c.close()
    stats = asyncio.run(judge.sweep_deadline(db))
    assert stats["escalated"] == 1
    assert _row(db, stale)["escalated_at"] is not None


def test_sweep_never_holds_when_the_model_loop_is_off(db, make_watcher, make_event, monkeypatch):
    monkeypatch.setattr(judge, "JUDGE_ENABLED", False)
    wid = make_watcher()
    stale = make_event(wid, external_id="stale", received_at=_hours_ago(48))
    c = db()
    c.execute(
        "UPDATE events SET ai_verdict = 'NO', ai_judged_at = ? WHERE id = ?",
        (judge._now_iso(), make_event(wid, external_id="justjudged")),
    )
    c.close()
    asyncio.run(judge.sweep_deadline(db))
    assert _row(db, stale)["escalated_at"] is not None
