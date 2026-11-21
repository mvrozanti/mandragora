import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

BRIDGE = os.environ.get("PHONE_MEDIA_BRIDGE", "http://127.0.0.1:6688")
SHEET_PAGE = 48
FONT = os.environ.get("PHONE_MEDIA_FONT")


def call(path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(f"{BRIDGE}{path}", data=data, headers={"Content-Type": "application/json"}, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as err:
        detail = err.read().decode("utf-8", "replace")
        sys.exit(f"phone-media: {path}: {err.code} {detail}")
    except urllib.error.URLError as err:
        sys.exit(f"phone-media: bridge unreachable at {BRIDGE}: {err.reason}")


def status():
    return call("/api/phone/media")


def ago(stamp):
    if not stamp:
        return "never"
    minutes = int((time.time() - stamp) / 60)
    return f"{minutes} min ago" if minutes < 120 else f"{minutes // 60} h ago"


def taken(item):
    ms = item.get("taken") or 0
    seconds = ms / 1000 if ms else item.get("modified") or 0
    return datetime.fromtimestamp(seconds) if seconds else None


def select(items, args):
    chosen = []
    since = datetime.fromisoformat(args.since) if getattr(args, "since", None) else None
    until = datetime.fromisoformat(args.until) if getattr(args, "until", None) else None
    for item in items:
        when = taken(item)
        where = f"{item.get('path') or ''}{item.get('name') or ''}".lower()
        if since and (when is None or when < since):
            continue
        if until and (when is None or when >= until):
            continue
        if getattr(args, "path", None) and args.path.lower() not in where:
            continue
        if getattr(args, "kind", None) and item.get("kind") != args.kind:
            continue
        chosen.append(item)
    chosen.sort(key=lambda i: taken(i) or datetime.min, reverse=True)
    return chosen[: args.limit] if getattr(args, "limit", None) else chosen


def wait_until(predicate, seconds, what):
    deadline = time.time() + seconds
    state = status()
    while not predicate(state):
        if time.time() >= deadline:
            print(f"phone-media: still waiting for {what}; the phone last checked in {ago(state.get('seen'))}. Run the same command again later, or open the app on the phone.")
            return None
        time.sleep(3)
        state = status()
    return state


def cmd_status(_args):
    state = status()
    index = state["index"]
    jobs = state["jobs"]
    print(f"phone last checked in: {ago(state.get('seen'))}")
    print(f"index: {len(index.get('items') or [])} items, posted {ago(index.get('at'))}")
    print(f"queued: {len(jobs['thumbs'])} thumbnails, {len(jobs['pull'])} copies, {len(jobs['remove'])} deletions")
    print(f"held on the desktop: {len(state['held'])}")
    for mid, failure in state["failed"].items():
        print(f"failed {failure['job']} {mid}: {failure['error']}")


def cmd_ls(args):
    for item in select(status()["index"].get("items") or [], args):
        when = taken(item)
        size = (item.get("size") or 0) / 1e6
        print(f"{item['id']:>8}  {when:%Y-%m-%d %H:%M}  {size:7.1f} MB  {item.get('path') or ''}{item.get('name') or ''}" if when else f"{item['id']:>8}  ?  {item.get('path')}{item.get('name')}")


def cmd_sheet(args):
    chosen = select(status()["index"].get("items") or [], args)
    if not chosen:
        sys.exit("phone-media: nothing matches")
    ids = [i["id"] for i in chosen]
    call("/api/phone/media/request", {"thumbs": ids})
    state = wait_until(lambda s: set(ids) <= set(s["thumbs"]) | set(s["failed"]), args.wait, f"{len(ids)} thumbnails")
    have = set((state or status())["thumbs"])
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        tiles = []
        for item in chosen:
            if item["id"] not in have:
                continue
            tile = Path(scratch) / f"{item['id']}.jpg"
            with urllib.request.urlopen(f"{BRIDGE}/api/phone/media/thumb?id={item['id']}", timeout=30) as response:
                tile.write_bytes(response.read())
            when = taken(item)
            tiles.append((tile, f"{item['id']} {when:%m-%d}" if when else item["id"]))
        for page in range(0, len(tiles), SHEET_PAGE):
            target = out / f"sheet-{page // SHEET_PAGE + 1}.jpg"
            argv = ["montage"] + (["-font", FONT] if FONT else [])
            for tile, label in tiles[page : page + SHEET_PAGE]:
                argv += ["-label", label, str(tile)]
            argv += ["-pointsize", "14", "-geometry", "240x240+4+4", "-tile", "8x", str(target)]
            subprocess.run(argv, check=True)
            print(target)
    if len(tiles) < len(chosen):
        print(f"phone-media: {len(chosen) - len(tiles)} thumbnails not delivered yet", file=sys.stderr)


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def deliver(meta, folder):
    name = Path(meta.get("name") or meta["id"]).name
    target = folder / name
    if target.exists():
        if sha256_of(target) == meta["sha256"]:
            return target
        target = folder / f"{target.stem}-{meta['sha256'][:8]}{target.suffix}"
        if target.exists() and sha256_of(target) == meta["sha256"]:
            return target
    partial = target.with_name(target.name + ".partial")
    with urllib.request.urlopen(f"{BRIDGE}/api/phone/media/held?id={meta['id']}", timeout=60) as response, open(partial, "wb") as fh:
        while chunk := response.read(1 << 20):
            fh.write(chunk)
    if sha256_of(partial) != meta["sha256"]:
        partial.unlink()
        sys.exit(f"phone-media: {meta['id']} arrived corrupted; nothing was removed from the phone")
    partial.rename(target)
    stamp = (meta.get("taken") or 0) / 1000 or meta.get("modified")
    if stamp:
        os.utime(target, (stamp, stamp))
    return target


def cmd_move(args):
    ids = list(dict.fromkeys(args.ids))
    folder = Path(args.to).expanduser()
    folder.mkdir(parents=True, exist_ok=True)
    known = {i["id"] for i in status()["index"].get("items") or []}
    unknown = [mid for mid in ids if mid not in known]
    if unknown:
        sys.exit(f"phone-media: not in the phone's index: {', '.join(unknown)}")
    call("/api/phone/media/request", {"pull": ids})
    state = wait_until(lambda s: set(ids) <= {h["id"] for h in s["held"]} | set(s["failed"]), args.wait, f"{len(ids)} copies")
    if state is None:
        return
    held = {h["id"]: h for h in state["held"]}
    failed = [mid for mid in ids if mid not in held]
    for mid in failed:
        print(f"phone-media: {mid} not copied: {state['failed'].get(mid, {}).get('error')}", file=sys.stderr)
    copied = [mid for mid in ids if mid in held]
    for mid in copied:
        print(f"copied {mid} -> {deliver(held[mid], folder)}")
    if args.keep or not copied:
        call("/api/phone/media/release", {"ids": copied})
        return
    call("/api/phone/media/request", {"remove": copied})
    state = wait_until(lambda s: not set(copied) & set(s["jobs"]["remove"]), args.wait, f"{len(copied)} deletions on the phone")
    if state is None:
        return
    for mid in copied:
        failure = state["failed"].get(mid)
        print(f"phone kept {mid}: {failure['error']}" if failure else f"removed {mid} from the phone")
    call("/api/phone/media/release", {"ids": copied})


def main():
    parser = argparse.ArgumentParser(prog="phone-media", description="Photos and videos on the phone, through the mandragora app and phone-bridge.")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status").set_defaults(func=cmd_status)
    for name, func in (("ls", cmd_ls), ("sheet", cmd_sheet)):
        p = sub.add_parser(name)
        p.add_argument("--since")
        p.add_argument("--until")
        p.add_argument("--path")
        p.add_argument("--kind", choices=("image", "video"))
        p.add_argument("--limit", type=int)
        if name == "sheet":
            p.add_argument("--out", default="~/.cache/phone-media/sheets")
            p.add_argument("--wait", type=int, default=900)
        p.set_defaults(func=func)
    move = sub.add_parser("move")
    move.add_argument("ids", nargs="+")
    move.add_argument("--to", required=True)
    move.add_argument("--keep", action="store_true")
    move.add_argument("--wait", type=int, default=1800)
    move.set_defaults(func=cmd_move)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
