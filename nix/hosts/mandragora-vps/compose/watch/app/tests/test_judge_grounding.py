import judge


REAL_FALSE_POSITIVES = [
    (
        "Major bitcoin wallet flaw drains 594 BTC in 25-minute sweep - CoinDesk",
        "electrum bitcoin wallet",
    ),
    (
        "Bitcoin wallet vulnerability exposes thousands of private keys - Digital Watch Observatory",
        "electrum bitcoin wallet",
    ),
    (
        "Randstorm Exploit: Bitcoin Wallets Created b/w 2011-2015 Vulnerable to Hacking - The Hacker News",
        "electrum bitcoin wallet",
    ),
]

REAL_TRUE_POSITIVES = [
    ("Electrum Bitcoin wallets under siege - Malwarebytes", "electrum bitcoin wallet"),
    ("Hackers stole $750,000 worth Bitcoin from Electrum wallets - Security Affairs", "electrum bitcoin wallet"),
    ("Electrum Bitcoin Wallets Left Exposed to Hacks for Two Years - BleepingComputer", "electrum bitcoin wallet"),
]


def _go(subject):
    return {"verdict": "GO", "reason": "headline asserts it", "claim": "a claim", "subject": subject, "incident": "vulnerability"}


def test_go_is_refused_when_the_subject_is_never_named():
    for title, subject in REAL_FALSE_POSITIVES:
        out = judge.ground_verdict(_go(subject), {"title": title, "summary": ""})
        assert out["verdict"] == "NO", title
        assert "electrum" in out["reason"]
        assert out["claim"] == ""


def test_go_survives_when_the_subject_is_named():
    for title, subject in REAL_TRUE_POSITIVES:
        out = judge.ground_verdict(_go(subject), {"title": title, "summary": ""})
        assert out["verdict"] == "GO", title


def test_subject_may_be_grounded_in_the_fetched_body():
    out = judge.ground_verdict(
        _go("electrum bitcoin wallet"),
        {"title": "Major bitcoin wallet flaw", "summary": ""},
        "the flaw affects Electrum users on desktop",
    )
    assert out["verdict"] == "GO"


def test_no_verdicts_pass_through_untouched():
    verdict = {"verdict": "NO", "reason": "off topic", "claim": "", "subject": "", "incident": "other"}
    assert judge.ground_verdict(verdict, {"title": "anything"}) == verdict


def test_unclear_is_also_gated():
    out = judge.ground_verdict(
        {**_go("electrum bitcoin wallet"), "verdict": "UNCLEAR"},
        {"title": "Major bitcoin wallet flaw", "summary": ""},
    )
    assert out["verdict"] == "NO"


def test_generic_subject_terms_do_not_gate():
    assert judge.subject_terms("the software platform") == []
    out = judge.ground_verdict(_go("the software platform"), {"title": "unrelated headline"})
    assert out["verdict"] == "GO"


def test_must_mention_refuses_even_when_the_model_names_a_generic_subject():
    verdict = {"verdict": "GO", "reason": "headline asserts a wallet flaw", "claim": "a claim",
               "subject": "bitcoin wallet", "incident": "vulnerability"}
    event = {"title": "Major bitcoin wallet flaw drains 594 BTC", "summary": "",
             "w_must_mention": "electrum"}
    out = judge.ground_verdict(verdict, event)
    assert out["verdict"] == "NO"
    assert "electrum" in out["reason"]


def test_must_mention_is_authoritative_and_not_over_strict():
    verdict = {"verdict": "GO", "reason": "r", "claim": "c", "subject": "electrum bitcoin wallet",
               "incident": "vulnerability"}
    event = {"title": "Electrum wallets under siege", "summary": "", "w_must_mention": "electrum"}
    assert judge.ground_verdict(verdict, event)["verdict"] == "GO"


def test_without_must_mention_every_subject_term_must_appear():
    verdict = {"verdict": "GO", "reason": "r", "claim": "c", "subject": "electrum bitcoin wallet",
               "incident": "vulnerability"}
    event = {"title": "Major bitcoin wallet flaw drains 594 BTC", "summary": ""}
    assert judge.ground_verdict(verdict, event)["verdict"] == "NO"


def test_must_mention_accepts_several_terms():
    assert judge.required_terms({"w_must_mention": "electrum, bitcoin core"}) == ["electrum", "bitcoin", "core"]
    assert judge.required_terms({}) == []
