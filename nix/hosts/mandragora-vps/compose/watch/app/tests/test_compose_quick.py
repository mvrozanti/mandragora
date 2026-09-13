import asyncio
import json

import pytest

import compose
import llm


def _model(monkeypatch, payload):
    async def fake(system, prompt):
        return (payload if isinstance(payload, str) else json.dumps(payload)), "stub"

    monkeypatch.setattr(llm, "complete", fake)
    monkeypatch.setattr(compose.llm, "complete", fake)


def _probe(monkeypatch, ok=True, samples=None, error="source unreachable"):
    async def fake(entry):
        if not ok:
            return {**entry, "ok": False, "error": error, "resolved_target": None, "samples": []}
        return {**entry, "ok": True, "error": None,
                "resolved_target": entry["target"], "available": len(samples or []),
                "samples": samples or []}

    monkeypatch.setattr(compose, "probe_source", fake)


def test_interpret_maps_a_sentence_to_a_template(monkeypatch):
    _model(monkeypatch, {"template": "tv", "args": ["severance", "3"], "why": "a tv season"})
    template, args, provider = asyncio.run(compose.interpret("when does severance season 3 drop"))
    assert template == "tv" and args == ["severance", "3"] and provider == "stub"


def test_interpret_rejects_a_template_that_does_not_exist(monkeypatch):
    _model(monkeypatch, {"template": "telepathy", "args": ["x"]})
    with pytest.raises(ValueError, match="unknown template"):
        asyncio.run(compose.interpret("anything"))


def test_interpret_rejects_an_empty_argument_list(monkeypatch):
    _model(monkeypatch, {"template": "tv", "args": []})
    with pytest.raises(ValueError, match="no arguments"):
        asyncio.run(compose.interpret("anything"))


def test_interpret_survives_a_model_that_wraps_json_in_prose(monkeypatch):
    _model(monkeypatch, 'Sure! Here you go:\n{"template":"repo","args":["a/b"]}\nHope that helps.')
    template, args, _ = asyncio.run(compose.interpret("watch a/b"))
    assert template == "repo" and args == ["a/b"]


def test_interpret_refuses_an_empty_sentence(monkeypatch):
    _model(monkeypatch, {"template": "tv", "args": ["x", "1"]})
    with pytest.raises(ValueError):
        asyncio.run(compose.interpret("   "))


def test_quick_create_returns_rows_ready_to_insert(monkeypatch):
    _model(monkeypatch, {"template": "tv", "args": ["severance", "3"]})
    _probe(monkeypatch, samples=[{"title": "Severance season 3 listed", "summary": "",
                                  "link": "", "occurred_at": "2026-09-01T00:00:00Z"}])
    out = asyncio.run(compose.quick_create("severance season 3"))
    assert len(out["rows"]) == 1
    assert out["rows"][0]["kind"] == "tvmaze_season"
    assert out["rows"][0]["stop_after"] == 1
    assert out["provider"] == "stub"


def test_quick_create_refuses_when_every_source_is_unreachable(monkeypatch):
    _model(monkeypatch, {"template": "advisory", "args": ["nope/nope"]})
    _probe(monkeypatch, ok=False, error="github has no repo called nope/nope")
    with pytest.raises(ValueError) as e:
        asyncio.run(compose.quick_create("watch nope/nope advisories"))
    assert "nothing usable" in str(e.value)


def test_quick_create_propagates_the_no_provider_error(monkeypatch):
    async def boom(system, prompt):
        raise llm.NoProviderAvailable("no model provider configured")

    monkeypatch.setattr(compose.llm, "complete", boom)
    with pytest.raises(llm.NoProviderAvailable):
        asyncio.run(compose.quick_create("anything at all"))


def test_estimate_counts_matches_and_extrapolates():
    samples = [
        {"title": "a jailbreak dropped", "summary": "", "occurred_at": "2026-09-01T00:00:00Z"},
        {"title": "unrelated", "summary": "", "occurred_at": "2026-09-16T00:00:00Z"},
        {"title": "another jailbreak", "summary": "", "occurred_at": "2026-09-30T00:00:00Z"},
    ]
    est = compose.estimate_volume({"samples": samples}, "jailbreak")
    assert est["sampled"] == 3 and est["matched"] == 2
    assert est["per_month"] == pytest.approx(2.0, abs=0.3)


def test_estimate_reports_a_dead_rule_plainly():
    samples = [{"title": "nothing relevant", "summary": "", "occurred_at": "2026-09-01T00:00:00Z"},
               {"title": "also nothing", "summary": "", "occurred_at": "2026-09-30T00:00:00Z"}]
    est = compose.estimate_volume({"samples": samples}, "jailbreak")
    assert est["matched"] == 0
    assert "waiting for something new" in compose.format_estimate(est)


def test_estimate_survives_an_unparseable_date():
    samples = [{"title": "a jailbreak", "summary": "", "occurred_at": "2026-09-31T00:00:00Z"},
               {"title": "another", "summary": "", "occurred_at": "not a date"}]
    est = compose.estimate_volume({"samples": samples}, "jailbreak")
    assert est["matched"] == 1 and est["per_month"] is None
    assert "1 of the last 2 items match" in compose.format_estimate(est)


def test_estimate_handles_a_source_with_no_samples():
    assert compose.estimate_volume({"samples": []}, "anything") is None
    assert compose.format_estimate(None) == ""


def test_empty_rule_matches_every_sample():
    samples = [{"title": "x", "summary": "", "occurred_at": "2026-09-01T00:00:00Z"},
               {"title": "y", "summary": "", "occurred_at": "2026-09-30T00:00:00Z"}]
    est = compose.estimate_volume({"samples": samples}, "")
    assert est["matched"] == 2
