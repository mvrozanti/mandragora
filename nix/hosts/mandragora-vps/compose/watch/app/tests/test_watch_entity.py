import asyncio

import pytest

import main
import poller
from fastapi import HTTPException


def _watches(db):
    c = db()
    rows = c.execute("SELECT * FROM watches ORDER BY id").fetchall()
    c.close()
    return rows


def _set(db, wid, **cols):
    c = db()
    for k, v in cols.items():
        c.execute(f"UPDATE watchers SET {k} = ? WHERE id = ?", (v, wid))
    c.close()


def test_a_watch_has_one_condition_and_many_places(db, make_watcher):
    a = make_watcher(kind="rss", target="https://a.invalid/f", ai_spec=None)
    b = make_watcher(kind="hn_search", target="q", ai_spec=None)
    for wid in (a, b):
        _set(db, wid, condition="a new kindle jailbreak is released")
    c = db()
    main._migrate_conditions_to_watches(c)
    c.close()
    watches = _watches(db)
    assert len(watches) == 1
    assert watches[0]["condition"] == "a new kindle jailbreak is released"
    c = db()
    places = c.execute("SELECT COUNT(*) n FROM watchers WHERE watch_id = ?",
                       (watches[0]["id"],)).fetchone()["n"]
    c.close()
    assert places == 2


def test_migration_merges_places_split_across_watch_groups(db, make_watcher):
    a = make_watcher(kind="rss", target="https://a.invalid/f", ai_spec=None)
    b = make_watcher(kind="hn_search", target="q", ai_spec=None)
    _set(db, a, condition="same question", watch_group="g1")
    _set(db, b, condition="same question", watch_group="g2")
    c = db()
    main._migrate_conditions_to_watches(c)
    c.close()
    assert len(_watches(db)) == 1


def test_different_conditions_are_different_watches(db, make_watcher):
    a = make_watcher(kind="rss", target="https://a.invalid/f", ai_spec=None)
    b = make_watcher(kind="hn_search", target="q", ai_spec=None)
    _set(db, a, condition="one thing")
    _set(db, b, condition="another thing")
    c = db()
    main._migrate_conditions_to_watches(c)
    c.close()
    assert len(_watches(db)) == 2


def test_migration_is_idempotent(db, make_watcher):
    a = make_watcher(kind="rss", target="https://a.invalid/f", ai_spec=None)
    _set(db, a, condition="one thing")
    for _ in range(3):
        c = db()
        main._migrate_conditions_to_watches(c)
        c.close()
    assert len(_watches(db)) == 1


def test_a_feed_with_no_condition_is_left_alone(db, make_watcher):
    make_watcher(kind="github_release", target="a/b", ai_spec=None)
    c = db()
    main._migrate_conditions_to_watches(c)
    c.close()
    assert _watches(db) == []


def test_stop_condition_counts_across_the_whole_watch(db, make_watcher, make_event, captured_sends):
    a = make_watcher(kind="hn_search", target="a", ai_spec=None)
    b = make_watcher(kind="reddit_search", target="b", ai_spec=None)
    c = db()
    wid = main.create_watch(c, "fires twice then stops", stop_after=2)
    for x in (a, b):
        c.execute("UPDATE watchers SET watch_id = ? WHERE id = ?", (wid, x))
    c.close()

    make_event(a, external_id="a1")
    asyncio.run(poller._push_pending(db))
    c = db()
    still = c.execute("SELECT enabled FROM watches WHERE id = ?", (wid,)).fetchone()["enabled"]
    c.close()
    assert still == 1

    make_event(b, external_id="b1")
    asyncio.run(poller._push_pending(db))
    c = db()
    row = c.execute("SELECT enabled FROM watches WHERE id = ?", (wid,)).fetchone()
    places = c.execute("SELECT SUM(enabled) s FROM watchers WHERE watch_id = ?", (wid,)).fetchone()["s"]
    c.close()
    assert row["enabled"] == 0
    assert places == 0


def test_every_place_carries_its_watch(db, make_watcher):
    a = make_watcher(kind="rss", target="https://a.invalid/f", ai_spec=None)
    b = make_watcher(kind="hn_search", target="q", ai_spec=None)
    for wid in (a, b):
        _set(db, wid, condition="a new kindle jailbreak is released")
    c = db()
    main._migrate_conditions_to_watches(c)
    c.close()
    listed = asyncio.run(main.list_watchers())
    assert {w["condition"] for w in listed} == {"a new kindle jailbreak is released"}
    assert len({w["watch_id"] for w in listed}) == 1
    assert None not in {w["watch_id"] for w in listed}


def test_deleting_a_watch_removes_every_place(db, make_watcher):
    a = make_watcher(kind="rss", target="https://a.invalid/f", ai_spec=None)
    b = make_watcher(kind="hn_search", target="q", ai_spec=None)
    for wid in (a, b):
        _set(db, wid, condition="going away")
    c = db()
    main._migrate_conditions_to_watches(c)
    c.close()
    watch_id = _watches(db)[0]["id"]
    out = asyncio.run(main.delete_watch(watch_id))
    assert out["condition"] == "going away"
    assert out["places"] == 2
    c = db()
    left = c.execute("SELECT COUNT(*) n FROM watchers").fetchone()["n"]
    c.close()
    assert left == 0
    assert _watches(db) == []


def test_deleting_an_unknown_id_says_so(db):
    with pytest.raises(HTTPException) as caught:
        asyncio.run(main.delete_watch(999))
    assert caught.value.status_code == 404


def test_recent_triggers_lists_open_pushing_triggers_newest_first(db, make_watcher, make_event):
    gated = make_watcher(kind="rss", target="https://a.invalid/f", ai_spec="spec")
    plain = make_watcher(kind="hn_search", target="q", ai_spec=None)
    muted = make_watcher(kind="hn_search", target="muted", ai_spec=None, push=0)
    rejected = make_event(gated, external_id="r", verdict="NO")
    go = make_event(gated, external_id="g", verdict="GO")
    first = make_event(plain, external_id="p1")
    accepted = make_event(plain, external_id="p2", acked_at="2026-01-01T00:00:00Z")
    make_event(muted, external_id="m")
    ids = [t["id"] for t in asyncio.run(main.recent_triggers(limit=20, open_only=1, pushing=1))]
    assert ids == [first, go]
    assert rejected not in ids and accepted not in ids
    everything = [t["id"] for t in asyncio.run(main.recent_triggers(limit=20, open_only=0, pushing=0))]
    assert accepted in everything and rejected not in everything
