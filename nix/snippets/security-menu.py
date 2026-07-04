#!/usr/bin/env python3
import argparse
import html
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

STATE_DIR = Path.home() / ".local/state/cve-scan"
LATEST = STATE_DIR / "latest.json"

NOISE_VERSION_SUFFIXES = (
    "-tex", "-texdoc", "-man", "-texman",
    "-source", "-source-unsecvars", "-binlore", "-env",
    "-builder", "-unwrapped", "-wrapped",
    "-vendor", "-vendor-staging",
    "-go-modules", "-bootstrap",
    "-r2.cabal",
)
NOISE_VERSION_REGEX = re.compile(r"\.(jar|pom|pam)$")
NOISE_VERSION_CONTAINS = ("-bootstrap-",)

NOISE_PNAME_VERSION = {
    ("ShellCheck", "0.11.0"), ("shellcheck", "0.11.0"),
    ("Diff", "1.0.2"),
    ("async", "2.2.6"), ("bytes", "1.11.0"),
    ("h3", "0.0.8"), ("http-client", "0.7.19"),
    ("hyper", "1.9.0"), ("instant", "0.1.13"),
    ("kitty", "0.46.2"), ("memcached", "1.6.41"),
    ("mujs", "1.3.6"), ("network", "3.2.8.0"),
    ("stringbuilder", "0.5.1"), ("system-configuration", "0.6.1"),
    ("tap", "1.0.1"), ("tokio", "1.52.1"),
    ("uuid", "1.18.1"), ("uuid", "1.20.0"),
    ("vault", "0.3.1.6"), ("warp", "3.4.9"),
    ("wire", "0.7.0"), ("yaml", "0.11.11.2"),
    ("yoke", "0.8.1"), ("yoke", "0.8.2"),
    ("web", "4.5"), ("markdown", "3.13.0-0-gdd212d58"),
    ("gnulib", "0a01f67"), ("impala", "0.7.4"),
    ("lapack", "3"), ("curl", "0.4.49"),
    ("rhino", "1.8.0"), ("gutenberg", "0-unstable-2024-07-29"),
    ("bash", "2.05b"),
    ("gcc", "4.6.4"),
    ("openssl", "0.10.78"),
    ("zlib", "0.7.1.1"),
    ("orc", "0.4.41"),
    ("python", "2.7.18.12"),
    ("openssl", "3.0.19"),
    ("gzip", "1.2.4"),
    ("rubygems", "3.7.2"),
    ("sassc", "3.6.2"),
    ("zlib", "1.3.1"),
    ("subversion", "1.14.5"),
}

NOISE_EXACT = {
    ("ShellCheck", "CVE-2021-28794"),
    ("kitty", "CVE-2016-2563"),
    ("hyper", "CVE-2024-23741"),
    ("snappy", "CVE-2023-28115"),
    ("snappy", "CVE-2023-41330"),
    ("memcached", "CVE-2022-26635"),
}

SEVERITIES = [
    ("CRITICAL", 9.0, float("inf"), "", "color1"),
    ("HIGH",     7.0, 9.0,          "", "color3"),
    ("MEDIUM",   4.0, 7.0,          "", "color3"),
    ("LOW",      0.1, 4.0,          "", "color4"),
    ("UNKNOWN",  -1,  0.1,          "", "color8"),
]


def max_score(entry: dict) -> float:
    scores = entry.get("cvssv3_basescore", {}) or {}
    return max(scores.values()) if scores else 0.0


def is_noise(entry: dict) -> bool:
    pname = entry.get("pname", "") or ""
    version = entry.get("version", "") or ""
    if any(version.endswith(s) for s in NOISE_VERSION_SUFFIXES):
        return True
    if NOISE_VERSION_REGEX.search(version):
        return True
    if any(tok in version for tok in NOISE_VERSION_CONTAINS):
        return True
    if (pname, version) in NOISE_PNAME_VERSION:
        return True
    cves = entry.get("affected_by", []) or []
    if cves and all((pname, cve) in NOISE_EXACT for cve in cves):
        return True
    return False


def severity_of(score: float) -> str:
    for label, lo, hi, *_ in SEVERITIES:
        if lo <= score < hi:
            return label
    return "UNKNOWN"


def load_report():
    if not LATEST.exists():
        return None, None
    try:
        data = json.loads(LATEST.read_text())
    except (OSError, json.JSONDecodeError):
        return None, None
    try:
        mtime = LATEST.stat().st_mtime
    except OSError:
        mtime = None
    return data, mtime


def bucketize(data, include_noise=False):
    buckets = {label: [] for label, *_ in SEVERITIES}
    suppressed = 0
    for entry in data:
        if is_noise(entry):
            suppressed += 1
            if not include_noise:
                continue
        scores = entry.get("cvssv3_basescore", {}) or {}
        descs = entry.get("description", {}) or {}
        if not scores:
            buckets["UNKNOWN"].append((entry, None, 0.0, ""))
            continue
        for cve, score in scores.items():
            buckets[severity_of(score)].append(
                (entry, cve, score, descs.get(cve, ""))
            )
    for label in buckets:
        buckets[label].sort(key=lambda row: -row[2])
    return buckets, suppressed


def cmd_waybar(_args) -> int:
    data, mtime = load_report()
    icon = '<span font_family="Font Awesome 7 Free Solid"></span>'
    if data is None:
        payload = {
            "text": f"? {icon}",
            "tooltip": "no cve scan report — run cve-scan.service",
            "class": "stale",
            "alt": "stale",
        }
        print(json.dumps(payload), flush=True)
        return 0

    buckets, suppressed = bucketize(data)

    def sev_pkgs(*labels):
        s = set()
        for lb in labels:
            for entry, *_ in buckets[lb]:
                s.add((entry.get("pname"), entry.get("version")))
        return s

    crit_pkgs = sev_pkgs("CRITICAL")
    crit = len(crit_pkgs)
    high = len(sev_pkgs("HIGH") - crit_pkgs)
    med = len(sev_pkgs("MEDIUM"))
    low = len(sev_pkgs("LOW"))
    unk = len(sev_pkgs("UNKNOWN"))
    total = len(sev_pkgs("CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"))

    badge = crit if crit else high
    if crit:
        cls = "critical"
    elif high:
        cls = "high"
    else:
        cls = "clean"
    text = f"{badge} {icon}" if badge else icon

    age = ""
    if mtime is not None:
        try:
            age = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
        except (OverflowError, OSError, ValueError):
            age = ""

    tip_lines = [f"<b>CVE scan</b> — {age}" if age else "<b>CVE scan</b>"]
    tip_lines.append("<i>distinct packages by top severity</i>")
    tip_lines.append("")
    tip_lines.append(f"CRITICAL ≥9.0  {crit}")
    tip_lines.append(f"HIGH     7–9   {high}")
    tip_lines.append(f"MEDIUM   4–7   {med}")
    tip_lines.append(f"LOW      &lt;4    {low}")
    if unk:
        tip_lines.append(f"UNKNOWN  -     {unk}")
    tip_lines.append("")
    tip_lines.append(f"<i>{total} pkgs flagged · {suppressed} suppressed</i>")
    tip_lines.append("<i>vulnix over-reports nixpkgs backports</i>")
    tip_lines.append("<i>click — browse · right — rescan</i>")

    payload = {
        "text": text,
        "tooltip": "\n".join(tip_lines),
        "class": cls,
        "alt": cls,
    }
    print(json.dumps(payload), flush=True)
    return 0


def trigger_rescan() -> None:
    subprocess.Popen(
        ["systemctl", "--user", "start", "cve-scan.service"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def rofi_pick(rows, *, include_noise: bool):
    if not rows:
        rows = [(None, "no vulnerabilities — enter to close", "CLEAN", 0.0)]
    lines = []
    for idx, (_url, label, sev, _score) in enumerate(rows):
        glyph = next((g for s, _, _, g, _ in SEVERITIES if s == sev), "")
        lines.append(f"{glyph}  {label}\x00info\x1f{idx}")
    theme = Path.home() / ".config/rofi/themes/menu.rasi"
    mesg = (
        "<b>Enter</b> open NVD · <b>Alt+r</b> rescan · "
        f"<b>Alt+n</b> {'hide' if include_noise else 'show'} suppressed"
    )
    proc = subprocess.run(
        [
            "rofi",
            "-dmenu",
            "-i",
            "-p",
            "cve",
            "-theme",
            str(theme),
            "-theme-str",
            "window { width: 60%; } listview { lines: 18; }",
            "-format",
            "i:s",
            "-kb-custom-1",
            "Alt+r",
            "-kb-custom-2",
            "Alt+n",
            "-markup-rows",
            "-mesg",
            mesg,
        ],
        input="\n".join(lines),
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode == 10:
        return "__rescan__", None
    if proc.returncode == 11:
        return "__toggle_noise__", None
    if proc.returncode != 0:
        return None, None
    out = proc.stdout.strip()
    if not out:
        return None, None
    idx_str, _, _ = out.partition(":")
    try:
        idx = int(idx_str)
    except ValueError:
        return None, None
    if idx < 0 or idx >= len(rows):
        return None, None
    return "__open__", rows[idx]


def build_rows(buckets):
    rows = []
    for label, *_ in SEVERITIES:
        entries = buckets.get(label, [])
        for entry, cve, score, desc in entries:
            pname = entry.get("pname", "?")
            version = entry.get("version", "")
            score_str = f"{score:0.1f}" if score else "  -"
            desc_short = (desc or "").strip().splitlines()[0] if desc else ""
            if len(desc_short) > 110:
                desc_short = desc_short[:107] + "..."
            cve_str = cve or "(no CVE id)"
            label_text = (
                f"<b>{label:<8}</b> {score_str}  "
                f"<b>{html.escape(pname)}</b> {html.escape(version)}  "
                f"<i>{html.escape(cve_str)}</i>"
            )
            if desc_short:
                label_text += f"  — {html.escape(desc_short)}"
            url = (
                f"https://nvd.nist.gov/vuln/detail/{cve}" if cve else None
            )
            rows.append((url, label_text, label, score))
    return rows


def cmd_pick(args) -> int:
    include_noise = bool(args.show_suppressed)
    while True:
        data, _ = load_report()
        if data is None:
            subprocess.run(
                [
                    "notify-send",
                    "-a",
                    "security-menu",
                    "CVE scan",
                    "No report yet — running scan now (up to 5 min)…",
                ],
                check=False,
            )
            trigger_rescan()
            return 0
        buckets, _suppressed = bucketize(data, include_noise=include_noise)
        rows = build_rows(buckets)
        action, picked = rofi_pick(rows, include_noise=include_noise)
        if action is None:
            return 0
        if action == "__rescan__":
            trigger_rescan()
            subprocess.run(
                [
                    "notify-send",
                    "-a",
                    "security-menu",
                    "CVE scan",
                    "Rescan started — refresh in a few minutes.",
                ],
                check=False,
            )
            return 0
        if action == "__toggle_noise__":
            include_noise = not include_noise
            continue
        if action == "__open__" and picked and picked[0]:
            subprocess.Popen(
                ["xdg-open", picked[0]],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        return 0


def cmd_rescan(_args) -> int:
    trigger_rescan()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="security-menu")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_waybar = sub.add_parser("waybar", help="emit waybar JSON")
    p_waybar.set_defaults(func=cmd_waybar)
    p_pick = sub.add_parser("pick", help="open rofi vulnerability picker")
    p_pick.add_argument(
        "--show-suppressed",
        action="store_true",
        help="include name-collision false positives",
    )
    p_pick.set_defaults(func=cmd_pick)
    p_rescan = sub.add_parser("rescan", help="trigger cve-scan.service")
    p_rescan.set_defaults(func=cmd_rescan)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
