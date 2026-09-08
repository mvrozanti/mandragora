import pytest

import sources

RSS_FEED = """<?xml version="1.0"?>
<rss version="2.0"><channel>
  <title>news</title>
  <item>
    <guid>https://news.example/electrum-attack</guid>
    <link>https://news.example/electrum-attack</link>
    <title>Electrum servers hit by phishing campaign</title>
    <pubDate>Mon, 07 Sep 2026 12:00:00 GMT</pubDate>
    <description>&lt;p&gt;Attackers   abused server messages&lt;/p&gt;</description>
  </item>
  <item>
    <guid>https://news.example/older</guid>
    <link>https://news.example/older</link>
    <title>Older story</title>
    <pubDate>Sun, 06 Sep 2026 12:00:00 GMT</pubDate>
    <description>stale</description>
  </item>
</channel></rss>
"""

ATOM_FEED = """<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>releases</title>
  <entry>
    <id>tag:example,2026:release/4.5.9</id>
    <title>4.5.9</title>
    <link href="https://example.invalid/releases/4.5.9"/>
    <updated>2026-09-07T12:00:00Z</updated>
    <summary>security fix</summary>
  </entry>
</feed>
"""


@pytest.mark.parametrize(
    "kind,raw,expected",
    [
        ("github_user", "@octocat", "octocat"),
        ("github_repo", "spesmilo/electrum", "spesmilo/electrum"),
        ("github_release", "spesmilo/electrum/", "spesmilo/electrum"),
        ("reddit_user", "u/spez", "spez"),
        ("reddit_sub", "r/selfhosted", "selfhosted"),
        ("hn_search", "  electrum vulnerability  ", "electrum vulnerability"),
        ("reddit_search", "electrum wallet", "electrum wallet"),
        ("rss", "https://news.example/rss", "https://news.example/rss"),
    ],
)
def test_valid_targets_are_normalized(kind, raw, expected):
    assert sources.validate_target(kind, raw) == expected


@pytest.mark.parametrize(
    "kind,raw",
    [
        ("github_user", "owner/repo"),
        ("github_repo", "just-a-name"),
        ("github_release", "too/many/parts"),
        ("reddit_sub", "two words"),
        ("rss", "news.example/rss"),
        ("hn_search", ""),
        ("nonsense_kind", "x"),
    ],
)
def test_invalid_targets_are_rejected(kind, raw):
    with pytest.raises(ValueError):
        sources.validate_target(kind, raw)


def test_rss_target_length_is_bounded():
    with pytest.raises(ValueError):
        sources.validate_target("rss", "https://news.example/" + "x" * 600)


def test_every_kind_is_declared_in_the_registry():
    assert set(sources.SOURCE_KINDS) >= {
        "github_user", "github_repo", "github_release", "reddit_user", "reddit_sub",
        "youtube_channel", "twitch_stream", "hn_search", "reddit_search", "rss",
    }


def test_rss_feed_yields_events_oldest_first_with_cursor():
    events, cursor = sources._parse_feed(RSS_FEED, None)
    assert [e["title"] for e in events] == [
        "Older story",
        "Electrum servers hit by phishing campaign",
    ]
    newest = events[-1]
    assert newest["external_id"] == "https://news.example/electrum-attack"
    assert "<p>" not in newest["summary"]
    assert "abused server messages" in newest["summary"]
    assert cursor is not None


def test_rss_cursor_suppresses_seen_entries():
    _, cursor = sources._parse_feed(RSS_FEED, None)
    events, _ = sources._parse_feed(RSS_FEED, cursor)
    assert events == []


def test_atom_feed_is_parsed():
    events, cursor = sources._parse_feed(ATOM_FEED, None)
    assert events[0]["title"] == "4.5.9"
    assert events[0]["link"] == "https://example.invalid/releases/4.5.9"


def test_malformed_feed_raises():
    with pytest.raises(RuntimeError):
        sources._parse_feed("<rss><channel>", None)


def test_rss_date_parsing():
    assert sources._parse_rss_date("Mon, 07 Sep 2026 12:00:00 GMT") is not None
    assert sources._parse_rss_date("not a date") is None
