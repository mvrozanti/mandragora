import asyncio

import pytest

import compose
import poller


def _plan(**kw):
    base = {
        "name": "severance season 3",
        "condition": "severance season 3 is released",
        "stop_after": 1,
        "sources": [{"kind": "tvmaze_season", "target": "severance:3", "match": "", "why": "fact source"}],
    }
    base.update(kw)
    return base


def test_plan_rows_skips_unreachable_sources():
    plan = _plan(sources=[
        {"kind": "tvmaze_season", "target": "severance:3", "match": "", "why": ""},
        {"kind": "rss", "target": "https://invented.invalid/feed", "match": "x", "why": ""},
    ])
    checked = [
        {"ok": True, "resolved_target": "44933:3"},
        {"ok": False, "resolved_target": None, "error": "source unreachable"},
    ]
    rows = compose.plan_rows(plan, checked)
    assert len(rows) == 1
    assert rows[0]["kind"] == "tvmaze_season"
    assert rows[0]["target"] == "44933:3"


def test_plan_rows_share_one_group_and_stop_condition():
    plan = _plan(stop_after=2, sources=[
        {"kind": "hn_search", "target": "a", "match": "s", "why": ""},
        {"kind": "reddit_search", "target": "b", "match": "s", "why": ""},
    ])
    checked = [{"ok": True, "resolved_target": "a"}, {"ok": True, "resolved_target": "b"}]
    rows = compose.plan_rows(plan, checked)
    assert len({r["watch_group"] for r in rows}) == 1
    assert all(r["stop_after"] == 2 for r in rows)


def test_empty_rule_becomes_no_gate_at_all():
    rows = compose.plan_rows(_plan(), [{"ok": True, "resolved_target": "44933:3"}])
    assert rows[0]["match_rule"] is None


def test_rule_is_carried_through():
    plan = _plan(sources=[{"kind": "hn_search", "target": "q", "match": "electrum", "why": ""}])
    rows = compose.plan_rows(plan, [{"ok": True, "resolved_target": "q"}])
    assert rows[0]["match_rule"] == "electrum"


def test_preview_warns_when_nothing_is_reachable(monkeypatch):
    async def fake_probe(entry):
        return {**entry, "ok": False, "error": "source unreachable", "resolved_target": None,
                "samples": []}

    monkeypatch.setattr(compose, "probe_source", fake_probe)
    result = asyncio.run(compose.preview({
        "name": "n", "condition": "c", "stop_after": 0,
        "sources": [{"kind": "github_advisory", "target": "spesmilo/electrum", "match": "", "why": ""}],
    }))
    assert result["usable"] == 0
    assert any("nothing would ever fire" in w for w in result["warnings"])


def _group(db, watcher_ids, group, stop_after):
    c = db()
    for wid in watcher_ids:
        c.execute("UPDATE watchers SET watch_group = ?, stop_after = ? WHERE id = ?",
                  (group, stop_after, wid))
    c.close()


def _enabled(db, wid):
    c = db()
    row = c.execute("SELECT enabled FROM watchers WHERE id = ?", (wid,)).fetchone()
    c.close()
    return row["enabled"]


def test_watch_without_stop_condition_keeps_going(db, make_watcher, make_event, captured_sends):
    wid = make_watcher(ai_spec=None)
    make_event(wid, external_id="e1")
    asyncio.run(poller._push_pending(db))
    assert _enabled(db, wid) == 1


def test_watch_stops_itself_after_one_delivery(db, make_watcher, make_event, captured_sends):
    wid = make_watcher(ai_spec=None)
    _group(db, [wid], "g1", 1)
    make_event(wid, external_id="e1")
    asyncio.run(poller._push_pending(db))
    assert captured_sends
    assert _enabled(db, wid) == 0


def test_stop_condition_counts_across_the_whole_group(db, make_watcher, make_event, captured_sends):
    a = make_watcher(kind="hn_search", target="a", ai_spec=None)
    b = make_watcher(kind="reddit_search", target="b", ai_spec=None)
    _group(db, [a, b], "g2", 2)
    make_event(a, external_id="a1")
    asyncio.run(poller._push_pending(db))
    assert _enabled(db, a) == 1 and _enabled(db, b) == 1
    make_event(b, external_id="b1")
    asyncio.run(poller._push_pending(db))
    assert _enabled(db, a) == 0 and _enabled(db, b) == 0


def test_suppressed_backlog_does_not_count_toward_the_stop_condition(
    db, make_watcher, make_event, captured_sends
):
    wid = make_watcher(ai_spec=None)
    _group(db, [wid], "g3", 1)
    make_event(wid, external_id="old", last_reminder_at="2026-01-01T00:00:00Z")
    asyncio.run(poller._push_pending(db))
    assert captured_sends == []
    assert _enabled(db, wid) == 1


def test_notified_at_is_stamped_only_on_a_real_push(db, make_watcher, make_event, captured_sends):
    wid = make_watcher(ai_spec=None)
    eid = make_event(wid, external_id="e1")
    suppressed = make_event(wid, external_id="e2", last_reminder_at="2026-01-01T00:00:00Z")
    asyncio.run(poller._push_pending(db))
    c = db()
    rows = {r["id"]: r["notified_at"] for r in c.execute("SELECT id, notified_at FROM events")}
    c.close()
    assert rows[eid] is not None
    assert rows[suppressed] is None


@pytest.mark.parametrize("stop_after", [0, -1])
def test_non_positive_stop_after_never_stops(db, make_watcher, make_event, captured_sends, stop_after):
    wid = make_watcher(ai_spec=None)
    _group(db, [wid], "g4", stop_after)
    make_event(wid, external_id="e1")
    asyncio.run(poller._push_pending(db))
    assert _enabled(db, wid) == 1
