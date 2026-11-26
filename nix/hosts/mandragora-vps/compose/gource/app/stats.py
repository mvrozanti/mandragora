import asyncio
import logging
from collections import Counter
from datetime import datetime

log = logging.getLogger("gource.stats")

HDR = "\x1f"


def _weekday(iso: str) -> int:
    return datetime.strptime(iso[:10], "%Y-%m-%d").weekday()


def _hour(iso: str) -> int:
    return int(iso[11:13])


def _new_path(path: str) -> str:
    if "=>" in path:
        return path.rsplit("=>", 1)[1].strip().strip("{}").strip()
    return path


async def _log_lines(repo) -> list[str]:
    cmd = [
        "git", "log",
        "--numstat",
        "--pretty=format:%x1f%H%x1f%an%x1f%ae%x1f%ai",
    ]
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        cwd=str(repo),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=120)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise RuntimeError("git log timed out")
    if proc.returncode != 0:
        raise RuntimeError(err.decode("utf-8", "replace")[:300])
    return out.decode("utf-8", "replace").splitlines()


async def compute(repo) -> dict:
    lines = await _log_lines(repo)

    day = Counter()
    day_ins = Counter()
    day_del = Counter()
    month = Counter()
    punch = Counter()
    files = Counter()
    authors = {}
    first = last = None
    total_ins = total_del = 0

    cur_name = cur_email = cur_iso = None
    cur_ins = cur_del = 0

    def flush():
        nonlocal cur_ins, cur_del
        if cur_email is None or cur_iso is None:
            return
        d = cur_iso[:10]
        wd, hr = _weekday(cur_iso), _hour(cur_iso)
        day[d] += 1
        day_ins[d] += cur_ins
        day_del[d] += cur_del
        month[d[:7]] += 1
        punch[(wd, hr)] += 1
        a = authors.setdefault(cur_email, {"name": cur_name, "commits": 0, "insertions": 0, "deletions": 0, "first": d, "last": d})
        a["commits"] += 1
        a["insertions"] += cur_ins
        a["deletions"] += cur_del
        a["name"] = cur_name
        a["first"] = min(a["first"], d)
        a["last"] = max(a["last"], d)
        cur_ins = cur_del = 0

    for line in lines:
        if not line:
            flush()
            cur_name = cur_email = cur_iso = None
            continue
        if line[0] == HDR:
            flush()
            name, email, iso = line.split(HDR)[2:]
            cur_name, cur_email, cur_iso = name, email, iso
            d = iso[:10]
            if first is None or d < first:
                first = d
            if last is None or d > last:
                last = d
            continue
        if "\t" not in line:
            continue
        add, delete, path = line.split("\t", 2)
        if add == "-" or delete == "-":
            files[_new_path(path)] += 1
            continue
        ins = int(add)
        dele = int(delete)
        cur_ins += ins
        cur_del += dele
        total_ins += ins
        total_del += dele
        files[_new_path(path)] += 1
    flush()

    return {
        "commits": sum(day.values()),
        "authors": len(authors),
        "insertions": total_ins,
        "deletions": total_del,
        "files": len(files),
        "days_active": len(day),
        "first": first,
        "last": last,
        "daily": {d: {"c": day[d], "i": day_ins[d], "del": day_del[d]} for d in day},
        "monthly": [{"m": m, "c": month[m]} for m in sorted(month)],
        "punch": [[punch.get((wd, hr), 0) for hr in range(24)] for wd in range(7)],
        "authors": sorted(
            ({"name": a["name"], "email": e, **{k: a[k] for k in ("commits", "insertions", "deletions", "first", "last")}}
             for e, a in authors.items()),
            key=lambda x: -x["commits"],
        ),
        "files": sorted(
            ({"path": p, "changes": n} for p, n in files.items()),
            key=lambda x: -x["changes"],
        )[:24],
    }
