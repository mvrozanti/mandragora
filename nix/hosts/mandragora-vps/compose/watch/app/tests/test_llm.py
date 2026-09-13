import asyncio

import pytest

import llm


@pytest.fixture(autouse=True)
def no_keys(monkeypatch):
    monkeypatch.setattr(llm, "DEEPSEEK_KEY", "")
    monkeypatch.setattr(llm, "ANTHROPIC_KEY", "")


def _stub(monkeypatch, deepseek=None, anthropic=None):
    async def ds(system, prompt):
        if isinstance(deepseek, Exception):
            raise deepseek
        return deepseek

    async def an(system, prompt):
        if isinstance(anthropic, Exception):
            raise anthropic
        return anthropic

    monkeypatch.setattr(llm, "_deepseek", ds)
    monkeypatch.setattr(llm, "_anthropic", an)
    monkeypatch.setattr(llm, "PROVIDERS", (
        ("deepseek", lambda: bool(llm.DEEPSEEK_KEY), ds),
        ("anthropic", lambda: bool(llm.ANTHROPIC_KEY), an),
    ))


def test_no_key_anywhere_is_a_clear_error(monkeypatch):
    _stub(monkeypatch, deepseek="{}", anthropic="{}")
    with pytest.raises(llm.NoProviderAvailable) as e:
        asyncio.run(llm.complete("s", "p"))
    assert "no model provider configured" in str(e.value)


def test_available_reports_only_configured_providers(monkeypatch):
    assert llm.available() == []
    monkeypatch.setattr(llm, "DEEPSEEK_KEY", "k")
    assert llm.available() == ["deepseek"]
    monkeypatch.setattr(llm, "ANTHROPIC_KEY", "k")
    assert llm.available() == ["deepseek", "anthropic"]


def test_deepseek_is_tried_first(monkeypatch):
    monkeypatch.setattr(llm, "DEEPSEEK_KEY", "k")
    monkeypatch.setattr(llm, "ANTHROPIC_KEY", "k")
    _stub(monkeypatch, deepseek='{"from":"ds"}', anthropic='{"from":"an"}')
    out, who = asyncio.run(llm.complete("s", "p"))
    assert who == "deepseek" and "ds" in out


def test_anthropic_takes_over_when_deepseek_fails(monkeypatch):
    monkeypatch.setattr(llm, "DEEPSEEK_KEY", "k")
    monkeypatch.setattr(llm, "ANTHROPIC_KEY", "k")
    _stub(monkeypatch, deepseek=llm.ProviderFailed("deepseek http 500"), anthropic='{"from":"an"}')
    out, who = asyncio.run(llm.complete("s", "p"))
    assert who == "anthropic" and "an" in out


def test_anthropic_alone_is_used_when_it_is_the_only_key(monkeypatch):
    monkeypatch.setattr(llm, "ANTHROPIC_KEY", "k")
    _stub(monkeypatch, deepseek='{"from":"ds"}', anthropic='{"from":"an"}')
    out, who = asyncio.run(llm.complete("s", "p"))
    assert who == "anthropic"


def test_every_provider_failing_names_each_failure(monkeypatch):
    monkeypatch.setattr(llm, "DEEPSEEK_KEY", "k")
    monkeypatch.setattr(llm, "ANTHROPIC_KEY", "k")
    _stub(monkeypatch,
          deepseek=llm.ProviderFailed("deepseek http 500"),
          anthropic=llm.ProviderFailed("anthropic http 529"))
    with pytest.raises(llm.NoProviderAvailable) as e:
        asyncio.run(llm.complete("s", "p"))
    assert "deepseek" in str(e.value) and "anthropic" in str(e.value)


def test_an_unconfigured_provider_is_skipped_not_called(monkeypatch):
    monkeypatch.setattr(llm, "ANTHROPIC_KEY", "k")
    called = []

    async def ds(system, prompt):
        called.append("deepseek")
        return "{}"

    async def an(system, prompt):
        return '{"ok":1}'

    monkeypatch.setattr(llm, "PROVIDERS", (
        ("deepseek", lambda: bool(llm.DEEPSEEK_KEY), ds),
        ("anthropic", lambda: bool(llm.ANTHROPIC_KEY), an),
    ))
    asyncio.run(llm.complete("s", "p"))
    assert called == []
