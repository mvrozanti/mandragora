import asyncio

import pytest

import judge


def test_parses_plain_verdict_json():
    parsed = judge._parse_verdict_json(
        '{"verdict":"GO","reason":"matched","claim":"x ships y","subject":"Electrum Wallet","incident":"vulnerability"}'
    )
    assert parsed["verdict"] == "GO"
    assert parsed["reason"] == "matched"
    assert parsed["subject"] == "electrum wallet"
    assert parsed["incident"] == "vulnerability"


def test_unknown_incident_falls_back_to_other():
    parsed = judge._parse_verdict_json(
        '{"verdict":"GO","reason":"r","claim":"c","subject":"s","incident":"apocalypse"}'
    )
    assert parsed["incident"] == "other"


@pytest.mark.parametrize(
    "left,right,expected",
    [
        ("electrum bitcoin wallet", "electrum bitcoin wallet", True),
        ("electrum wallet", "electrum bitcoin wallet", True),
        ("electrum bitcoin wallet", "ledger hardware wallet", False),
        ("electrum", "electrum bitcoin wallet", True),
        ("wallet", "electrum bitcoin wallet", False),
        ("btc", "btc wallet software", False),
        ("", "electrum wallet", False),
    ],
)
def test_subject_matching(left, right, expected):
    assert judge.subjects_match(left, right) is expected


def test_subject_normalization_strips_noise():
    assert judge.normalize_subject("  Electrum (Bitcoin) Wallet!! ") == "electrum bitcoin wallet"


def test_strips_think_block():
    raw = '<think>weighing it up</think>{"verdict":"NO","reason":"off topic","claim":"","subject":"","incident":"other"}'
    assert judge._parse_verdict_json(raw)["verdict"] == "NO"


def test_extracts_embedded_object():
    raw = 'here you go: {"verdict":"UNCLEAR","reason":"single report","claim":"rumor","subject":"electrum","incident":"exploit"} thanks'
    assert judge._parse_verdict_json(raw)["verdict"] == "UNCLEAR"


def test_rejects_unknown_verdict():
    with pytest.raises(RuntimeError):
        judge._parse_verdict_json('{"verdict":"MAYBE","reason":"legacy","claim":"","subject":"","incident":"other"}')


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
    first = {"verdict": "GO", "reason": "first", "claim": "c", "subject": "electrum wallet", "incident": "vulnerability"}
    second = {"verdict": "NO", "reason": "second", "claim": "", "subject": "", "incident": "other"}
    assert judge._write_verdict(db, eid, first) is True
    assert judge._write_verdict(db, eid, second) is False


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
        return {
            "verdict": "GO",
            "reason": "matched",
            "claim": "electrum server attack",
            "subject": "electrum bitcoin wallet",
            "incident": "exploit",
        }

    monkeypatch.setattr(judge, "judge_event", verdict)
    asyncio.run(judge.judge_pending(db))
    c = db()
    row = c.execute("SELECT ai_verdict, ai_claim, ai_subject, ai_incident FROM events WHERE id = ?", (eid,)).fetchone()
    c.close()
    assert row["ai_verdict"] == "GO"
    assert row["ai_subject"] == "electrum bitcoin wallet"
    assert row["ai_incident"] == "exploit"


def test_judge_takes_newest_first(db, make_watcher, make_event, monkeypatch):
    wid = make_watcher()
    make_event(wid, external_id="old")
    newest = make_event(wid, external_id="new")
    judged = []

    async def verdict(spec, event):
        judged.append(event["id"])
        return {"verdict": "NO", "reason": "no", "claim": "", "subject": "", "incident": "other"}

    monkeypatch.setattr(judge, "judge_event", verdict)
    monkeypatch.setattr(judge, "JUDGE_BATCH", 1)
    asyncio.run(judge.judge_pending(db))
    assert judged == [newest]


def test_corroboration_promotes_agreeing_sources(db, make_watcher, make_event):
    hn = make_watcher(kind="hn_search", target="electrum")
    rss = make_watcher(kind="rss", target="https://news.example/feed")
    first = make_event(hn, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="exploit")
    second = make_event(rss, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="exploit")
    stats = judge.corroborate_pending(db)
    assert stats["promoted"] == 2
    c = db()
    rows = {r["id"]: (r["ai_verdict"], r["ai_reason"]) for r in c.execute("SELECT id, ai_verdict, ai_reason FROM events")}
    c.close()
    assert rows[first][0] == "GO" and rows[second][0] == "GO"
    assert "corroborated by event" in rows[first][1]


def test_corroboration_matches_narrower_subject(db, make_watcher, make_event):
    hn = make_watcher(kind="hn_search", target="electrum")
    rss = make_watcher(kind="rss", target="https://news.example/feed")
    make_event(hn, verdict="UNCLEAR", subject="electrum wallet", incident="phishing")
    make_event(rss, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="phishing")
    assert judge.corroborate_pending(db)["promoted"] == 2


def test_corroboration_ignores_different_subjects(db, make_watcher, make_event):
    hn = make_watcher(kind="hn_search", target="electrum")
    rss = make_watcher(kind="rss", target="https://news.example/feed")
    make_event(hn, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="vulnerability")
    make_event(rss, verdict="UNCLEAR", subject="ledger hardware wallet", incident="vulnerability")
    assert judge.corroborate_pending(db)["promoted"] == 0


def test_corroboration_ignores_different_incidents(db, make_watcher, make_event):
    hn = make_watcher(kind="hn_search", target="electrum")
    rss = make_watcher(kind="rss", target="https://news.example/feed")
    make_event(hn, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="vulnerability")
    make_event(rss, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="release")
    assert judge.corroborate_pending(db)["promoted"] == 0


def test_corroboration_requires_distinct_watchers(db, make_watcher, make_event):
    wid = make_watcher()
    make_event(wid, external_id="a", verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="exploit")
    make_event(wid, external_id="b", verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="exploit")
    assert judge.corroborate_pending(db)["promoted"] == 0


def test_corroboration_promotes_against_an_existing_go(db, make_watcher, make_event):
    hn = make_watcher(kind="hn_search", target="electrum")
    rss = make_watcher(kind="rss", target="https://news.example/feed")
    settled = make_event(hn, verdict="GO", subject="electrum bitcoin wallet", incident="exploit")
    weak = make_event(rss, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="exploit")
    assert judge.corroborate_pending(db)["promoted"] == 1
    c = db()
    verdicts = {r["id"]: r["ai_verdict"] for r in c.execute("SELECT id, ai_verdict FROM events")}
    c.close()
    assert verdicts[weak] == "GO" and verdicts[settled] == "GO"


def test_corroboration_skips_muted_watchers(db, make_watcher, make_event):
    hn = make_watcher(kind="hn_search", target="electrum", push=0)
    rss = make_watcher(kind="rss", target="https://news.example/feed", push=0)
    make_event(hn, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="exploit")
    make_event(rss, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="exploit")
    assert judge.corroborate_pending(db)["promoted"] == 0


def test_corroboration_respects_the_window(db, make_watcher, make_event):
    hn = make_watcher(kind="hn_search", target="electrum")
    rss = make_watcher(kind="rss", target="https://news.example/feed")
    make_event(hn, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="exploit")
    make_event(rss, verdict="UNCLEAR", subject="electrum bitcoin wallet", incident="exploit",
               received_at="2020-01-01T00:00:00Z")
    assert judge.corroborate_pending(db)["promoted"] == 0


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
