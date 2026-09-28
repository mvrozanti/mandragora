import ipaddress
import json
import os
import re
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

FIREWALL = json.loads(Path(os.environ["VULN_FIREWALL"]).read_text())
OUT = Path(os.environ.get("VULN_EXPOSURE_OUT", "/run/vuln-exposure/exposure.json"))
STORE_RE = re.compile(r"/nix/store/[0-9a-z]{32}-([^/\s]+)")
DRV_SPLIT = re.compile(r"^(.*?)-([^a-zA-Z].*)$")
OUTPUT_SUFFIX = re.compile(r"(-[a-z][a-z0-9]*)+$")
PY_PREFIX = re.compile(r"^python3\.\d+-")
PHYSICAL = re.compile(r"^(en|eth|wl)")
TAILNET = "tailscale0"


def ports_allowed(spec: dict) -> set[int]:
    ports = set(spec.get("allowedTCPPorts") or [])
    for r in spec.get("allowedTCPPortRanges") or []:
        ports |= set(range(int(r["from"]), int(r["to"]) + 1))
    return ports


GLOBAL = ports_allowed(FIREWALL)
PER_IFACE = {name: ports_allowed(spec) for name, spec in (FIREWALL.get("interfaces") or {}).items()}
TRUSTED = set(FIREWALL.get("trustedInterfaces") or [])


def allowed(iface: str, port: int) -> bool:
    return iface in TRUSTED or port in GLOBAL or port in PER_IFACE.get(iface, set())


def interfaces() -> dict[str, list[ipaddress._BaseAddress]]:
    raw = json.loads(subprocess.run(["ip", "-j", "addr"], check=True, capture_output=True, text=True).stdout)
    out: dict[str, list] = {}
    for link in raw:
        out[link["ifname"]] = [ipaddress.ip_address(a["local"]) for a in link.get("addr_info") or []]
    return out


def scope_of(bind: str, port: int, ifaces: dict[str, list]) -> str:
    addr = ipaddress.ip_address(bind.strip("[]").split("%")[0])
    if addr.is_loopback:
        return ""
    if addr.is_unspecified:
        candidates = [i for i in ifaces if i != "lo"]
    else:
        candidates = [i for i, addrs in ifaces.items() if addr in addrs]
    physical = [i for i in candidates if PHYSICAL.match(i) and allowed(i, port)]
    if physical:
        return "open" if port in GLOBAL else "lan"
    if TAILNET in candidates and allowed(TAILNET, port):
        return "tailnet"
    return ""


def parse_store_name(name: str) -> tuple[str, str] | None:
    m = DRV_SPLIT.match(name)
    if not m:
        return None
    pname, version = m.group(1), OUTPUT_SUFFIX.sub("", m.group(2))
    return pname, version


def candidates(pname: str) -> set[str]:
    out = {pname}
    stripped = PY_PREFIX.sub("", pname)
    out.add(stripped)
    if re.fullmatch(r"python3(\.\d+)?", pname):
        out.add("python")
    return out


def packages_of(pid: int) -> list[dict[str, str]]:
    paths: set[str] = set()
    for probe in (f"/proc/{pid}/exe", f"/proc/{pid}/maps", f"/proc/{pid}/cmdline"):
        try:
            if probe.endswith("exe"):
                text = os.readlink(probe)
            else:
                text = Path(probe).read_bytes().replace(b"\0", b" ").decode(errors="replace")
        except OSError:
            continue
        paths.update(STORE_RE.findall(text))
    pkgs: dict[tuple[str, str], None] = {}
    for name in paths:
        parsed = parse_store_name(name)
        if not parsed:
            continue
        pname, version = parsed
        for p in candidates(pname):
            pkgs[(p, version)] = None
    return [{"pname": p, "version": v} for p, v in sorted(pkgs)]


SS_LINE = re.compile(r"^\S+\s+\d+\s+\d+\s+(\S+):(\d+)\s+\S+\s*(.*)$")
SS_USER = re.compile(r'\("([^"]*)",pid=(\d+)')


def listeners() -> list[dict]:
    raw = subprocess.run(["ss", "-tlnpH"], check=True, capture_output=True, text=True).stdout
    ifaces = interfaces()
    seen: dict[tuple[int, str], dict] = {}
    for line in raw.splitlines():
        m = SS_LINE.match(line.strip())
        if not m:
            continue
        bind, port, users = m.group(1), int(m.group(2)), m.group(3)
        bind = "0.0.0.0" if bind == "*" else bind
        try:
            scope = scope_of(bind, port, ifaces)
        except ValueError:
            continue
        if not scope:
            continue
        for process, pid in SS_USER.findall(users) or [("?", "")]:
            key = (port, process)
            if key in seen:
                continue
            seen[key] = {
                "port": port,
                "proto": "tcp",
                "bind": bind,
                "scope": scope,
                "process": process,
                "packages": packages_of(int(pid)) if pid else [],
            }
    return sorted(seen.values(), key=lambda x: (x["port"], x["process"]))


def main() -> int:
    report = {
        "schema": 1,
        "host": socket.gethostname(),
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "listeners": listeners(),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(report, indent=1) + "\n")
    tmp.chmod(0o644)
    tmp.replace(OUT)
    print(f"{len(report['listeners'])} exposed listener(s) -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
