import pytest

import match
import sources


def test_target_is_normalised_to_a_lowercase_needle():
    assert sources.validate_target("anticheat_game", "  BattleField ") == "battlefield"


@pytest.mark.parametrize("bad", ["", "   ", "x" * 81])
def test_malformed_targets_are_rejected(bad):
    with pytest.raises(ValueError):
        sources.validate_target("anticheat_game", bad)


def test_cursor_round_trips():
    states = {"battlefield-6": "Denied", "battlefield-4": "Supported"}
    cursor = sources._anticheat_join_cursor('W/"abc"', states)
    etag, back = sources._anticheat_split_cursor(cursor)
    assert etag == 'W/"abc"'
    assert back == states


def test_cursor_of_none_is_an_empty_baseline():
    etag, states = sources._anticheat_split_cursor(None)
    assert etag == "" and states == {}


def test_headline_distinguishes_a_new_listing_from_a_change():
    assert sources.anticheat_headline("Battlefield 6", "Denied", None) == (
        "Battlefield 6 is listed as Denied on Linux"
    )
    assert sources.anticheat_headline("Battlefield 6", "Supported", "Denied") == (
        "Battlefield 6 is now Supported on Linux (was Denied)"
    )


PLAYABLE_RULE = '"now Supported" OR "now Running"'


def test_the_playable_rule_fires_on_becoming_playable():
    assert match.matches(PLAYABLE_RULE,
                         sources.anticheat_headline("Battlefield 6", "Supported", "Denied"))
    assert match.matches(PLAYABLE_RULE,
                         sources.anticheat_headline("Battlefield 1", "Running", "Denied"))


def test_the_playable_rule_stays_quiet_on_a_regression():
    assert not match.matches(PLAYABLE_RULE,
                             sources.anticheat_headline("Battlefield 4", "Broken", "Supported"))
    assert not match.matches(PLAYABLE_RULE,
                             sources.anticheat_headline("Battlefield 4", "Denied", "Running"))


def test_the_playable_rule_stays_quiet_on_a_baseline_listing():
    assert not match.matches(PLAYABLE_RULE,
                             sources.anticheat_headline("Battlefield 4", "Supported", None))


def test_the_playable_rule_stays_quiet_while_it_remains_blocked():
    assert not match.matches(PLAYABLE_RULE,
                             sources.anticheat_headline("Battlefield 6", "Denied", "Planned"))


def test_kind_is_registered_everywhere():
    assert "anticheat_game" in sources.SOURCE_KINDS
    assert "anticheat_game" in sources.SOURCE_EMITS
