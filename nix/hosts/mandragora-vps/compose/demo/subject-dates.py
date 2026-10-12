import json
import os
import re
import subprocess
import sys

FIRST_COMMIT = "2018-09-08"
ERAS = {
    "arch-i3": ("2018-09-08", "2019-09-30"),
    "refinement": ("2019-10-01", "2021-01-31"),
    "arch-refinement": ("2019-10-01", "2021-01-31"),
    "silent": ("2021-02-01", "2024-05-31"),
    "nixos-migration": ("2024-06-01", "2026-02-28"),
    "nixos-hyprland": ("2024-06-01", "2026-02-28"),
    "multi-host": ("2026-03-01", "9999-12-31"),
}
STOP = set("""the and for with from into over not but are was its via that this when what why how one two out off
use uses used new old all per any can has have only than then them they who""".split())
TOKEN = re.compile(r"[a-z0-9][a-z0-9.+_-]*[a-z0-9]|[a-z0-9]")
ISO_DATE = re.compile(r"(?<!\d)(20[12]\d-[01]\d-[0-3]\d)(?!\d)")
FRONT_DATE = re.compile(r"^(?:date_start|date|created):\s*(\d{4}-\d{2}-\d{2})", re.M)
ERA = re.compile(r"^era:\s*(\S+)", re.M)


def first_seen(repo):
    log = subprocess.run(["git", "-C", repo, "log", "--format=@%cs%x09%s", "--name-only"],
                         capture_output=True, text=True, check=True).stdout
    first = {}
    day = None
    for line in log.lower().splitlines():
        if line.startswith("@"):
            day, _, subject = line[1:].partition("\t")
            words = TOKEN.findall(subject)
        elif line:
            words = TOKEN.findall(line)
        else:
            continue
        for w in words:
            if w not in first or day < first[w]:
                first[w] = day
    return first


def evidence(text, filename, first):
    front = text.split("\n---", 1)[0] if text.startswith("---") else ""
    m = FRONT_DATE.search(front)
    if m:
        return m.group(1)
    m = re.match(r"(\d{4}-\d{2}-\d{2})", filename)
    if m:
        return m.group(1)
    words = [w for w in TOKEN.findall(filename[:-3].lower()) if len(w) >= 3 and w not in STOP and w in first]
    if words:
        return max(first[w] for w in words)
    dates = [d for d in ISO_DATE.findall(text) if d >= FIRST_COMMIT]
    return min(dates) if dates else None


def subject_date(text, filename, first):
    raw = evidence(text, filename, first)
    m = ERA.search(text.split("\n---", 1)[0]) if text.startswith("---") else None
    lo, hi = ERAS.get(m.group(1), (None, None)) if m else (None, None)
    if raw is None:
        return lo, lo
    if hi and raw > hi:
        return hi, raw
    return raw, raw


def main(vault, graph_path, repo):
    first = first_seen(repo)
    with open(graph_path, encoding="utf-8") as f:
        graph = json.load(f)
    keyed = []
    for node in graph["nodes"]:
        path = node.get("path")
        full = os.path.join(vault, path) if path else None
        if not full or not os.path.isfile(full):
            continue
        with open(full, encoding="utf-8", errors="replace") as f:
            text = f.read()
        since, raw = subject_date(text, os.path.basename(path), first)
        if since:
            keyed.append(((since, raw, path), node))
    keyed.sort(key=lambda k: k[0])
    last = max(len(keyed) - 1, 1)
    for rank, ((since, _, _), node) in enumerate(keyed):
        node["since"] = since
        node["order"] = round(rank / last, 4)
    with open(graph_path, "w", encoding="utf-8") as f:
        json.dump(graph, f, ensure_ascii=False, separators=(",", ":"))
    print(f"subject dates: {len(keyed)} of {len(graph['nodes'])} nodes dated")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "/etc/nixos/mandragora")
