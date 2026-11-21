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
INBOX = Path(os.environ.get("PHONE_MEDIA_INBOX", "~/Pictures/PhoneInbox")).expanduser()
ARCHIVE_INDEX = Path(os.environ.get("PHONE_MEDIA_ARCHIVE_INDEX", "~/.cache/phone-archiver-hashes.json")).expanduser()
LEDGER = Path(os.environ.get("PHONE_MEDIA_LEDGER", "~/.local/state/phone-media/archive.json")).expanduser()
RETENTION_DAYS = int(os.environ.get("PHONE_MEDIA_RETENTION_DAYS", "30"))
DRAINED = (
    ("Android/media/com.whatsapp/WhatsApp/Media/", "whatsapp"),
    ("DCIM/", "dcim"),
    ("Pictures/", "pictures"),
    ("Movies/", "movies"),
    ("Recordings/", "recordings"),
    ("Download/", "downloads"),
)
IGNORED_PARTS = {".stversions", ".stfolder", ".thumbnails", "Thumbnails", ".", ".."}
IGNORED_NAMES = {".nomedia", ".stignore"}
IGNORED_PREFIXES = (".trashed-", ".pending-")
IGNORED_SUFFIXES = (".tmp", ".partial", ".part")
PULL_BATCH = 300
NAME_MAX_BYTES = 200
PULL_BYTES = 2 << 30
PENDING_TTL = 6 * 3600
FAILED_PAUSE = 24 * 3600
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


def fitted(name, sha):
    if len(name.encode()) <= NAME_MAX_BYTES:
        return name
    path = Path(name)
    room = NAME_MAX_BYTES - len(path.suffix.encode()) - 9
    return f"{path.stem.encode()[:room].decode('utf-8', 'ignore')}-{sha[:8]}{path.suffix}"


def deliver(meta, folder):
    name = fitted(Path(meta.get("name") or meta["id"]).name, meta["sha256"])
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


def staging(item):
    name = Path(item.get("name") or "").name
    if not name or name in IGNORED_NAMES or name.startswith(IGNORED_PREFIXES) or name.endswith(IGNORED_SUFFIXES) or ".sync-conflict-" in name:
        return None
    path = item.get("path") or ""
    for prefix, bucket in DRAINED:
        if path.startswith(prefix):
            parts = [part for part in path[len(prefix) :].split("/") if part]
            if any(part in IGNORED_PARTS for part in parts):
                return None
            return INBOX.joinpath(bucket, *parts)
    return None


def load_ledger():
    try:
        data = json.loads(LEDGER.read_text())
    except (OSError, ValueError):
        data = {}
    return {"items": dict(data.get("items") or {}), "pending": dict(data.get("pending") or {}), "errors": []}


def save_ledger(ledger):
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    tmp = LEDGER.with_name(LEDGER.name + ".tmp")
    tmp.write_text(json.dumps(ledger))
    os.replace(tmp, LEDGER)


def unchanged(item, record):
    return record is not None and record.get("size") == item.get("size") and record.get("modified") == item.get("modified")


def stage_held(state, items, ledger, now):
    known, pending = ledger["items"], ledger["pending"]
    held = {h["id"]: h for h in state["held"]}
    staged = []
    for mid in list(pending):
        item = items.get(mid)
        if item is None or now - pending[mid] > PENDING_TTL or mid in state["failed"]:
            pending.pop(mid)
            continue
        if mid not in held:
            continue
        folder = staging(item)
        if folder is None:
            pending.pop(mid)
            continue
        try:
            folder.mkdir(parents=True, exist_ok=True)
            deliver(held[mid], folder)
        except (OSError, urllib.error.URLError) as err:
            print(f"phone-media: could not stage {mid} ({item.get('path')}{item.get('name')}): {err}", file=sys.stderr)
            ledger.setdefault("errors", []).append(mid)
            continue
        known[mid] = {"sha256": held[mid]["sha256"], "size": item.get("size"), "modified": item.get("modified"), "at": now}
        pending.pop(mid)
        staged.append(mid)
    return staged


def queue_pulls(state, items, ledger, now):
    known, pending = ledger["items"], ledger["pending"]
    failed = state["failed"]
    wanted = [
        item
        for mid, item in items.items()
        if staging(item) is not None
        and not unchanged(item, known.get(mid))
        and mid not in pending
        and not (mid in failed and now - (failed[mid].get("at") or 0) < FAILED_PAUSE)
    ]
    wanted.sort(key=lambda i: i.get("modified") or 0)
    batch, size = [], 0
    for item in wanted:
        if batch and (len(batch) >= PULL_BATCH or size + (item.get("size") or 0) > PULL_BYTES):
            break
        batch.append(item["id"])
        size += item.get("size") or 0
    for mid in batch:
        pending[mid] = now
    return batch, len(wanted)


def due_deletions(state, items, ledger, now):
    try:
        archived = json.loads(ARCHIVE_INDEX.read_text())
    except (OSError, ValueError):
        return {}
    cutoff = now - RETENTION_DAYS * 86400
    due = {}
    for mid, record in ledger["items"].items():
        item = items.get(mid)
        if item is None or not unchanged(item, record) or (item.get("modified") or now) > cutoff or mid in state["jobs"]["remove"]:
            continue
        copy = archived.get(record["sha256"])
        if copy and Path(copy).is_file() and sha256_of(copy) == record["sha256"]:
            due[mid] = record["sha256"]
    return due


def cmd_archive(args):
    now = time.time()
    state = status()
    items = {i["id"]: i for i in state["index"].get("items") or []}
    if not items:
        print("phone-media: the phone has not sent an index yet; nothing to do")
        return
    ledger = load_ledger()
    ledger["items"] = {mid: rec for mid, rec in ledger["items"].items() if mid in items}
    staged = [] if args.dry_run else stage_held(state, items, ledger, now)
    if staged:
        call("/api/phone/media/release", {"ids": staged})
    batch, behind = queue_pulls(state, items, ledger, now)
    due = due_deletions(state, items, ledger, now)
    errors = ledger.pop("errors", [])
    if not args.dry_run:
        if batch:
            call("/api/phone/media/request", {"pull": batch})
        if due:
            call("/api/phone/media/request", {"archived": due})
        save_ledger(ledger)
    verb = "would" if args.dry_run else "did"
    print(f"phone-media archive ({verb}): staged {len(staged)}, asked for {len(batch)} of {behind} not yet copied, deleting {len(due)} archived and older than {RETENTION_DAYS} days, {len(ledger['pending'])} copies in flight")
    if errors:
        sys.exit(f"phone-media: {len(errors)} could not be staged; they stay held on the desktop and are retried next run")


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
    archive = sub.add_parser("archive")
    archive.add_argument("--dry-run", action="store_true")
    archive.set_defaults(func=cmd_archive)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
