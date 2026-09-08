import asyncio

import pytest

import judge


PLURIBUS_SPEC = (
    "GO only if the link content explicitly confirms a concrete release of Pluribus Season 2 "
    "on Apple TV+: either (a) an official Apple TV+ announcement of a specific premiere date "
    "for season 2, or (b) the first season-2 episode is actually streaming now. NO if it is "
    "renewal news, casting news, rumors, or any post that does not state a release date."
)


def lint(kind, target, spec, response):
    async def fake_generate(system, prompt, schema, num_predict=512):
        fake_generate.system = system
        fake_generate.prompt = prompt
        return response

    original = judge._generate
    judge._generate = fake_generate
    try:
        return asyncio.run(judge.lint_spec(kind, target, spec)), fake_generate
    finally:
        judge._generate = original


@pytest.mark.parametrize("kind", ["reddit_search", "hn_search", "rss", "reddit_sub"])
def test_link_bearing_sources_advertise_the_fetched_page(kind):
    assert "the page" in judge.SOURCE_EMITS[kind]


@pytest.mark.parametrize("kind", ["reddit_search", "hn_search", "rss"])
def test_emits_never_claims_the_body_is_missing(kind):
    emits = judge.SOURCE_EMITS[kind].lower()
    assert "without the linked article body" not in emits
    assert "reachable only by fetching" not in emits


def test_prompt_forbids_the_body_is_unavailable_verdict():
    prompt = judge.SPEC_LINT_PROMPT.lower()
    assert "always fetches and reads the page behind an item's link" in prompt
    assert "never call a spec undecidable because the answer lives in the article body" in prompt
    assert "rare is not undecidable" in prompt


def test_prompt_states_material_the_judge_holds():
    _, gen = lint("reddit_search", "pluribus season 2", PLURIBUS_SPEC,
                  '{"decidable":true,"problems":[],"suggestion":""}')
    assert "MATERIAL THE JUDGE WILL HOLD" in gen.prompt
    assert "the full text of the page the post links to" in gen.prompt


def test_verbatim_echo_of_the_spec_is_dropped():
    echo = PLURIBUS_SPEC[:300]
    out, _ = lint("reddit_search", "pluribus season 2", PLURIBUS_SPEC,
                  '{"decidable":false,"problems":["p"],"suggestion":%s}' % judge.json.dumps(echo))
    assert out["suggestion"] == ""


def test_genuine_rewrite_survives():
    rewrite = "GO only when the linked page names a premiere date, or says episode 1 is streaming."
    out, _ = lint("reddit_search", "pluribus season 2", PLURIBUS_SPEC,
                  '{"decidable":false,"problems":["p"],"suggestion":%s}' % judge.json.dumps(rewrite))
    assert out["suggestion"] == rewrite


def test_decidable_spec_carries_no_problems_or_suggestion():
    out, _ = lint("hn_search", "claude code browser", "GO only if Anthropic ships a browser extension.",
                  '{"decidable":true,"problems":["stray"],"suggestion":"stray"}')
    assert out == {"version": judge.SPEC_LINT_VERSION, "decidable": True, "problems": [], "suggestion": ""}


@pytest.mark.parametrize(
    "suggestion,spec,expected",
    [
        ("", "anything", True),
        (PLURIBUS_SPEC, PLURIBUS_SPEC, True),
        (PLURIBUS_SPEC[:300], PLURIBUS_SPEC, True),
        (PLURIBUS_SPEC.upper(), PLURIBUS_SPEC, True),
        ("GO when the linked page names a date.", PLURIBUS_SPEC, False),
    ],
)
def test_echoes_spec(suggestion, spec, expected):
    assert judge.echoes_spec(suggestion, spec) is expected


def test_unknown_kind_still_promises_the_linked_page():
    _, gen = lint("brand_new_kind", "x", "GO if x.",
                  '{"decidable":true,"problems":[],"suggestion":""}')
    assert "the full text of the page the item links to" in gen.prompt


def test_lint_result_carries_its_version():
    out, _ = lint("hn_search", "x", "GO if x ships.",
                  '{"decidable":true,"problems":[],"suggestion":""}')
    assert out["version"] == judge.SPEC_LINT_VERSION


@pytest.mark.parametrize(
    "at,stored,expected",
    [
        (None, None, True),
        ("now", None, True),
        ("now", "not json", True),
        ("now", '{"decidable":false}', True),
        ("now", judge.json.dumps({"version": judge.SPEC_LINT_VERSION - 1, "decidable": False}), True),
        ("now", judge.json.dumps({"version": judge.SPEC_LINT_VERSION, "decidable": False}), False),
    ],
)
def test_lint_is_stale(at, stored, expected):
    assert judge.lint_is_stale(at, stored) is expected


def test_prompt_change_relints_every_watcher(db, make_watcher, monkeypatch):
    wid = make_watcher()
    c = db()
    c.execute(
        "UPDATE watchers SET spec_lint = ?, spec_lint_at = 'then' WHERE id = ?",
        (judge.json.dumps({"decidable": False, "problems": ["stale"], "suggestion": ""}), wid),
    )
    c.close()

    async def fresh(kind, target, spec):
        return {"version": judge.SPEC_LINT_VERSION, "decidable": True, "problems": [], "suggestion": ""}

    monkeypatch.setattr(judge, "lint_spec", fresh)
    assert asyncio.run(judge.lint_pending_specs(db))["linted"] == 1
    c = db()
    row = c.execute("SELECT spec_lint FROM watchers WHERE id = ?", (wid,)).fetchone()
    c.close()
    assert judge.json.loads(row["spec_lint"])["decidable"] is True


def test_current_version_lint_is_left_alone(db, make_watcher, monkeypatch):
    wid = make_watcher()
    c = db()
    c.execute(
        "UPDATE watchers SET spec_lint = ?, spec_lint_at = 'then' WHERE id = ?",
        (judge.json.dumps({"version": judge.SPEC_LINT_VERSION, "decidable": True, "problems": [], "suggestion": ""}), wid),
    )
    c.close()
    calls = []

    async def counted(kind, target, spec):
        calls.append(spec)
        return {"version": judge.SPEC_LINT_VERSION, "decidable": True, "problems": [], "suggestion": ""}

    monkeypatch.setattr(judge, "lint_spec", counted)
    asyncio.run(judge.lint_pending_specs(db))
    assert calls == []
