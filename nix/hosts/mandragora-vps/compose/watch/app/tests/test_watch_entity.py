import asyncio

import pytest

import main
import poller
import telegram as tg


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


def test_list_addresses_watches_not_places(db, make_watcher):
    a = make_watcher(kind="rss", target="https://a.invalid/f", ai_spec=None)
    b = make_watcher(kind="hn_search", target="q", ai_spec=None)
    for wid in (a, b):
        _set(db, wid, condition="a new kindle jailbreak is released")
    c = db()
    main._migrate_conditions_to_watches(c)
    c.close()
    out = asyncio.run(tg._cmd_list(db))
    assert out.count("a new kindle jailbreak is released") == 1
    assert "2 places" in out


def test_deleting_a_watch_removes_every_place(db, make_watcher):
    a = make_watcher(kind="rss", target="https://a.invalid/f", ai_spec=None)
    b = make_watcher(kind="hn_search", target="q", ai_spec=None)
    for wid in (a, b):
        _set(db, wid, condition="going away")
    c = db()
    main._migrate_conditions_to_watches(c)
    c.close()
    watch_id = _watches(db)[0]["id"]
    out = asyncio.run(tg._cmd_del(db, [str(watch_id)]))
    assert "going away" in out
    c = db()
    left = c.execute("SELECT COUNT(*) n FROM watchers").fetchone()["n"]
    c.close()
    assert left == 0
    assert _watches(db) == []


def test_deleting_an_unknown_id_says_so(db):
    assert "no watch" in asyncio.run(tg._cmd_del(db, ["999"]))
