import asyncio

import httpx
import pytest

import sources


SEARCH_FEED = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>t5_n0cya</id>
    <link href="https://www.reddit.com/r/SmilingFriends/" />
    <updated>2018-08-10T08:00:39+00:00</updated>
    <title>Smiling Friends Inc.</title>
    <content type="html">&lt;div&gt; a subreddit &lt;/div&gt;</content>
  </entry>
  <entry>
    <id>t3_aaa</id>
    <link href="https://www.reddit.com/r/television/comments/aaa/pluribus_s2/" />
    <updated>2026-09-08T21:19:37+00:00</updated>
    <title>Pluribus season 2 premiere date announced</title>
    <content type="html">&lt;table&gt;&lt;tr&gt;&lt;td&gt;&lt;a href=&quot;https://external-preview.redd.it/x.jpeg&quot;&gt;&lt;img src=&quot;https://external-preview.redd.it/x.jpeg&quot; /&gt;&lt;/a&gt;&lt;/td&gt;&lt;td&gt;submitted by &lt;a href=&quot;https://www.reddit.com/user/someone&quot;&gt;/u/someone&lt;/a&gt; to &lt;a href=&quot;https://www.reddit.com/r/television/&quot;&gt;r/television&lt;/a&gt;&lt;br/&gt;&lt;span&gt;&lt;a href=&quot;https://press.apple.com/pluribus-s2&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt;&lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;</content>
  </entry>
  <entry>
    <id>t3_bbb</id>
    <link href="https://www.reddit.com/r/television/comments/bbb/selfpost/" />
    <updated>2026-09-08T21:20:00+00:00</updated>
    <title>My theory about the finale</title>
    <content type="html">&lt;div&gt;Here is the whole body of my self post, which the judge needs.&lt;/div&gt; &lt;div&gt;&lt;a href=&quot;https://www.reddit.com/r/television/comments/bbb/selfpost/&quot;&gt;[link]&lt;/a&gt;&lt;/div&gt;</content>
  </entry>
</feed>
"""


def parse(cursor=None):
    return sources._parse_reddit_feed(SEARCH_FEED, cursor)


def test_subreddit_results_are_dropped():
    events, _ = parse()
    assert [e["external_id"] for e in events] == ["t3_bbb", "t3_aaa"]


def test_link_post_points_at_the_outbound_article():
    events, _ = parse()
    post = next(e for e in events if e["external_id"] == "t3_aaa")
    assert post["link"] == "https://press.apple.com/pluribus-s2"
    assert post["raw"]["permalink"] == "https://www.reddit.com/r/television/comments/aaa/pluribus_s2/"


def test_self_post_falls_back_to_its_permalink():
    events, _ = parse()
    post = next(e for e in events if e["external_id"] == "t3_bbb")
    assert post["link"] == "https://www.reddit.com/r/television/comments/bbb/selfpost/"


def test_self_post_body_survives_as_summary():
    events, _ = parse()
    post = next(e for e in events if e["external_id"] == "t3_bbb")
    assert "the whole body of my self post" in post["summary"]


def test_summary_is_not_truncated_to_a_headline():
    assert sources.REDDIT_SUMMARY_MAX >= 1000


def test_titles_are_prefixed_by_item_kind():
    events, _ = parse()
    assert all(e["title"].startswith("post: ") for e in events)


def test_cursor_filters_already_seen_entries():
    _, cursor = parse()
    events, again = parse(cursor)
    assert events == [] and again == cursor


def test_reddit_uses_the_atom_endpoints(monkeypatch):
    seen = []

    class _Feed:
        status_code = 200
        text = SEARCH_FEED

        def raise_for_status(self):
            return None

    async def get(self, url, params=None):
        seen.append((url, params))
        return _Feed()

    monkeypatch.setattr(httpx.AsyncClient, "get", get)
    asyncio.run(sources._fetch_reddit_search("pluribus season 2", None))
    asyncio.run(sources._fetch_reddit_sub("television", None))
    asyncio.run(sources._fetch_reddit_user("spez", None))
    urls = [u for u, _ in seen]
    assert urls == [
        "https://www.reddit.com/search.rss",
        "https://www.reddit.com/r/television/new.rss",
        "https://www.reddit.com/user/spez.rss",
    ]
    assert not any(u.endswith(".json") for u in urls)
    assert seen[0][1]["q"] == "pluribus season 2"


def test_reddit_requests_are_paced(monkeypatch):
    monkeypatch.setattr(sources, "REDDIT_MIN_INTERVAL", 5.0)
    sources._reddit_gate["lock"] = None
    sources._reddit_gate["last"] = 0.0
    slept = []

    async def fake_sleep(seconds):
        slept.append(seconds)

    monkeypatch.setattr(sources.asyncio, "sleep", fake_sleep)

    async def two_calls():
        await sources._reddit_pace()
        await sources._reddit_pace()

    asyncio.run(two_calls())
    assert len(slept) == 1 and 0 < slept[0] <= 5.0


@pytest.mark.parametrize(
    "content,permalink,expected",
    [
        ('<a href="https://example.com/a">[link]</a>', "https://www.reddit.com/p", "https://example.com/a"),
        ('<a href="https://i.redd.it/x.png">img</a>', "https://www.reddit.com/p", "https://www.reddit.com/p"),
        ('<a href="https://old.reddit.com/r/x/">r/x</a>', "https://www.reddit.com/p", "https://www.reddit.com/p"),
        ("", "https://www.reddit.com/p", "https://www.reddit.com/p"),
    ],
)
def test_outbound_link_skips_reddit_hosts(content, permalink, expected):
    assert sources.reddit_outbound_link(content, permalink) == expected


def test_malformed_reddit_feed_raises():
    with pytest.raises(RuntimeError, match="reddit feed parse error"):
        sources._parse_reddit_feed("<feed><entry>", None)
