import poller


def test_backoff_grows_and_caps():
    waits = [poller.backoff_seconds(n) for n in range(1, 12)]
    assert waits[0] >= poller.POLL_INTERVAL
    for earlier, later in zip(waits, waits[1:]):
        assert later >= earlier * 0.9
    assert max(waits) <= poller.BACKOFF_CAP_SECONDS * 1.11


def test_backoff_honours_a_larger_retry_after_hint():
    plain = poller.backoff_seconds(1)
    hinted = poller.backoff_seconds(1, 3600)
    assert hinted > plain
    assert hinted <= poller.BACKOFF_CAP_SECONDS * 1.11


def test_backoff_ignores_a_smaller_retry_after_hint():
    assert poller.backoff_seconds(6, 1) >= poller.backoff_seconds(6) * 0.9


def test_manual_poll_clears_the_backoff(db, make_watcher, monkeypatch):
    import asyncio

    import main
    import sources

    wid = make_watcher(kind="reddit_search", target="pluribus season 2")
    c = db()
    c.execute(
        "UPDATE watchers SET fail_count = 9, retry_after = '2099-01-01T00:00:00Z', "
        "last_error = 'reddit refused the request (403)' WHERE id = ?",
        (wid,),
    )
    c.close()

    async def fetch(kind, target, cursor):
        return [{"external_id": "t3_a", "title": "post: x", "summary": "s",
                 "link": "https://example.invalid/a", "occurred_at": main.now_iso(), "raw": {}}], "1"

    monkeypatch.setattr(sources, "fetch", fetch)
    monkeypatch.setattr(main, "conn", db)
    assert asyncio.run(main.poll_now(wid))["ok"] is True

    c = db()
    row = c.execute("SELECT fail_count, retry_after, last_error FROM watchers WHERE id = ?", (wid,)).fetchone()
    c.close()
    assert row["fail_count"] == 0
    assert row["retry_after"] is None
    assert row["last_error"] is None


class _Row(dict):
    def __getitem__(self, k):
        return dict.__getitem__(self, k)


def _rows(*specs):
    return [_Row(id=i, kind=k, last_polled_at=p) for i, k, p in specs]


def test_only_one_reddit_watcher_polls_per_cycle():
    import poller

    rows = _rows(
        (1, "rss", "2026-01-01T00:00:00Z"),
        (2, "reddit_search", "2026-09-08T10:00:00Z"),
        (3, "reddit_search", "2026-09-08T08:00:00Z"),
        (4, "reddit_sub", "2026-09-08T09:00:00Z"),
        (5, "github_release", "2026-01-01T00:00:00Z"),
    )
    kept = poller.ration_reddit(rows)
    assert [r["id"] for r in kept] == [1, 3, 5]


def test_rationing_prefers_the_least_recently_polled():
    import poller

    rows = _rows(
        (2, "reddit_search", "2026-09-08T10:00:00Z"),
        (3, "reddit_search", None),
        (4, "reddit_user", "2026-09-08T09:00:00Z"),
    )
    assert [r["id"] for r in poller.ration_reddit(rows)] == [3]


def test_non_reddit_watchers_are_never_rationed():
    import poller

    rows = _rows(
        (1, "rss", None),
        (2, "hn_search", None),
        (3, "github_release", None),
    )
    assert poller.ration_reddit(rows) == rows


def test_a_single_reddit_watcher_is_left_alone():
    import poller

    rows = _rows((1, "reddit_search", None), (2, "rss", None))
    assert poller.ration_reddit(rows) == rows


def test_ration_limit_is_configurable():
    import poller

    rows = _rows(
        (1, "reddit_search", "2026-09-08T10:00:00Z"),
        (2, "reddit_search", "2026-09-08T08:00:00Z"),
        (3, "reddit_search", "2026-09-08T09:00:00Z"),
    )
    assert [r["id"] for r in poller.ration_reddit(rows, limit=2)] == [2, 3]
