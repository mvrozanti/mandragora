import html
from datetime import datetime, timedelta, timezone

VERDICT_KEYS = ("GO", "UNCLEAR", "NO", "pending")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def hours_ago_iso(hours: int) -> str:
    moment = datetime.now(timezone.utc) - timedelta(hours=hours)
    return moment.isoformat(timespec="seconds").replace("+00:00", "Z")


def get_meta(conn_factory, key: str) -> str | None:
    c = conn_factory()
    try:
        row = c.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
    finally:
        c.close()
    return row["value"] if row else None


def set_meta(conn_factory, key: str, value: str) -> None:
    c = conn_factory()
    try:
        c.execute(
            "INSERT INTO meta (key, value) VALUES (?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )
    finally:
        c.close()


def funnel_counts(conn_factory, since: str | None = None) -> dict[str, int]:
    query = (
        "SELECT COALESCE(e.ai_verdict, 'pending') AS verdict, COUNT(*) AS n "
        "FROM events e JOIN watchers w ON w.id = e.watcher_id "
        "WHERE w.ai_spec IS NOT NULL"
    )
    params: list = []
    if since:
        query += " AND e.received_at >= ?"
        params.append(since)
    query += " GROUP BY 1"
    c = conn_factory()
    try:
        rows = c.execute(query, params).fetchall()
    finally:
        c.close()
    counts = {key: 0 for key in VERDICT_KEYS}
    for row in rows:
        counts[row["verdict"]] = counts.get(row["verdict"], 0) + row["n"]
    return counts


def pending_unjudged(conn_factory) -> int:
    c = conn_factory()
    try:
        row = c.execute(
            "SELECT COUNT(*) AS n FROM events e JOIN watchers w ON w.id = e.watcher_id "
            "WHERE e.ai_verdict IS NULL AND w.ai_spec IS NOT NULL AND w.enabled = 1"
        ).fetchone()
    finally:
        c.close()
    return int(row["n"])


def escalated_open(conn_factory) -> int:
    c = conn_factory()
    try:
        row = c.execute(
            "SELECT COUNT(*) AS n FROM events e JOIN watchers w ON w.id = e.watcher_id "
            "WHERE e.escalated_at IS NOT NULL AND e.acked_at IS NULL AND w.enabled = 1"
        ).fetchone()
    finally:
        c.close()
    return int(row["n"])


def event_totals(conn_factory, since: str | None = None) -> int:
    query = "SELECT COUNT(*) AS n FROM events"
    params: list = []
    if since:
        query += " WHERE received_at >= ?"
        params.append(since)
    c = conn_factory()
    try:
        row = c.execute(query, params).fetchone()
    finally:
        c.close()
    return int(row["n"])


def last_poll_at(conn_factory) -> str | None:
    c = conn_factory()
    try:
        row = c.execute("SELECT MAX(last_polled_at) AS t FROM watchers").fetchone()
    finally:
        c.close()
    return row["t"] if row else None


def watcher_summary(conn_factory) -> dict[str, int]:
    c = conn_factory()
    try:
        row = c.execute(
            "SELECT COUNT(*) AS total, "
            "SUM(CASE WHEN enabled = 1 THEN 1 ELSE 0 END) AS enabled, "
            "SUM(CASE WHEN enabled = 1 AND push = 1 THEN 1 ELSE 0 END) AS pushing, "
            "SUM(CASE WHEN enabled = 1 AND push = 1 AND ai_spec IS NOT NULL THEN 1 ELSE 0 END) AS judged "
            "FROM watchers"
        ).fetchone()
    finally:
        c.close()
    return {
        "total": int(row["total"] or 0),
        "enabled": int(row["enabled"] or 0),
        "pushing": int(row["pushing"] or 0),
        "judged": int(row["judged"] or 0),
    }


def undecidable_specs(conn_factory) -> list[dict]:
    c = conn_factory()
    try:
        rows = c.execute(
            "SELECT id, name, kind, target, spec_lint FROM watchers "
            "WHERE enabled = 1 AND ai_spec IS NOT NULL AND spec_lint IS NOT NULL "
            "AND spec_lint NOT LIKE '%\"decidable\": true%' ORDER BY id"
        ).fetchall()
    except Exception:
        return []
    finally:
        c.close()
    return [dict(row) for row in rows]


def collect(conn_factory) -> dict:
    return {
        "last_poll_at": last_poll_at(conn_factory),
        "last_push_at": get_meta(conn_factory, "last_push_at"),
        "pending_unjudged": pending_unjudged(conn_factory),
        "escalated_open": escalated_open(conn_factory),
        "events_24h": event_totals(conn_factory, hours_ago_iso(24)),
        "events_total": event_totals(conn_factory),
        "funnel_24h": funnel_counts(conn_factory, hours_ago_iso(24)),
        "funnel_lifetime": funnel_counts(conn_factory),
        "watchers": watcher_summary(conn_factory),
    }


def _funnel_line(counts: dict[str, int]) -> str:
    return " · ".join(f"{key} {counts.get(key, 0)}" for key in VERDICT_KEYS)


def format_status(snapshot: dict, telegram_enabled: bool, undecidable: list[dict] | None = None) -> str:
    watchers = snapshot.get("watchers") or {}
    lines = [
        "<b>watch status</b>",
        f"watchers: {watchers.get('enabled', 0)} enabled · {watchers.get('pushing', 0)} pushing · {watchers.get('judged', 0)} ai-gated",
        f"events: {snapshot.get('events_24h', 0)} in 24h · {snapshot.get('events_total', 0)} total",
        f"24h funnel: {_funnel_line(snapshot.get('funnel_24h') or {})}",
        f"lifetime: {_funnel_line(snapshot.get('funnel_lifetime') or {})}",
        f"pending unjudged: {snapshot.get('pending_unjudged', 0)} · escalated open: {snapshot.get('escalated_open', 0)}",
        f"last poll: {snapshot.get('last_poll_at') or 'never'}",
        f"last push: {snapshot.get('last_push_at') or 'never'}",
        f"telegram: {'enabled' if telegram_enabled else 'DISABLED'}",
    ]
    for watcher in undecidable or []:
        label = html.escape(f"{watcher.get('name') or watcher.get('kind')}", quote=False)
        lines.append(f"⚠ undecidable spec: <code>{watcher.get('id')}</code> {label}")
    return "\n".join(lines)
