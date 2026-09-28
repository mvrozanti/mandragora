import asyncio
import json
from datetime import datetime, timezone

import pytest

import health
import match
import poller
import sources

NOW = datetime(2026, 9, 28, 12, 0, tzinfo=timezone.utc)


def unit(name, status="ok", scope="system", last_ok="2026-09-28T11:30:00Z", period=1800):
    return {
        "unit": name,
        "timer": name.replace(".service", ".timer"),
        "scope": scope,
        "status": status,
        "period": period,
        "last_ok": last_ok,
        "watched_since": "2026-09-28T00:00:00Z",
        "due_by": "2026-09-28T13:00:00Z",
        "failing_since": None,
        "failures": 0,
    }


def report(*units, host="mandragora", generated="2026-09-28T11:50:00Z"):
    return {"schema": 1, "host": host, "generated": generated, "units": list(units)}


def publish(tmp_path, monkeypatch, *reports):
    monkeypatch.setattr(health, "HEALTH_DIR", tmp_path)
    for r in reports:
        (tmp_path / f"health-{r['host']}.json").write_text(json.dumps(r))


def test_healthy_failing_and_inactive_units_are_quiet():
    r = report(unit("a.service"), unit("b.service", "failing"), unit("c.service", "inactive"))
    assert health.events({"mandragora": r}, NOW) == []


def test_a_stale_unit_pages_once_per_episode():
    stale = unit("audit-watch.service", "stale", last_ok="2026-09-27T01:00:00Z")
    first = health.events({"mandragora": report(stale)}, NOW)
    again = health.events({"mandragora": report(stale)}, NOW)
    assert len(first) == 1 and first == again
    ev = first[0]
    assert ev["title"].startswith("health:stale health:mandragora audit-watch.service")
    assert "runs every 30min" in ev["title"]
    newer = dict(stale, last_ok="2026-09-28T02:00:00Z")
    assert health.events({"mandragora": report(newer)}, NOW)[0]["external_id"] != ev["external_id"]


def test_a_never_succeeded_unit_names_when_watching_began():
    stale = unit("mbsync.service", "stale", scope="user", last_ok=None)
    ev = health.events({"mandragora": report(stale)}, NOW)[0]
    assert "since watching began" in ev["title"]
    assert "systemctl --user status" in ev["summary"]


def test_a_silent_host_pages_daily_and_hides_its_stale_units():
    old = report(unit("x.service", "stale"), generated="2026-09-28T08:00:00Z")
    evs = health.events({"mandragora": old}, NOW)
    assert [e["external_id"] for e in evs] == ["silent|mandragora|2026-09-28"]
    assert "last report 4h ago" in evs[0]["title"]


def test_an_unreadable_report_is_silence_not_an_exception(tmp_path, monkeypatch):
    monkeypatch.setattr(health, "HEALTH_DIR", tmp_path)
    (tmp_path / "health-mandragora.json").write_text("{not json")
    evs = health.events(health.load("*"), NOW)
    assert evs[0]["title"].startswith("health:silent") and "unreadable" in evs[0]["title"]


def test_missing_directory_is_an_error_not_silence(tmp_path, monkeypatch):
    monkeypatch.setattr(health, "HEALTH_DIR", tmp_path / "absent")
    with pytest.raises(RuntimeError, match="ever published"):
        asyncio.run(sources.fetch("unit_health", "*", None))


def test_a_vanished_host_is_an_error_not_silence(tmp_path, monkeypatch):
    publish(tmp_path, monkeypatch, report(unit("a.service")))
    with pytest.raises(RuntimeError, match="no longer publishes"):
        asyncio.run(sources.fetch("unit_health", "mandragora-wsl", None))


def test_validate():
    assert sources.validate_target("unit_health", "*") == "*"
    assert sources.validate_target("unit_health", "Mandragora") == "mandragora"
    with pytest.raises(ValueError):
        sources.validate_target("unit_health", "not a host")


def test_default_rule_matches_what_it_should():
    stale = health.stale_event("mandragora", unit("a.service", "stale"))
    silent = health.silent_event("mandragora", "last report 3h ago", "2026-09-28")
    for ev in (stale, silent):
        assert match.matches(health.DEFAULT_RULE, ev["title"], ev["summary"])


def test_the_watcher_pages_through_the_real_poller(db, make_watcher, captured_sends, monkeypatch, tmp_path):
    make_watcher(kind="unit_health", target="*", ai_spec=None, match_rule=health.DEFAULT_RULE)
    fresh = report(unit("a.service"), generated=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    publish(tmp_path, monkeypatch, fresh)
    asyncio.run(poller.poll_once(db))
    assert captured_sends == []
    fresh["units"].append(unit("b.service", "stale", last_ok="2026-09-01T00:00:00Z"))
    publish(tmp_path, monkeypatch, fresh)
    asyncio.run(poller.poll_once(db))
    asyncio.run(poller.poll_once(db))
    assert len(captured_sends) == 1


def test_bootstrap_registers_one_attached_watcher(db):
    import main

    main.bootstrap_health_watch()
    main.bootstrap_health_watch()
    c = db()
    rows = c.execute("SELECT * FROM watchers WHERE kind = 'unit_health'").fetchall()
    c.close()
    assert len(rows) == 1
    row = rows[0]
    assert row["target"] == "*" and row["ai_spec"] is None and row["push"] == 1
    assert row["watch_id"] is not None and row["match_rule"] == health.DEFAULT_RULE


def test_kind_is_registered_everywhere():
    assert "unit_health" in sources.SOURCE_KINDS
    assert "unit_health" in sources.SOURCE_EMITS
