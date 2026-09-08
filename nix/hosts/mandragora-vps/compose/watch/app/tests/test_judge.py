import asyncio

import pytest

import judge


def test_parses_plain_verdict_json():
    verdict, reason, claim = judge._parse_verdict_json('{"verdict":"GO","reason":"matched","claim":"x ships y"}')
    assert (verdict, reason, claim) == ("GO", "matched", "x ships y")


def test_strips_think_block():
    raw = '<think>weighing it up</think>{"verdict":"NO","reason":"off topic","claim":""}'
    assert judge._parse_verdict_json(raw)[0] == "NO"


def test_extracts_embedded_object():
    raw = 'here you go: {"verdict":"UNCLEAR","reason":"single report","claim":"rumor"} thanks'
    assert judge._parse_verdict_json(raw)[0] == "UNCLEAR"


def test_rejects_unknown_verdict():
    with pytest.raises(RuntimeError):
        judge._parse_verdict_json('{"verdict":"MAYBE","reason":"legacy","claim":""}')


def test_rejects_missing_json():
    with pytest.raises(RuntimeError):
        judge._parse_verdict_json("no json here")


def test_strip_html_skips_script_and_style():
    html = "<html><head><style>p{color:red}</style></head><body><script>evil()</script><p>real  text</p></body></html>"
    assert judge._strip_html(html) == "real text"


def test_claim_release_makes_event_available_again(db, make_watcher, make_event):
    wid = make_watcher()
    eid = make_event(wid)
    assert judge._claim_event(db, eid) is True
    assert judge._claim_event(db, eid) is False
    judge._release_claim(db, eid)
    assert judge._claim_event(db, eid) is True


def test_write_verdict_is_single_writer(db, make_watcher, make_event):
    wid = make_watcher()
    eid = make_event(wid)
    assert judge._write_verdict(db, eid, "GO", "first", "claim") is True
    assert judge._write_verdict(db, eid, "NO", "second", "") is False


def test_judge_failure_releases_claim(db, make_watcher, make_event, monkeypatch):
    wid = make_watcher()
    eid = make_event(wid)

    async def boom(spec, event):
        raise RuntimeError("ollama down")

    monkeypatch.setattr(judge, "judge_event", boom)
    stats = asyncio.run(judge.judge_pending(db))
    assert stats["errors"] == 1
    c = db()
    row = c.execute("SELECT ai_claimed_at FROM events WHERE id = ?", (eid,)).fetchone()
    c.close()
    assert row["ai_claimed_at"] is None


def test_judge_writes_claim(db, make_watcher, make_event, monkeypatch):
    wid = make_watcher()
    eid = make_event(wid)

    async def verdict(spec, event):
        return "GO", "matched", "electrum server attack"

    monkeypatch.setattr(judge, "judge_event", verdict)
    asyncio.run(judge.judge_pending(db))
    c = db()
    row = c.execute("SELECT ai_verdict, ai_claim FROM events WHERE id = ?", (eid,)).fetchone()
    c.close()
    assert (row["ai_verdict"], row["ai_claim"]) == ("GO", "electrum server attack")


def test_judge_takes_newest_first(db, make_watcher, make_event, monkeypatch):
    wid = make_watcher()
    make_event(wid, external_id="old")
    newest = make_event(wid, external_id="new")
    judged = []

    async def verdict(spec, event):
        judged.append(event["id"])
        return "NO", "no", ""

    monkeypatch.setattr(judge, "judge_event", verdict)
    monkeypatch.setattr(judge, "JUDGE_BATCH", 1)
    asyncio.run(judge.judge_pending(db))
    assert judged == [newest]


def test_corroboration_promotes_agreeing_sources(db, make_watcher, make_event, monkeypatch):
    hn = make_watcher(kind="hn_search", target="electrum")
    rss = make_watcher(kind="rss", target="https://news.example/feed")
    first = make_event(hn, verdict="UNCLEAR", claim="attackers exploit electrum servers")
    second = make_event(rss, verdict="UNCLEAR", claim="electrum server attack steals funds")

    async def agree(a, b):
        return True, "same incident"

    monkeypatch.setattr(judge, "same_claim", agree)
    stats = asyncio.run(judge.corroborate_pending(db))
    assert stats["promoted"] == 2
    c = db()
    verdicts = {r["id"]: r["ai_verdict"] for r in c.execute("SELECT id, ai_verdict FROM events")}
    c.close()
    assert verdicts == {first: "GO", second: "GO"}


def test_corroboration_ignores_disagreeing_claims(db, make_watcher, make_event, monkeypatch):
    hn = make_watcher(kind="hn_search", target="electrum")
    rss = make_watcher(kind="rss", target="https://news.example/feed")
    make_event(hn, verdict="UNCLEAR", claim="electrum server attack")
    make_event(rss, verdict="UNCLEAR", claim="ledger firmware bug")

    async def disagree(a, b):
        return False, "different products"

    monkeypatch.setattr(judge, "same_claim", disagree)
    stats = asyncio.run(judge.corroborate_pending(db))
    assert stats["promoted"] == 0


def test_corroboration_requires_distinct_watchers(db, make_watcher, make_event, monkeypatch):
    wid = make_watcher()
    make_event(wid, external_id="a", verdict="UNCLEAR", claim="electrum server attack")
    make_event(wid, external_id="b", verdict="UNCLEAR", claim="electrum server attack")

    async def agree(a, b):
        return True, "same"

    monkeypatch.setattr(judge, "same_claim", agree)
    stats = asyncio.run(judge.corroborate_pending(db))
    assert stats["promoted"] == 0


def test_corroboration_skips_muted_watchers(db, make_watcher, make_event, monkeypatch):
    hn = make_watcher(kind="hn_search", target="electrum", push=0)
    rss = make_watcher(kind="rss", target="https://news.example/feed", push=0)
    make_event(hn, verdict="UNCLEAR", claim="electrum server attack")
    make_event(rss, verdict="UNCLEAR", claim="electrum server attack")

    async def agree(a, b):
        return True, "same"

    monkeypatch.setattr(judge, "same_claim", agree)
    assert asyncio.run(judge.corroborate_pending(db))["promoted"] == 0


def test_spec_lint_is_recorded(db, make_watcher, monkeypatch):
    wid = make_watcher()

    async def lint(kind, target, spec):
        return {"decidable": False, "problems": ["titles only"], "suggestion": "narrow it"}

    monkeypatch.setattr(judge, "lint_spec", lint)
    stats = asyncio.run(judge.lint_pending_specs(db))
    assert stats == {"linted": 1, "undecidable": 1, "errors": 0}
    c = db()
    row = c.execute("SELECT spec_lint, spec_lint_at FROM watchers WHERE id = ?", (wid,)).fetchone()
    c.close()
    assert "titles only" in row["spec_lint"]
    assert row["spec_lint_at"] is not None


def test_spec_lint_runs_once_per_spec(db, make_watcher, monkeypatch):
    make_watcher()
    calls = []

    async def lint(kind, target, spec):
        calls.append(spec)
        return {"decidable": True, "problems": [], "suggestion": ""}

    monkeypatch.setattr(judge, "lint_spec", lint)
    asyncio.run(judge.lint_pending_specs(db))
    asyncio.run(judge.lint_pending_specs(db))
    assert len(calls) == 1
