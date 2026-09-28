import hashlib
import json
import os
import re
import time
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Any

import httpx

VULN_BASE = os.environ.get("WATCH_VULN_BASE", "http://vuln").rstrip("/")
VULN_SITE = os.environ.get("WATCH_VULN_SITE", "https://vuln.mvr.ac")
KEV_URL = os.environ.get(
    "WATCH_KEV_URL",
    "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json",
)
KEV_TTL = float(os.environ.get("WATCH_KEV_TTL", "86400"))
STALE_AFTER = timedelta(hours=float(os.environ.get("WATCH_VULN_STALE_HOURS", "72")))
FORGET_AFTER_DAYS = int(os.environ.get("WATCH_VULN_FORGET_DAYS", "30"))
BURST = int(os.environ.get("WATCH_VULN_BURST", "20"))
USER_AGENT = os.environ.get("WATCH_USER_AGENT", "mandragora-watch/0.1 (+https://watch.mvr.ac)")

HOST_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
DEFAULT_RULE = (
    "(vuln:kev OR vuln:stale OR (vuln:critical AND vuln:fixable) OR vuln:exposed) "
    "AND NOT vuln:bulk OR vuln:burst"
)

_http_cache: dict[str, tuple[str, Any]] = {}
_kev_cache: dict[str, Any] = {"at": 0.0, "ids": None}


@dataclass
class Record:
    pname: str
    cve: str
    hosts: set[str] = field(default_factory=set)
    versions: set[str] = field(default_factory=set)
    images: set[str] = field(default_factory=set)
    fixed_versions: set[str] = field(default_factory=set)
    score: float = 0.0
    severity: str = ""
    fixable: bool = False
    nofix: bool = False
    exposed: set[str] = field(default_factory=set)
    desc: str = ""
    generated: str = ""

    @property
    def key(self) -> str:
        return f"{self.pname}|{self.cve}"


class Noise:
    def __init__(self, spec: dict[str, Any] | None) -> None:
        spec = spec or {}
        self.pname_suffixes = tuple(spec.get("pname_suffixes") or ())
        self.version_suffixes = tuple(spec.get("version_suffixes") or ())
        self.version_contains = tuple(spec.get("version_contains") or ())
        rx = spec.get("version_regex") or ""
        self.version_re = re.compile(rx) if rx else None
        self.pname_version = {tuple(p) for p in spec.get("pname_version") or ()}
        self.pname_cve = {tuple(p) for p in spec.get("pname_cve") or ()}

    def entry(self, pname: str, version: str) -> bool:
        if any(pname.endswith(s) for s in self.pname_suffixes):
            return True
        if any(version.endswith(s) for s in self.version_suffixes):
            return True
        if any(s in version for s in self.version_contains):
            return True
        if self.version_re and self.version_re.search(version):
            return True
        return (pname, version) in self.pname_version

    def cve(self, pname: str, cve: str) -> bool:
        return (pname, cve) in self.pname_cve


def digest(key: str) -> str:
    return hashlib.sha1(key.encode()).hexdigest()[:10]


def host_tag(host: str) -> str:
    return "vuln:" + re.sub(r"[^a-z0-9]+", "_", host.lower()).strip("_")


def severity_band(score: float, vendor: str = "") -> str:
    if score >= 9.0:
        return "critical"
    if score >= 7.0:
        return "high"
    if score >= 4.0:
        return "medium"
    if score > 0:
        return "low"
    vendor = (vendor or "").lower()
    return vendor if vendor in ("critical", "high", "medium", "low") else "unknown"


def parse_generated(value: str) -> datetime | None:
    value = (value or "").strip()
    if not value:
        return None
    try:
        if len(value) == 10:
            return datetime.combine(date.fromisoformat(value), datetime.min.time(), tzinfo=timezone.utc)
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def exposure_index(exposure: dict[str, Any] | None) -> tuple[dict[str, str], dict[str, str]]:
    pnames: dict[str, str] = {}
    images: dict[str, str] = {}
    for item in (exposure or {}).get("listeners") or []:
        scope = str(item.get("scope") or "listening")
        for p in item.get("pnames") or ([item["pname"]] if item.get("pname") else []):
            pnames[str(p)] = scope
        if item.get("image"):
            images[str(item["image"])] = scope
    return pnames, images


def collect(
    reports: dict[str, dict[str, Any]],
    noise: Noise,
    exposures: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Record]:
    exposures = exposures or {}
    recs: dict[str, Record] = {}
    for host, report in reports.items():
        exp_pnames, exp_images = exposure_index(exposures.get(host))
        for e in report.get("entries") or []:
            pname = str(e.get("pname") or "")
            version = str(e.get("version") or "")
            if not pname or noise.entry(pname, version):
                continue
            images = {str(i) for i in e.get("images") or []}
            scopes = set()
            if pname in exp_pnames:
                scopes.add(f"{host}:{exp_pnames[pname]}")
            for img in images & set(exp_images):
                scopes.add(f"{host}:{exp_images[img]}")
            for c in e.get("cves") or []:
                cve = str(c.get("id") or "")
                if not cve or noise.cve(pname, cve):
                    continue
                rec = recs.setdefault(f"{pname}|{cve}", Record(pname=pname, cve=cve))
                rec.hosts.add(host)
                if version:
                    rec.versions.add(version)
                rec.images |= images
                rec.exposed |= scopes
                score = float(c.get("score") or 0)
                if score > rec.score:
                    rec.score = score
                if c.get("severity") and not rec.severity:
                    rec.severity = str(c["severity"])
                if "fixed" not in c or c.get("fixed"):
                    rec.fixable = True
                else:
                    rec.nofix = True
                if c.get("fixed_version"):
                    rec.fixed_versions.add(str(c["fixed_version"]))
                if not rec.desc:
                    rec.desc = str(c.get("desc") or "")
                gen = str(report.get("generated") or "")
                if gen > rec.generated:
                    rec.generated = gen
    return recs


def tags(rec: Record, kev: bool, bulk: bool = False) -> list[str]:
    out = [f"vuln:{severity_band(rec.score, rec.severity)}"]
    if kev:
        out.append("vuln:kev")
    out.append("vuln:fixable" if rec.fixable else "vuln:nofix")
    if rec.exposed:
        out.append("vuln:exposed")
    out.extend(host_tag(h) for h in sorted(rec.hosts))
    if bulk:
        out.append("vuln:bulk")
    return out


def _versions(rec: Record) -> str:
    vs = sorted(rec.versions)
    return ", ".join(vs[:3]) + (f" +{len(vs) - 3}" if len(vs) > 3 else "")


def record_event(rec: Record, kind: str, kev: bool, bulk: bool = False) -> dict[str, Any]:
    score = f"{rec.score:.1f}" if rec.score else rec.severity or "unscored"
    headline = f"{rec.pname} {_versions(rec)} · {rec.cve} ({score})"
    if kind == "kev":
        headline += " · now on CISA KEV, exploited in the wild"
    fix = ", ".join(sorted(rec.fixed_versions)) or ("none upstream" if not rec.fixable else "update available")
    parts = [f"fix: {fix}", f"hosts: {', '.join(sorted(rec.hosts))}"]
    if rec.exposed:
        parts.append(f"exposed: {', '.join(sorted(rec.exposed))}")
    if rec.images:
        imgs = sorted(rec.images)
        parts.append(f"images: {', '.join(imgs[:4])}" + (f" +{len(imgs) - 4}" if len(imgs) > 4 else ""))
    if rec.desc:
        parts.append(rec.desc)
    return {
        "external_id": f"{kind}|{rec.key}",
        "title": " ".join(tags(rec, kev, bulk)) + " " + headline,
        "summary": " · ".join(parts),
        "link": f"https://osv.dev/vulnerability/{rec.cve}",
        "occurred_at": rec.generated or None,
        "raw": {
            "kind": kind,
            "pname": rec.pname,
            "cve": rec.cve,
            "hosts": sorted(rec.hosts),
            "versions": sorted(rec.versions),
            "images": sorted(rec.images),
            "fixed_versions": sorted(rec.fixed_versions),
            "score": rec.score,
            "severity": severity_band(rec.score, rec.severity),
            "kev": kev,
            "exposed": sorted(rec.exposed),
        },
    }


def burst_event(items: list[tuple[Record, bool]], today: str) -> dict[str, Any]:
    ranked = sorted(items, key=lambda t: (not t[1], -t[0].score, t[0].key))
    union: list[str] = []
    for rec, kev in ranked:
        for t in tags(rec, kev):
            if t not in union:
                union.append(t)
    top = "; ".join(f"{r.pname} {r.cve} ({r.score:.1f})" for r, _ in ranked[:10])
    return {
        "external_id": f"burst|{today}|{digest('|'.join(r.key for r, _ in ranked))}",
        "title": " ".join(["vuln:burst"] + union) + f" {len(items)} new CVE-affected packages in one scan",
        "summary": f"top: {top} · full list at {VULN_SITE}",
        "link": VULN_SITE,
        "occurred_at": None,
        "raw": {"kind": "burst", "count": len(items), "keys": [r.key for r, _ in ranked][:200]},
    }


def stale_event(host: str, reason: str, today: str) -> dict[str, Any]:
    return {
        "external_id": f"stale|{host}|{today}",
        "title": f"vuln:stale {host_tag(host)} {host} scanner is not reporting: {reason}",
        "summary": f"vuln.mvr.ac is showing {host}'s last good scan; new CVEs on it go unnoticed until this clears",
        "link": VULN_SITE,
        "occurred_at": None,
        "raw": {"kind": "stale", "host": host, "reason": reason},
    }


def stale_reason(report: dict[str, Any], now: datetime) -> str:
    if report.get("error"):
        return str(report["error"])[:200]
    gen = parse_generated(str(report.get("generated") or ""))
    if gen is None:
        return "report has no generated timestamp"
    age = now - gen
    if age > STALE_AFTER:
        return f"last scan {age.days}d {age.seconds // 3600}h ago"
    return ""


@dataclass
class State:
    hosts: dict[str, str] = field(default_factory=dict)
    seen: dict[str, int] = field(default_factory=dict)
    kev: set[str] = field(default_factory=set)
    stale: dict[str, str] = field(default_factory=dict)


def load_cursor(cursor: str | None) -> State:
    if not cursor:
        return State()
    try:
        d = json.loads(cursor)
    except (TypeError, ValueError):
        return State()
    return State(
        hosts=dict(d.get("hosts") or {}),
        seen={str(k): int(v) for k, v in (d.get("seen") or {}).items()},
        kev=set(d.get("kev") or []),
        stale=dict(d.get("stale") or {}),
    )


def dump_cursor(state: State) -> str:
    return json.dumps(
        {
            "v": 1,
            "hosts": state.hosts,
            "seen": dict(sorted(state.seen.items())),
            "kev": sorted(state.kev),
            "stale": state.stale,
        },
        separators=(",", ":"),
    )


def diff(
    state: State,
    first: bool,
    reports: dict[str, dict[str, Any]],
    recs: dict[str, Record],
    kev_ids: frozenset[str] | None,
    now: datetime,
) -> tuple[list[dict[str, Any]], State]:
    today = now.date().isoformat()
    day = (now.date() - date(1970, 1, 1)).days
    fresh_hosts = {h for h in reports if h not in state.hosts}
    kev_known = kev_ids is not None
    kev_ids = kev_ids or frozenset()

    fresh: list[tuple[Record, bool]] = []
    escalated: list[Record] = []
    for key in sorted(recs):
        rec = recs[key]
        d = digest(key)
        on_kev = rec.cve in kev_ids
        if d not in state.seen:
            if not first and not rec.hosts <= fresh_hosts:
                fresh.append((rec, on_kev))
        elif on_kev and d not in state.kev:
            escalated.append(rec)

    events: list[dict[str, Any]] = []
    bulk = len(fresh) > BURST
    for rec, on_kev in fresh:
        events.append(record_event(rec, "new", on_kev, bulk))
    if bulk:
        events.append(burst_event(fresh, today))
    for rec in escalated:
        events.append(record_event(rec, "kev", True))

    seen = {d: last for d, last in state.seen.items() if day - last <= FORGET_AFTER_DAYS}
    for key in recs:
        seen[digest(key)] = day
    kev_state = state.kev & set(seen)
    if kev_known:
        kev_state |= {digest(k) for k, r in recs.items() if r.cve in kev_ids}

    stale = {h: v for h, v in state.stale.items() if h in reports}
    for host, report in sorted(reports.items()):
        reason = stale_reason(report, now)
        if not reason:
            stale.pop(host, None)
            continue
        if first or host in fresh_hosts or stale.get(host) == today:
            continue
        events.append(stale_event(host, reason, today))
        stale[host] = today

    hosts = {h: str(r.get("generated") or "") for h, r in reports.items()}
    if first:
        stale = {}
    return events, State(hosts=hosts, seen=seen, kev=kev_state, stale=stale)


def _raise_for_throttle(response: httpx.Response, source: str) -> None:
    import sources

    sources._raise_for_throttle(response, source)


async def _get_json(c: httpx.AsyncClient, url: str, missing_ok: bool = False) -> Any:
    cached = _http_cache.get(url)
    headers = {"If-None-Match": cached[0]} if cached and cached[0] else {}
    r = await c.get(url, headers=headers)
    if r.status_code == 304 and cached:
        return cached[1]
    if missing_ok and r.status_code == 404:
        _http_cache.pop(url, None)
        return None
    _raise_for_throttle(r, "vuln")
    r.raise_for_status()
    data = r.json()
    etag = r.headers.get("ETag", "") if getattr(r, "headers", None) else ""
    if etag:
        _http_cache[url] = (etag, data)
    return data


async def kev_catalog() -> frozenset[str] | None:
    if _kev_cache["ids"] is not None and time.time() - _kev_cache["at"] < KEV_TTL:
        return _kev_cache["ids"]
    try:
        async with httpx.AsyncClient(timeout=30.0, headers={"User-Agent": USER_AGENT}) as c:
            r = await c.get(KEV_URL)
        r.raise_for_status()
        ids = frozenset(
            str(v.get("cveID")) for v in (r.json() or {}).get("vulnerabilities") or [] if v.get("cveID")
        )
    except (httpx.HTTPError, ValueError):
        return _kev_cache["ids"]
    _kev_cache.update(at=time.time(), ids=ids)
    return ids


def validate(target: str) -> str:
    t = target.strip().lower()
    if t in ("*", "all"):
        return "*"
    if not HOST_RE.match(t):
        raise ValueError("vuln_inventory expects * (every host) or one host name, e.g. mandragora-vps")
    try:
        with httpx.Client(timeout=5.0, headers={"User-Agent": USER_AGENT}) as c:
            r = c.get(f"{VULN_BASE}/hosts.json")
        hosts = r.json() if r.status_code == 200 else None
    except (httpx.HTTPError, ValueError):
        hosts = None
    if isinstance(hosts, list) and t not in hosts:
        raise ValueError(f"no host {t} publishes to vuln.mvr.ac (known: {', '.join(hosts)})")
    return t


async def fetch(target: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    async with httpx.AsyncClient(timeout=30.0, headers={"User-Agent": USER_AGENT}) as c:
        hosts = await _get_json(c, f"{VULN_BASE}/hosts.json")
        if not isinstance(hosts, list):
            raise RuntimeError("vuln hosts.json is not a list")
        scope = sorted(str(h) for h in hosts) if target == "*" else [target]
        if target != "*" and target not in hosts:
            raise RuntimeError(f"host {target} no longer publishes a report")
        noise = Noise(await _get_json(c, f"{VULN_BASE}/noise.json", missing_ok=True))
        reports = {h: await _get_json(c, f"{VULN_BASE}/report-{h}.json") for h in scope}
        exposures = {h: await _get_json(c, f"{VULN_BASE}/exposure-{h}.json", missing_ok=True) for h in scope}
    kev_ids = await kev_catalog()
    recs = collect(reports, noise, exposures)
    events, state = diff(load_cursor(cursor), cursor is None, reports, recs, kev_ids, datetime.now(timezone.utc))
    return events, dump_cursor(state)
