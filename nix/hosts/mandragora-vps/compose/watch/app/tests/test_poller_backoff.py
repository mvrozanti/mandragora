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
