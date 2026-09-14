import asyncio

import pytest

import main


def _row(db, wid):
    c = db()
    row = c.execute("SELECT * FROM watchers WHERE id = ?", (wid,)).fetchone()
    c.close()
    return row


def test_create_accepts_and_persists_a_match_rule(db):
    out = asyncio.run(main.create_watcher({
        "kind": "anticheat_game", "target": "battlefield",
        "match_rule": '"now Supported" OR "now Running"',
    }))
    assert out["match_rule"] == '"now Supported" OR "now Running"'
    assert _row(db, out["id"])["match_rule"] == '"now Supported" OR "now Running"'


def test_create_without_a_rule_leaves_it_null(db):
    out = asyncio.run(main.create_watcher({"kind": "hn_search", "target": "anything"}))
    assert out["match_rule"] is None


def test_create_rejects_an_unparseable_rule(db):
    with pytest.raises(main.HTTPException) as e:
        asyncio.run(main.create_watcher({
            "kind": "hn_search", "target": "x", "match_rule": "a AND ("
        }))
    assert e.value.status_code == 400
    assert "will not parse" in e.value.detail


def test_create_accepts_a_stop_condition(db):
    out = asyncio.run(main.create_watcher({
        "kind": "hn_search", "target": "y", "stop_after": 1,
    }))
    assert out["stop_after"] == 1
    assert _row(db, out["id"])["stop_after"] == 1


def test_patch_sets_a_rule(db):
    out = asyncio.run(main.create_watcher({"kind": "hn_search", "target": "z"}))
    asyncio.run(main.patch_watcher(out["id"], {"match_rule": "jailbreak"}))
    assert _row(db, out["id"])["match_rule"] == "jailbreak"


def test_patch_clears_a_rule(db):
    out = asyncio.run(main.create_watcher({
        "kind": "hn_search", "target": "w", "match_rule": "jailbreak",
    }))
    asyncio.run(main.patch_watcher(out["id"], {"match_rule": ""}))
    assert _row(db, out["id"])["match_rule"] is None


def test_patch_rejects_an_unparseable_rule(db):
    out = asyncio.run(main.create_watcher({"kind": "hn_search", "target": "v"}))
    with pytest.raises(main.HTTPException) as e:
        asyncio.run(main.patch_watcher(out["id"], {"match_rule": "NOT"}))
    assert e.value.status_code == 400


def test_listing_exposes_the_rule_so_the_ui_can_show_it(db):
    asyncio.run(main.create_watcher({
        "kind": "hn_search", "target": "listed", "match_rule": "jailbreak",
    }))
    rows = asyncio.run(main.list_watchers())
    assert any(r["match_rule"] == "jailbreak" for r in rows)
