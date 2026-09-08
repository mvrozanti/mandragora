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
