import json
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

HEALTH_DIR = Path(os.environ.get("WATCH_HEALTH_DIR", "/health"))
SILENT_AFTER = timedelta(hours=float(os.environ.get("WATCH_HEALTH_SILENT_HOURS", "2")))
HOST_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
DEFAULT_RULE = "health:stale OR health:silent"


def host_tag(host: str) -> str:
    return "health:" + re.sub(r"[^a-z0-9]+", "_", host.lower()).strip("_")


def human(seconds: float | None) -> str:
    if not seconds:
        return "an unknown interval"
    s = int(seconds)
    for size, unit in ((86400, "d"), (3600, "h"), (60, "min")):
        if s >= size:
            return f"{s / size:.0f}{unit}" if s % size == 0 else f"{s / size:.1f}{unit}"
    return f"{s}s"


def parse(value: Any) -> datetime | None:
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def load(target: str) -> dict[str, dict[str, Any]]:
    if not HEALTH_DIR.is_dir():
        raise RuntimeError(f"{HEALTH_DIR} does not exist: no host has ever published unit health")
    reports: dict[str, dict[str, Any]] = {}
    for path in sorted(HEALTH_DIR.glob("health-*.json")):
        host = path.name[len("health-") : -len(".json")]
        if target != "*" and host != target:
            continue
        try:
            reports[host] = json.loads(path.read_text())
        except (OSError, ValueError) as exc:
            reports[host] = {"error": f"{path.name} is unreadable: {exc}"}
    if target != "*" and target not in reports:
        raise RuntimeError(f"host {target} no longer publishes unit health")
    return reports


def silent_reason(report: dict[str, Any], now: datetime) -> str:
    if report.get("error"):
        return str(report["error"])[:200]
    gen = parse(report.get("generated"))
    if gen is None:
        return "report has no generated timestamp"
    age = now - gen
    if age > SILENT_AFTER:
        return f"last report {human(age.total_seconds())} ago"
    return ""


def stale_event(host: str, unit: dict[str, Any]) -> dict[str, Any]:
    name = str(unit.get("unit") or "")
    last_ok = unit.get("last_ok")
    since = f"since {last_ok}" if last_ok else f"since watching began at {unit.get('watched_since')}"
    user = " --user" if unit.get("scope") == "user" else ""
    return {
        "external_id": f"stale|{host}|{unit.get('scope')}|{name}|{last_ok or unit.get('watched_since')}",
        "title": f"health:stale {host_tag(host)} {name} on {host} has not succeeded {since} "
        f"(runs every {human(unit.get('period'))})",
        "summary": f"due by {unit.get('due_by')} · nothing failed loudly, so the timer stopped firing "
        f"or the job hangs · systemctl{user} status {unit.get('timer')} {name}",
        "link": None,
        "occurred_at": unit.get("due_by"),
        "raw": {"kind": "stale", "host": host, **unit},
    }


def silent_event(host: str, reason: str, today: str) -> dict[str, Any]:
    return {
        "external_id": f"silent|{host}|{today}",
        "title": f"health:silent {host_tag(host)} {host} stopped publishing unit health: {reason}",
        "summary": f"{host} is off, its unit-health-publish timer is broken, or the path to the VPS moved; "
        "stale and failing jobs on it go unnoticed until this clears",
        "link": None,
        "occurred_at": None,
        "raw": {"kind": "silent", "host": host, "reason": reason},
    }


def events(reports: dict[str, dict[str, Any]], now: datetime) -> list[dict[str, Any]]:
    today = now.date().isoformat()
    out: list[dict[str, Any]] = []
    for host, report in sorted(reports.items()):
        reason = silent_reason(report, now)
        if reason:
            out.append(silent_event(host, reason, today))
            continue
        for unit in report.get("units") or []:
            if unit.get("status") == "stale":
                out.append(stale_event(host, unit))
    return out


def validate(target: str) -> str:
    t = target.strip().lower()
    if t in ("*", "all"):
        return "*"
    if not HOST_RE.match(t):
        raise ValueError("unit_health expects * (every host) or one host name, e.g. mandragora")
    return t


async def fetch(target: str, cursor: str | None) -> tuple[list[dict[str, Any]], str | None]:
    return events(load(target), datetime.now(timezone.utc)), "1"
