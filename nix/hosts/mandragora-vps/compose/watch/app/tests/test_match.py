import pytest

import match


def test_bare_term_matches_case_insensitively():
    assert match.matches("electrum", "Electrum Bitcoin Wallets Left Exposed")


def test_term_respects_word_boundaries():
    assert not match.matches("electrum", "Electrostatic Cathode Ray Tube Project")
    assert not match.matches("electrum", "I put my Electron app on my landing page")


def test_possessive_and_plural_still_match():
    assert match.matches("electrum", "Electrum's servers were attacked")
    assert match.matches("wallet", "the wallet, compromised")


def test_whitespace_means_and():
    assert match.matches("electrum wallet", "Electrum wallet drained")
    assert not match.matches("electrum wallet", "Electrum servers offline")


def test_explicit_and_or_not():
    assert match.matches("electrum AND exploit", "Electrum exploit in the wild")
    assert match.matches("electrum OR monero", "Monero users targeted")
    assert not match.matches("electrum AND NOT phishing", "Electrum phishing campaign")
    assert match.matches("electrum AND NOT phishing", "Electrum RPC vulnerability")


def test_or_binds_looser_than_and():
    assert match.matches("a AND b OR c", "c alone")
    assert match.matches("a AND b OR c", "a b")
    assert not match.matches("a AND b OR c", "a alone")


def test_parentheses_override_precedence():
    assert not match.matches("a AND (b OR c)", "a alone")
    assert match.matches("a AND (b OR c)", "a and c")


def test_quoted_phrase_is_one_term():
    assert match.matches('"supply chain"', "a supply chain compromise")
    assert not match.matches('"supply chain"', "the chain of supply")


def test_quoted_phrase_tolerates_runs_of_whitespace():
    assert match.matches('"supply chain"', "a supply\n  chain compromise")


def test_lowercase_and_is_a_literal_not_an_operator():
    assert match.matches("and", "peanuts and cream")


def test_empty_rule_matches_everything():
    assert match.matches("", "anything at all")
    assert match.matches("   ", "anything at all")


def test_searches_every_text_given():
    assert match.matches("electrum", "unrelated headline", "", "body mentions Electrum here")


@pytest.mark.parametrize("bad", ["(", ")", "a AND", "AND a", "a AND (b", "NOT", '""'])
def test_malformed_expressions_are_rejected(bad):
    ok, err = match.is_valid(bad)
    assert not ok and err


@pytest.mark.parametrize("good", ["electrum", "a AND b", "a OR b", "NOT a", "(a OR b) AND c", '"a b" OR c'])
def test_well_formed_expressions_validate(good):
    ok, err = match.is_valid(good)
    assert ok and not err


def test_explain_names_the_missing_term():
    out = match.explain("electrum AND exploit", "Electrum release notes")
    assert "exploit" in out and "electrum" not in out


def test_explain_reports_a_match():
    assert match.explain("electrum", "Electrum hacked") == "matched"


def test_explain_handles_the_empty_rule():
    assert "everything" in match.explain("", "whatever")


def test_must_mention_converts_to_an_and_expression():
    assert match.from_must_mention("electrum") == "electrum"
    assert match.from_must_mention("kindle paperwhite") == "kindle AND paperwhite"
    assert match.from_must_mention("a, b") == "a AND b"
    assert match.from_must_mention(None) == ""


def test_converted_must_mention_behaves_like_the_old_gate():
    expr = match.from_must_mention("electrum")
    assert match.matches(expr, "Electrum wallets exposed")
    assert not match.matches(expr, "Revolut exposed KYC data")
