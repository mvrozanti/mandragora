import json
import os
import sys
import time
import urllib.parse
import urllib.request

VM_URL = os.environ.get("VM_URL", "http://127.0.0.1:8428")
TIMEOUT = float(os.environ.get("VM_TIMEOUT", "10"))


def vm(path: str, params: dict) -> list:
    url = f"{VM_URL}{path}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=TIMEOUT) as resp:
        body = json.loads(resp.read())
    if body.get("status") != "success":
        raise RuntimeError(f"{path}: {body.get('error', 'query failed')}")
    return body["data"]["result"]


def rounded(value: str) -> float | None:
    number = float(value)
    if number != number or number in (float("inf"), float("-inf")):
        return None
    return round(number, 3)


def series_values(expr: str, start: int, end: int, step: int) -> list:
    result = vm("/api/v1/query_range", {"query": expr, "start": start, "end": end, "step": step})
    points = {}
    if result:
        points = {int(float(t)): rounded(v) for t, v in result[0]["values"]}
    return [points.get(t) for t in range(start, end + 1, step)]


def fact_value(expr: str) -> float | None:
    result = vm("/api/v1/query", {"query": expr})
    return rounded(result[0]["value"][1]) if result else None


def classify(code: float | None, ms: float | None, probes: dict) -> str:
    if code is None:
        return "."
    if code == 0 or code >= 500:
        return "d"
    if code >= 400 and int(code) not in probes["gateCodes"]:
        return "w"
    if ms is not None and ms >= probes["slowMs"]:
        return "w"
    return "o"


def by_host(expr: str, start: int, end: int, step: int, scale: float) -> dict:
    result = vm("/api/v1/query_range", {"query": expr, "start": start, "end": end, "step": step})
    hosts = {}
    for row in result:
        host = row["metric"].get("instance", "").split("//", 1)[-1].split("/", 1)[0]
        hosts.setdefault(host, {}).update(
            {int(float(t)): rounded(v) * scale for t, v in row["values"] if rounded(v) is not None}
        )
    return hosts


def probe_states(spec: dict, now: float) -> dict:
    probes, step = spec["probes"], spec["step"]
    end = -(-int(now) // step) * step
    start = end - spec["window"] + step
    sample = probes["sample"]
    selector = '{job="%s"}' % probes["job"]
    codes = by_host(f"probe_http_status_code{selector}", start - step + sample, end, sample, 1)
    durations = by_host(f"probe_duration_seconds{selector}", start - step + sample, end, sample, 1000)
    rank = {".": 0, "o": 1, "w": 2, "d": 3}
    hosts = {}
    for host in probes["hosts"]:
        cells = ["."] * ((end - start) // step + 1)
        code_at, ms_at = codes.get(host, {}), durations.get(host, {})
        raw = {t: classify(code, ms_at.get(t), probes) for t, code in code_at.items()}
        for t, state in raw.items():
            if state == "d" and "d" not in (raw.get(t - sample), raw.get(t + sample)):
                state = "w"
            i = (-(-t // step) * step - start) // step
            if 0 <= i < len(cells) and rank[state] > rank[cells[i]]:
                cells[i] = state
        hosts[host] = "".join(cells)
    return {"source": "desktop", "step": step, "start": start, "end": end, "hosts": hosts}


def build(spec: dict, now: float) -> dict:
    step = spec["step"]
    end = int(now) // step * step
    start = end - spec["window"] + step
    hosts = {}
    for key, host in spec["hosts"].items():
        hosts[key] = {
            "label": host["label"],
            "series": [
                {k: s[k] for k in ("key", "label", "unit", "warn", "crit", "card") if k in s}
                | {"values": series_values(s["expr"], start, end, step)}
                for s in host["series"]
            ],
            "facts": [
                {k: f[k] for k in ("key", "label", "unit")} | {"value": fact_value(f["expr"])}
                for f in host["facts"]
            ],
        }
    return {
        "v": 1,
        "generated": int(now),
        "period": spec["period"],
        "step": step,
        "start": start,
        "end": end,
        "hosts": hosts,
        "probes": probe_states(spec, now),
    }


def write_atomic(path: str, payload: dict) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, separators=(",", ":"))
    os.replace(tmp, path)


def main() -> int:
    spec_path, out_path = sys.argv[1], sys.argv[2]
    with open(spec_path, encoding="utf-8") as fh:
        spec = json.load(fh)
    write_atomic(out_path, build(spec, time.time()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
