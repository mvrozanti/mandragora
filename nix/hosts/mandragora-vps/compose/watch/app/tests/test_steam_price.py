import pytest

import sources


def test_target_accepts_a_bare_appid():
    assert sources.validate_target("steam_price", " 2483190 ") == "2483190"


def test_target_extracts_appid_from_a_store_url():
    assert sources.validate_target(
        "steam_price", "https://store.steampowered.com/app/2483190/Forza_Horizon_6/"
    ) == "2483190"


@pytest.mark.parametrize("bad", ["", "   ", "abc", "steam://store/2483190", "x" * 12])
def test_malformed_targets_are_rejected(bad):
    with pytest.raises(ValueError):
        sources.validate_target("steam_price", bad)


def test_money_formats_cents_with_a_symbol():
    assert sources._steam_money(6999, "USD") == "$69.99"
    assert sources._steam_money(4899, "USD") == "$48.99"
    assert sources._steam_money(34990, "BRL") == "R$349.90"


def test_money_falls_back_without_a_known_symbol():
    assert sources._steam_money(100, "PHP") == "PHP 1.00"
    assert sources._steam_money(100, "") == "1.00"


def test_cursor_round_trips():
    state = {"c": "USD", "d": "30", "f": "4899", "i": "6999"}
    cursor = sources._steam_join_cursor(state)
    assert sources._steam_split_cursor(cursor) == state


def test_cursor_of_none_is_no_baseline():
    assert sources._steam_split_cursor(None) is None


def test_state_reads_the_price_overview():
    po = {"currency": "USD", "initial": 6999, "final": 4899, "discount_percent": 30}
    assert sources._steam_state(po) == {"c": "USD", "d": "30", "f": "4899", "i": "6999"}


def test_headlines_say_what_changed():
    name = "Forza Horizon 6"
    base = {"c": "USD", "d": "0", "f": "6999", "i": "6999"}
    sale = {"c": "USD", "d": "30", "f": "4899", "i": "6999"}
    deeper = {"c": "USD", "d": "50", "f": "3499", "i": "6999"}
    assert sources.steam_price_headline(name, 0, "$69.99", None) == (
        "Forza Horizon 6 is not discounted on Steam ($69.99)"
    )
    assert sources.steam_price_headline(name, 30, "$48.99", None) == (
        "Forza Horizon 6 is 30% off on Steam — $48.99"
    )
    assert sources.steam_price_headline(name, 30, "$48.99", base) == (
        "Forza Horizon 6 is now 30% off on Steam — $48.99"
    )
    assert sources.steam_price_headline(name, 50, "$34.99", sale) == (
        "Forza Horizon 6 is now 50% off on Steam — $34.99 (was 30% off)"
    )
    assert sources.steam_price_headline(name, 0, "$69.99", sale) == (
        "Forza Horizon 6 is back to full price on Steam ($69.99)"
    )
    assert sources.steam_price_headline(name, 20, "$55.99", deeper) == (
        "Forza Horizon 6 discount dropped to 20% on Steam — $55.99"
    )
    assert sources.steam_price_headline(name, 0, "$64.99", base) == (
        "Forza Horizon 6 price changed on Steam ($64.99)"
    )


def test_kind_is_registered_everywhere():
    assert "steam_price" in sources.SOURCE_KINDS
    assert "steam_price" in sources.SOURCE_EMITS
