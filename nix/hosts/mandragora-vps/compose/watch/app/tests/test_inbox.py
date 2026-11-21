import asyncio

import httpx

import inbox


class _Response:
    def __init__(self, status_code, text=""):
        self.status_code = status_code
        self.text = text


def _install(monkeypatch, responses):
    posted = []

    async def fake_post(self, url, json=None):
        posted.append((url, json))
        result = responses[len(posted) - 1]
        if isinstance(result, Exception):
            raise result
        return result

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    monkeypatch.setattr(inbox, "INBOX_URL", "http://desk.invalid/api/inbox")
    return posted


WATCHER = {"id": 7, "kind": "rss", "target": "https://a.invalid/f", "requires_ack": 0}


def test_disabled_without_a_url(monkeypatch):
    monkeypatch.setattr(inbox, "INBOX_URL", "")
    assert inbox.enabled() is False
    assert asyncio.run(inbox.push_event(WATCHER, {"id": 1, "title": "t"})) is False
    assert asyncio.run(inbox.broadcast("hello")) is False


def test_push_event_confirms_delivery(monkeypatch):
    posted = _install(monkeypatch, [_Response(200)])
    assert asyncio.run(inbox.push_event(WATCHER, {"id": 1, "title": "t", "link": "https://x.invalid"})) is True
    url, payload = posted[0]
    assert url == "http://desk.invalid/api/inbox"
    assert payload["source"] == "watch"
    assert payload["open"] == "watch"
    assert payload["ref"] == {"event": 1, "watcher": 7}
    assert payload["link"] == "https://x.invalid"
    assert payload["level"] == "info"


def test_ack_watchers_raise_alerts(monkeypatch):
    posted = _install(monkeypatch, [_Response(200)])
    asyncio.run(inbox.push_event({**WATCHER, "requires_ack": 1}, {"id": 2, "title": "t"}))
    assert posted[0][1]["level"] == "alert"


def test_headline_names_the_place_and_badges_in_words():
    title = inbox.headline(WATCHER, {"is_reminder": True, "ai_verdict": "GO"})
    assert title == "reminder · go · rss · https://a.invalid/f"
    assert inbox.headline(WATCHER, {"escalated_at": "x"}).startswith("unjudged · ")


def test_body_is_plain_text():
    text = inbox.body({"title": "a <b>", "summary": "s" * 900, "ai_reason": "fits"})
    assert text.splitlines()[0] == "a <b>"
    assert len(text.splitlines()[1]) == inbox.SUMMARY_MAX
    assert text.splitlines()[2] == "why: fits"


def test_unreachable_desktop_is_retried(monkeypatch):
    _install(monkeypatch, [httpx.ConnectError("no route")])
    assert asyncio.run(inbox.push_event(WATCHER, {"id": 1, "title": "t"})) is False


def test_server_error_is_retried(monkeypatch):
    _install(monkeypatch, [_Response(503)])
    assert asyncio.run(inbox.push_event(WATCHER, {"id": 1, "title": "t"})) is False


def test_refused_message_is_not_retried_forever(monkeypatch):
    _install(monkeypatch, [_Response(400, "text required")])
    assert asyncio.run(inbox.push_event(WATCHER, {"id": 1, "title": "t"})) is True


def test_broadcast_carries_title_level_and_link(monkeypatch):
    posted = _install(monkeypatch, [_Response(200)])
    assert asyncio.run(inbox.broadcast("body", title="watch backlog", level="alert", link="https://w.invalid/healthz")) is True
    payload = posted[0][1]
    assert payload == {"source": "watch", "title": "watch backlog", "text": "body", "open": "watch", "level": "alert", "link": "https://w.invalid/healthz"}


def test_refused_broadcast_reports_failure(monkeypatch):
    _install(monkeypatch, [_Response(400)])
    assert asyncio.run(inbox.broadcast("body")) is False
