import asyncio
import json
from datetime import datetime, timedelta, timezone

import pytest

import inventory
import match
import poller
import sources

NOW = datetime(2026, 9, 27, 12, 0, tzinfo=timezone.utc)
FRESH = "2026-09-27T06:00:00Z"


def report(host, entries, generated=FRESH, **extra):
    return {"schema": 2, "host": host, "generated": generated, "entries": entries, **extra}


def entry(pname, version, *cves, images=None):
    return {"pname": pname, "version": version, "images": images or [], "cves": list(cves)}


def cve(cid, score, fixed=None, fixed_version=""):
    c = {"id": cid, "score": score, "desc": f"{cid} desc"}
    if fixed is not None:
        c["fixed"] = fixed
        c["fixed_version"] = fixed_version
    return c


BASE = {
    "mandragora": report("mandragora", [entry("openssl", "3.4.1", cve("CVE-2026-0001", 7.5))]),
    "mandragora-vps": report("mandragora-vps", [
        entry("libc6", "2.36", cve("CVE-2026-0002", 9.8, True, "2.37"), images=["seafile:12"]),
    ]),
}


def run(reports, state=None, first=False, kev=frozenset(), noise=None, exposures=None, now=NOW):
    recs = inventory.collect(reports, inventory.Noise(noise), exposures)
    return inventory.diff(state or inventory.State(), first, reports, recs, kev, now)


def baseline(reports=BASE, kev=frozenset()):
    events, state = run(reports, first=True, kev=kev)
    assert events == []
    return state


def with_entry(host, e):
    out = json.loads(json.dumps(BASE))
    out[host]["entries"].append(e)
    return out


def test_first_poll_records_a_silent_baseline():
    state = baseline()
    assert set(state.hosts) == {"mandragora", "mandragora-vps"}
    assert len(state.seen) == 2


def test_a_new_pair_emits_exactly_one_event():
    state = baseline()
    reports = with_entry("mandragora-vps", entry("curl", "8.0", cve("CVE-2026-0003", 9.1, True, "8.1")))
    events, state = run(reports, state)
    assert [e["external_id"] for e in events] == ["new|curl|CVE-2026-0003"]
    again, _ = run(reports, state)
    assert again == []


def test_a_version_bump_that_keeps_the_cve_stays_quiet():
    state = baseline()
    reports = json.loads(json.dumps(BASE))
    reports["mandragora"]["entries"][0]["version"] = "3.4.2"
    events, _ = run(reports, state)
    assert events == []


def test_a_kev_listing_escalates_a_known_pair_once():
    state = baseline()
    events, state = run(BASE, state, kev=frozenset({"CVE-2026-0001"}))
    assert [e["external_id"] for e in events] == ["kev|openssl|CVE-2026-0001"]
    assert "vuln:kev" in events[0]["title"]
    again, _ = run(BASE, state, kev=frozenset({"CVE-2026-0001"}))
    assert again == []


def test_an_unreachable_kev_catalog_does_not_forget_escalations():
    state = baseline(kev=frozenset({"CVE-2026-0001"}))
    _, after = run(BASE, state, kev=None)
    assert after.kev == state.kev


def test_noise_entries_and_noise_pairs_are_dropped():
    state = baseline()
    reports = with_entry("mandragora", entry("texlive-foo", "1.0-tex", cve("CVE-2026-0004", 9.9)))
    reports["mandragora"]["entries"].append(entry("kitty", "0.40", cve("CVE-2016-2563", 9.8)))
    noise = {"version_suffixes": ["-tex"], "pname_cve": [["kitty", "CVE-2016-2563"]]}
    events, _ = run(reports, state, noise=noise)
    assert events == []


def test_a_newly_publishing_host_is_baselined_not_paged():
    state = baseline()
    reports = dict(BASE, **{"mandragora-wsl": report("mandragora-wsl", [
        entry("zlib", "1.3", cve("CVE-2026-0005", 9.8)),
    ])})
    events, state = run(reports, state)
    assert events == []
    assert "mandragora-wsl" in state.hosts


def test_a_pair_shared_with_a_known_host_still_pages():
    state = baseline()
    reports = dict(BASE, **{"mandragora-wsl": report("mandragora-wsl", [])})
    reports = json.loads(json.dumps(reports))
    shared = entry("zlib", "1.3", cve("CVE-2026-0005", 9.8))
    reports["mandragora-wsl"]["entries"].append(shared)
    reports["mandragora"]["entries"].append(shared)
    events, _ = run(reports, state)
    assert [e["external_id"] for e in events] == ["new|zlib|CVE-2026-0005"]


def test_a_stale_report_raises_one_alert_per_day():
    state = baseline()
    old = (NOW - timedelta(days=4)).isoformat().replace("+00:00", "Z")
    reports = json.loads(json.dumps(BASE))
    reports["mandragora"]["generated"] = old
    events, state = run(reports, state)
    assert [e["external_id"] for e in events] == ["stale|mandragora|2026-09-27"]
    assert "vuln:stale" in events[0]["title"]
    again, state = run(reports, state, now=NOW + timedelta(hours=3))
    assert again == []
    tomorrow, _ = run(reports, state, now=NOW + timedelta(days=1))
    assert [e["external_id"] for e in tomorrow] == ["stale|mandragora|2026-09-28"]


def test_a_scanner_error_is_stale_even_when_recent():
    state = baseline()
    reports = json.loads(json.dumps(BASE))
    reports["mandragora-vps"]["error"] = "trivy failed on all 30 image(s)"
    events, _ = run(reports, state)
    assert len(events) == 1 and "trivy failed" in events[0]["title"]


def test_a_legacy_date_only_stamp_is_understood():
    assert inventory.parse_generated("2026-09-20") == datetime(2026, 9, 20, tzinfo=timezone.utc)


def test_a_burst_collapses_into_one_page():
    state = baseline()
    reports = json.loads(json.dumps(BASE))
    for i in range(inventory.BURST + 1):
        reports["mandragora"]["entries"].append(entry(f"pkg{i}", "1", cve(f"CVE-2026-1{i:03d}", 9.8)))
    events, _ = run(reports, state)
    paged = [e for e in events if match.matches(inventory.DEFAULT_RULE, e["title"], e["summary"])]
    assert len(events) == inventory.BURST + 2
    assert len(paged) == 1 and paged[0]["external_id"].startswith("burst|")


def test_forgotten_pairs_page_again_after_the_forget_window():
    state = baseline()
    gone = {h: report(h, []) for h in BASE}
    later = NOW + timedelta(days=inventory.FORGET_AFTER_DAYS + 2)
    _, state = run(gone, state, now=later)
    back, _ = run(BASE, state, now=later)
    assert {e["external_id"] for e in back} == {"new|openssl|CVE-2026-0001", "new|libc6|CVE-2026-0002"}


def test_a_briefly_missing_pair_does_not_page_again():
    state = baseline()
    gone = {h: report(h, []) for h in BASE}
    _, state = run(gone, state, now=NOW + timedelta(days=1))
    back, _ = run(BASE, state, now=NOW + timedelta(days=2))
    assert back == []


def test_cursor_round_trips():
    state = baseline(kev=frozenset({"CVE-2026-0001"}))
    state.stale["mandragora"] = "2026-09-27"
    back = inventory.load_cursor(inventory.dump_cursor(state))
    assert back == state


def test_a_garbled_cursor_is_an_empty_state():
    assert inventory.load_cursor("not json") == inventory.State()


def _title(reports, kev=frozenset(), exposures=None):
    state = baseline()
    events, _ = run(reports, state, kev=kev, exposures=exposures)
    assert len(events) == 1
    return events[0]


def _pages(ev):
    return match.matches(inventory.DEFAULT_RULE, ev["title"], ev["summary"])


def test_default_rule_pages_a_fixable_critical():
    ev = _title(with_entry("mandragora-vps", entry("curl", "8.0", cve("CVE-2026-0003", 9.1, True, "8.1"))))
    assert "vuln:critical" in ev["title"] and "vuln:fixable" in ev["title"]
    assert "fix: 8.1" in ev["summary"]
    assert _pages(ev)


def test_default_rule_ignores_a_critical_without_a_fix():
    ev = _title(with_entry("mandragora-vps", entry("curl", "8.0", cve("CVE-2026-0003", 9.1, False))))
    assert "vuln:nofix" in ev["title"]
    assert not _pages(ev)


def test_default_rule_ignores_a_medium():
    ev = _title(with_entry("mandragora", entry("less", "600", cve("CVE-2026-0006", 5.0))))
    assert "vuln:medium" in ev["title"]
    assert not _pages(ev)


def test_default_rule_pages_anything_on_kev():
    ev = _title(with_entry("mandragora", entry("less", "600", cve("CVE-2026-0006", 5.0))),
                kev=frozenset({"CVE-2026-0006"}))
    assert _pages(ev)


def test_default_rule_pages_an_exposed_package():
    reports = with_entry("mandragora", entry("less", "600", cve("CVE-2026-0006", 5.0)))
    exposures = {"mandragora": {"listeners": [{"port": 22, "scope": "public", "pnames": ["less"]}]}}
    ev = _title(reports, exposures=exposures)
    assert "vuln:exposed" in ev["title"] and "mandragora:public" in ev["summary"]
    assert _pages(ev)


def test_exposure_matches_vps_packages_by_image():
    reports = with_entry("mandragora-vps", entry("curl", "8.0", cve("CVE-2026-0003", 5.0, False), images=["caddy:2"]))
    exposures = {"mandragora-vps": {"listeners": [{"port": 443, "scope": "public", "image": "caddy:2"}]}}
    ev = _title(reports, exposures=exposures)
    assert "vuln:exposed" in ev["title"]


def test_host_tags_do_not_collide_on_a_shared_prefix():
    ev = _title(with_entry("mandragora-vps", entry("curl", "8.0", cve("CVE-2026-0003", 9.1, True, "8.1"))))
    assert match.matches("vuln:mandragora_vps", ev["title"])
    assert not match.matches("vuln:mandragora", ev["title"])


def test_severity_falls_back_to_the_vendor_label_when_unscored():
    assert inventory.severity_band(0, "CRITICAL") == "critical"
    assert inventory.severity_band(0, "") == "unknown"


def test_target_accepts_every_host_or_one_name(monkeypatch):
    import httpx

    class _Hosts:
        status_code = 200

        def json(self):
            return ["mandragora", "mandragora-vps"]

    monkeypatch.setattr(httpx.Client, "get", lambda self, url: _Hosts())
    assert sources.validate_target("vuln_inventory", "*") == "*"
    assert sources.validate_target("vuln_inventory", "Mandragora-VPS") == "mandragora-vps"
    with pytest.raises(ValueError):
        sources.validate_target("vuln_inventory", "not-a-host")
    with pytest.raises(ValueError):
        sources.validate_target("vuln_inventory", "bad host!")


class _Resp:
    def __init__(self, status, body=None, etag=""):
        self.status_code = status
        self._body = body
        self.headers = {"ETag": etag} if etag else {}
        self.text = json.dumps(body)

    def json(self):
        return self._body

    def raise_for_status(self):
        if self.status_code >= 400:
            import httpx

            raise httpx.HTTPStatusError("err", request=None, response=None)


def _serve(monkeypatch, files, kev=()):
    import httpx

    calls = []

    async def get(self, url, headers=None, params=None):
        calls.append(url)
        if url == inventory.KEV_URL:
            return _Resp(200, {"vulnerabilities": [{"cveID": c} for c in kev]})
        name = url.rsplit("/", 1)[-1]
        if name in files:
            return _Resp(200, files[name])
        return _Resp(404)

    monkeypatch.setattr(httpx.AsyncClient, "get", get)
    monkeypatch.setattr(inventory, "_http_cache", {})
    monkeypatch.setattr(inventory, "_kev_cache", {"at": 0.0, "ids": None})
    return calls


def _files(reports):
    files = {"hosts.json": list(reports), "noise.json": {}}
    files.update({f"report-{h}.json": r for h, r in reports.items()})
    return files


def test_fetch_end_to_end_baselines_then_reports(monkeypatch):
    _serve(monkeypatch, _files(BASE))
    events, cursor = asyncio.run(sources.fetch("vuln_inventory", "*", None))
    assert events == [] and cursor
    reports = with_entry("mandragora-vps", entry("curl", "8.0", cve("CVE-2026-0003", 9.1, True, "8.1")))
    _serve(monkeypatch, _files(reports))
    events, _ = asyncio.run(sources.fetch("vuln_inventory", "*", cursor))
    assert [e["external_id"] for e in events] == ["new|curl|CVE-2026-0003"]


def test_fetch_for_a_vanished_host_is_an_error_not_silence(monkeypatch):
    _serve(monkeypatch, _files(BASE))
    with pytest.raises(RuntimeError, match="no longer publishes"):
        asyncio.run(sources.fetch("vuln_inventory", "mandragora-wsl", None))


def test_the_watcher_pages_through_the_real_poller(db, make_watcher, captured_sends, monkeypatch):
    make_watcher(kind="vuln_inventory", target="*", ai_spec=None, match_rule=inventory.DEFAULT_RULE)
    _serve(monkeypatch, _files(BASE))
    asyncio.run(poller.poll_once(db))
    assert captured_sends == []
    reports = with_entry("mandragora-vps", entry("curl", "8.0", cve("CVE-2026-0003", 9.1, True, "8.1")))
    reports["mandragora"]["entries"].append(entry("less", "600", cve("CVE-2026-0006", 5.0)))
    _serve(monkeypatch, _files(reports))
    asyncio.run(poller.poll_once(db))
    assert len(captured_sends) == 1


def test_bootstrap_registers_one_attached_watcher(db):
    import main

    main.bootstrap_vuln_watch()
    main.bootstrap_vuln_watch()
    c = db()
    rows = c.execute("SELECT * FROM watchers WHERE kind = 'vuln_inventory'").fetchall()
    c.close()
    assert len(rows) == 1
    row = rows[0]
    assert row["target"] == "*" and row["ai_spec"] is None and row["push"] == 1
    assert row["watch_id"] is not None and row["match_rule"] == inventory.DEFAULT_RULE


def test_kind_is_registered_everywhere():
    assert "vuln_inventory" in sources.SOURCE_KINDS
    assert "vuln_inventory" in sources.SOURCE_EMITS
