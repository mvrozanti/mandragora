import asyncio

import pytest

import sources


def test_target_normalizes_to_star():
    assert sources.validate_target("ea_app_version", "*") == "*"
    assert sources.validate_target("ea_app_version", "anything else") == "*"


def test_kind_is_registered_everywhere():
    assert "ea_app_version" in sources.SOURCE_KINDS
    assert "ea_app_version" in sources.SOURCE_EMITS


def test_fetch_baseline_then_change(monkeypatch):
    class FakeResponse:
        status_code = 200

        def raise_for_status(self):
            pass

        def json(self):
            return {
                "recommended": {"version": "13.806.0.6400"},
                "minimum": {"version": "13.805.2.6319"},
            }

    class FakeClient:
        def __init__(self, *a, **kw):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            pass

        async def get(self, url):
            return FakeResponse()

    monkeypatch.setattr(sources.httpx, "AsyncClient", FakeClient)

    events, cursor = asyncio.run(sources._fetch_ea_app_version("*", None))
    assert events == []
    assert cursor == "13.806.0.6400"

    events, cursor = asyncio.run(sources._fetch_ea_app_version("*", "13.806.0.6400"))
    assert events == []
    assert cursor == "13.806.0.6400"

    events, cursor = asyncio.run(sources._fetch_ea_app_version("*", "13.805.11.6320"))
    assert len(events) == 1
    assert events[0]["title"] == "EA App 13.806.0.6400 released"
    assert cursor == "13.806.0.6400"
