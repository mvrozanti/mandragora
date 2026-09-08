import json

import stats


def test_meta_roundtrip_and_overwrite(db):
    assert stats.get_meta(db, "last_push_at") is None
    stats.set_meta(db, "last_push_at", "2026-09-07T00:00:00Z")
    stats.set_meta(db, "last_push_at", "2026-09-07T01:00:00Z")
    assert stats.get_meta(db, "last_push_at") == "2026-09-07T01:00:00Z"


def test_funnel_counts_only_ai_gated_watchers(db, make_watcher, make_event):
    gated = make_watcher(kind="hn_search", target="electrum")
    ungated = make_watcher(kind="rss", target="https://news.example/feed", ai_spec=None)
    make_event(gated, external_id="a", verdict="GO")
    make_event(gated, external_id="b", verdict="NO")
    make_event(gated, external_id="c", verdict="UNCLEAR")
    make_event(gated, external_id="d")
    make_event(ungated, external_id="e")
    assert stats.funnel_counts(db) == {"GO": 1, "UNCLEAR": 1, "NO": 1, "pending": 1}


def test_funnel_window_excludes_older_events(db, make_watcher, make_event):
    wid = make_watcher()
    make_event(wid, external_id="old", verdict="GO", received_at="2020-01-01T00:00:00Z")
    make_event(wid, external_id="new", verdict="GO")
    assert stats.funnel_counts(db, stats.hours_ago_iso(24))["GO"] == 1
    assert stats.funnel_counts(db)["GO"] == 2


def test_pending_unjudged_ignores_disabled_watchers(db, make_watcher, make_event):
    active = make_watcher(kind="hn_search", target="electrum")
    paused = make_watcher(kind="rss", target="https://news.example/feed", enabled=0)
    make_event(active, external_id="a")
    make_event(paused, external_id="b")
    assert stats.pending_unjudged(db) == 1


def test_watcher_summary_counts_roles(db, make_watcher):
    make_watcher(kind="hn_search", target="electrum")
    make_watcher(kind="rss", target="https://news.example/feed", push=0)
    make_watcher(kind="reddit_sub", target="bitcoin", ai_spec=None)
    make_watcher(kind="github_repo", target="a/b", enabled=0)
    assert stats.watcher_summary(db) == {"total": 4, "enabled": 3, "pushing": 2, "judged": 1}


def test_undecidable_specs_lists_only_failures(db, make_watcher):
    good = make_watcher(kind="hn_search", target="electrum")
    bad = make_watcher(kind="rss", target="https://news.example/feed")
    c = db()
    c.execute(
        "UPDATE watchers SET spec_lint = ?, spec_lint_at = 'now' WHERE id = ?",
        (json.dumps({"decidable": True, "problems": [], "suggestion": ""}), good),
    )
    c.execute(
        "UPDATE watchers SET spec_lint = ?, spec_lint_at = 'now' WHERE id = ?",
        (json.dumps({"decidable": False, "problems": ["titles only"], "suggestion": "narrow"}), bad),
    )
    c.close()
    flagged = stats.undecidable_specs(db)
    assert [w["id"] for w in flagged] == [bad]


def test_collect_reports_backlog_and_totals(db, make_watcher, make_event):
    wid = make_watcher()
    make_event(wid, external_id="a", verdict="GO")
    make_event(wid, external_id="b")
    snapshot = stats.collect(db)
    assert snapshot["events_total"] == 2
    assert snapshot["pending_unjudged"] == 1
    assert snapshot["funnel_lifetime"]["GO"] == 1
    assert snapshot["last_push_at"] is None


def test_format_status_shows_disabled_telegram(db, make_watcher, make_event):
    wid = make_watcher()
    make_event(wid, verdict="GO")
    text = stats.format_status(stats.collect(db), False, [])
    assert "telegram: DISABLED" in text
    assert "GO 1" in text


def test_format_status_lists_undecidable_specs(db, make_watcher):
    wid = make_watcher(name="electrum-sec: hn")
    text = stats.format_status(stats.collect(db), True, [{"id": wid, "name": "electrum-sec: hn"}])
    assert "undecidable spec" in text
    assert "electrum-sec: hn" in text
