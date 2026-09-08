import asyncio

import httpx
import pytest

import telegram as tg


class _Response:
    def __init__(self, status_code, payload=None, text=""):
        self.status_code = status_code
        self._payload = payload or {}
        self.text = text

    def json(self):
        return self._payload


def _install(monkeypatch, responses, sleeps=None):
    calls = []

    async def fake_post(self, url, json=None):
        calls.append(url)
        return responses[len(calls) - 1]

    async def fake_sleep(seconds):
        (sleeps if sleeps is not None else []).append(seconds)

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    monkeypatch.setattr(tg.asyncio, "sleep", fake_sleep)
    monkeypatch.setattr(tg, "BOT_TOKEN", "token")
    return calls


def test_escapes_html_entities():
    assert tg._esc("<b>&amp</b>") == "&lt;b&gt;&amp;amp&lt;/b&gt;"


def test_successful_post_returns_payload(monkeypatch):
    _install(monkeypatch, [_Response(200, {"ok": True, "result": {}})])
    assert asyncio.run(tg._post("sendMessage", {}))["ok"] is True


def test_throttled_post_retries_after_delay(monkeypatch):
    sleeps = []
    calls = _install(
        monkeypatch,
        [_Response(429, {"parameters": {"retry_after": 3}}), _Response(200, {"ok": True})],
        sleeps,
    )
    assert asyncio.run(tg._post("sendMessage", {}))["ok"] is True
    assert len(calls) == 2
    assert sleeps == [3.0]


def test_retry_delay_is_capped(monkeypatch):
    sleeps = []
    _install(monkeypatch, [_Response(429, {"parameters": {"retry_after": 9999}}), _Response(200, {"ok": True})], sleeps)
    asyncio.run(tg._post("sendMessage", {}))
    assert sleeps == [tg.MAX_RETRY_AFTER]


def test_persistent_throttle_reports_transient_failure(monkeypatch):
    _install(monkeypatch, [_Response(429, {}), _Response(429, {})])
    assert asyncio.run(tg._post("sendMessage", {})) is None


def test_client_error_is_permanent(monkeypatch):
    _install(monkeypatch, [_Response(400, {}, "bad request")])
    assert asyncio.run(tg._post("sendMessage", {})) is tg.PERMANENT_FAILURE


def test_server_error_is_transient(monkeypatch):
    _install(monkeypatch, [_Response(502, {}, "bad gateway")])
    assert asyncio.run(tg._post("sendMessage", {})) is None


def test_network_error_is_transient(monkeypatch):
    async def boom(self, url, json=None):
        raise httpx.ConnectError("no route")

    monkeypatch.setattr(httpx.AsyncClient, "post", boom)
    monkeypatch.setattr(tg, "BOT_TOKEN", "token")
    assert asyncio.run(tg._post("sendMessage", {})) is None


def test_push_event_reports_failure_without_credentials(monkeypatch):
    monkeypatch.setattr(tg, "BOT_TOKEN", "")
    monkeypatch.setattr(tg, "ALLOWED_CHAT_IDS", set())
    delivered = asyncio.run(tg.push_event({"kind": "rss", "target": "x", "requires_ack": 0}, {"id": 1, "title": "t"}))
    assert delivered is False


def test_push_event_confirms_delivery(monkeypatch):
    _install(monkeypatch, [_Response(200, {"ok": True})])
    monkeypatch.setattr(tg, "ALLOWED_CHAT_IDS", {42})
    delivered = asyncio.run(
        tg.push_event({"kind": "rss", "target": "x", "requires_ack": 0}, {"id": 1, "title": "t", "ai_verdict": "GO"})
    )
    assert delivered is True


def test_push_event_reports_transient_failure(monkeypatch):
    _install(monkeypatch, [_Response(502, {}), _Response(502, {})])
    monkeypatch.setattr(tg, "ALLOWED_CHAT_IDS", {42, 43})
    delivered = asyncio.run(
        tg.push_event({"kind": "rss", "target": "x", "requires_ack": 0}, {"id": 1, "title": "t", "ai_verdict": "GO"})
    )
    assert delivered is False


def test_status_command_renders_funnel(db, make_watcher, make_event):
    wid = make_watcher()
    make_event(wid, verdict="GO")
    reply = asyncio.run(tg._dispatch(db, 1, "/status"))
    assert "watch status" in reply
    assert "GO 1" in reply


def test_spec_command_requeues_lint(db, make_watcher):
    wid = make_watcher()
    c = db()
    c.execute("UPDATE watchers SET spec_lint = '{}', spec_lint_at = 'now' WHERE id = ?", (wid,))
    c.close()
    asyncio.run(tg._dispatch(db, 1, f"/spec {wid} a tighter spec"))
    c = db()
    row = c.execute("SELECT ai_spec, spec_lint, spec_lint_at FROM watchers WHERE id = ?", (wid,)).fetchone()
    c.close()
    assert row["ai_spec"] == "a tighter spec"
    assert row["spec_lint"] is None and row["spec_lint_at"] is None
