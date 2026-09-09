import pytest

import sources


def _season(number, premiere=None, order=None):
    return {"number": number, "premiereDate": premiere, "episodeOrder": order}


TODAY = "2026-09-09"


def test_absent_season_has_its_own_state():
    assert sources.tvmaze_state(None, TODAY) == "absent"


def test_listed_without_a_date_is_not_a_premiere():
    assert sources.tvmaze_state(_season(3), TODAY) == "listed"


def test_episode_order_is_part_of_the_state():
    assert sources.tvmaze_state(_season(3, order=10), TODAY) == "listed:eps=10"


def test_future_date_is_dated_and_past_date_is_aired():
    assert sources.tvmaze_state(_season(3, premiere="2027-01-15"), TODAY) == "dated:2027-01-15"
    assert sources.tvmaze_state(_season(3, premiere="2025-01-17"), TODAY) == "aired:2025-01-17"


def test_premiere_today_counts_as_aired():
    assert sources.tvmaze_state(_season(3, premiere=TODAY), TODAY) == f"aired:{TODAY}"


@pytest.mark.parametrize(
    "state,expected",
    [
        ("absent", "Severance season 3 is not listed on TVmaze"),
        ("listed", "Severance season 3 listed — no premiere date yet"),
        ("listed:eps=10", "Severance season 3 ordered — 10 episodes, no premiere date yet"),
        ("dated:2027-01-15", "Severance season 3 premiere dated 2027-01-15"),
        ("aired:2027-01-15", "Severance season 3 premiered 2027-01-15"),
    ],
)
def test_headlines_say_what_changed(state, expected):
    assert sources.tvmaze_headline("Severance", 3, state) == expected


def test_target_accepts_a_numeric_show_id():
    assert sources.validate_target("tvmaze_season", "44933:3") == "44933:3"


@pytest.mark.parametrize("bad", ["severance", "severance:", ":3", "severance:0", "44933:x"])
def test_malformed_targets_are_rejected(bad):
    with pytest.raises(ValueError):
        sources.validate_target("tvmaze_season", bad)


def test_target_parses_back_to_show_and_season():
    assert sources._parse_tvmaze_target("44933:3") == (44933, 3)


def test_kind_is_registered_everywhere():
    import judge

    assert "tvmaze_season" in sources.SOURCE_KINDS
    assert "tvmaze_season" in judge.SOURCE_EMITS
