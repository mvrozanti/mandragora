#!/usr/bin/env python3
import argparse
import email
import email.policy
import fcntl
import json
import os
import queue
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time
from email.utils import parseaddr, parsedate_to_datetime
from pathlib import Path

HOME = Path.home()
MBSYNCRC = HOME / ".mbsyncrc"
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "mail-menu"
NEEDS_AUTH = RUNTIME / "needs-auth"
LAST_SYNC = RUNTIME / "last-sync"
SIGNIN_LOCK = RUNTIME / "signin.lock"
WAYBAR_SIGNAL = "SIGRTMIN+17"
STALE_SECONDS = 1800
BROWSER_TIMEOUT = 300
DEVICE_TIMEOUT = 900
ICON = "󰇮"
AERC = [
    "smart-launch",
    "_aerc_",
    "[workspace 5] kitty --class _aerc_ --title _aerc_ -o close_on_child_death=yes -e aerc",
]


def self_bin() -> str:
    path = os.environ.get("MAIL_MENU_BIN", "mail-menu")
    return path if os.path.isabs(path) else (shutil.which(path) or path)


def account_config() -> tuple[str, list[str]]:
    account, passcmd = "", ""
    for line in MBSYNCRC.read_text().splitlines():
        key, _, value = line.strip().partition(" ")
        if key == "IMAPAccount" and not account:
            account = value.strip()
        elif key == "PassCmd" and not passcmd:
            passcmd = value.strip()
    argv = shlex.split(shlex.split(passcmd)[0]) if passcmd else []
    return account, argv


def inbox() -> Path:
    account, _ = account_config()
    return DATA / "mail" / account / "INBOX"


def notify(summary: str, body: str = "", urgency: str = "normal") -> None:
    subprocess.run(
        ["notify-send", "-a", "Mail", "-u", urgency, "-i", "mail-unread", summary, body],
        check=False,
    )


def refresh_waybar() -> None:
    subprocess.run(
        ["pkill", "--signal", WAYBAR_SIGNAL, "waybar"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def is_unread(path: Path) -> bool:
    if path.parent.name == "new":
        return True
    _, _, info = path.name.partition(":2,")
    return "S" not in info


def unread_files() -> list[Path]:
    box = inbox()
    files = [p for sub in ("new", "cur") for p in (box / sub).glob("*") if p.is_file()]
    unread = [p for p in files if is_unread(p)]
    unread.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return unread


def headers(path: Path) -> tuple[str, str, str]:
    try:
        with path.open("rb") as fh:
            msg = email.message_from_binary_file(fh, policy=email.policy.default)
        name, addr = parseaddr(str(msg.get("From", "")))
        subject = " ".join(str(msg.get("Subject", "")).split()) or "(no subject)"
        try:
            when = parsedate_to_datetime(str(msg.get("Date"))).astimezone().strftime("%d/%m %H:%M")
        except (TypeError, ValueError):
            when = ""
        return name or addr or "?", subject, when
    except OSError:
        return "?", "(unreadable)", ""


def last_sync_age() -> float | None:
    try:
        return time.time() - LAST_SYNC.stat().st_mtime
    except OSError:
        return None


def waybar_payload() -> dict:
    if NEEDS_AUTH.exists():
        return {
            "text": f"{ICON} !",
            "class": "auth",
            "alt": "auth",
            "tooltip": "Hotmail sign-in expired: mail is not syncing.\nClick to sign in.",
        }
    unread = unread_files()
    age = last_sync_age()
    lines = [f"{len(unread)} unread in Inbox"]
    for path in unread[:8]:
        sender, subject, when = headers(path)
        lines.append(f"· {sender}: {subject}" + (f"  ({when})" if when else ""))
    if age is None:
        lines.append("not synced since boot")
    else:
        lines.append(f"synced {int(age // 60)} min ago")
    if age is not None and age > STALE_SECONDS:
        cls = "stale"
    elif unread:
        cls = "unread"
    else:
        cls = "empty"
    text = f"{ICON} {len(unread)}" if unread else ICON
    return {"text": text, "class": cls, "alt": cls, "tooltip": "\n".join(lines)}


def cmd_waybar(args) -> int:
    print(json.dumps(waybar_payload()), flush=True)
    return 0


def open_aerc() -> None:
    subprocess.Popen(AERC, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def sync_now() -> None:
    subprocess.run(["systemctl", "--user", "start", "--no-block", "mbsync-hotmail.service"], check=False)


def rofi(rows: list[str], mesg: str) -> tuple[int, int | None]:
    theme = HOME / ".config/rofi/themes/menu.rasi"
    proc = subprocess.run(
        [
            "rofi", "-dmenu", "-i", "-p", "mail",
            "-theme", str(theme),
            "-theme-str", "window { width: 46%; } listview { lines: 12; }",
            "-format", "i",
            "-kb-custom-1", "Alt+r",
            "-mesg", mesg,
        ],
        input="\n".join(rows),
        capture_output=True,
        text=True,
        check=False,
    )
    out = proc.stdout.strip()
    return proc.returncode, (int(out) if out.isdigit() else None)


def cmd_pick(args) -> int:
    if NEEDS_AUTH.exists():
        return cmd_signin(args)
    unread = unread_files()
    rows = []
    for path in unread[:100]:
        sender, subject, when = headers(path)
        rows.append(f"{when:>11}  {sender[:28]:<28}  {subject}")
    if not rows:
        rows = ["no unread mail: Enter opens aerc"]
    code, _ = rofi(rows, "<b>Enter</b> open aerc · <b>Alt+r</b> sync now")
    if code == 10:
        sync_now()
    elif code == 0:
        open_aerc()
    return 0


def cmd_click(args) -> int:
    if NEEDS_AUTH.exists():
        return cmd_signin(args)
    os.execvp("shell-popup", ["shell-popup", "mail", "--", self_bin(), "pick"])
    return 0


def run_authorize(flow: str, timeout: int) -> bool:
    account, argv = account_config()
    if not argv:
        notify("Mail sign-in failed", "No PassCmd found in ~/.mbsyncrc", "critical")
        return False
    options = next((i for i, a in enumerate(argv) if a.startswith("--")), len(argv))
    argv = [shutil.which("mutt-oauth2") or "mutt-oauth2"] + argv[options:]
    argv += ["--authorize", "--authflow", flow, "--email", account]
    proc = subprocess.Popen(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    lines: queue.Queue = queue.Queue()

    def reader() -> None:
        for line in proc.stdout:
            lines.put(line)

    threading.Thread(target=reader, daemon=True).start()
    deadline = time.time() + timeout
    prompted = False
    while time.time() < deadline and proc.poll() is None:
        try:
            line = lines.get(timeout=0.5)
        except queue.Empty:
            continue
        if prompted:
            continue
        if flow == "localhostauthcode" and line.startswith("https://"):
            subprocess.Popen(["xdg-open", line.strip()], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            notify("Sign in to Hotmail", "A Microsoft sign-in tab just opened in your browser.")
            prompted = True
        elif flow == "devicecode" and "code" in line:
            code = re.search(r"code ([A-Z0-9]{6,})", line)
            url = re.search(r"(https://\S+)", line)
            if code and url:
                subprocess.run(["wl-copy", code.group(1)], check=False)
                subprocess.Popen(["xdg-open", url.group(1)], start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                notify("Sign in to Hotmail", f"Code {code.group(1)} is in your clipboard: paste it on the page that opened.", "critical")
                prompted = True
    if proc.poll() is None:
        proc.kill()
        proc.wait()
        return False
    return proc.returncode == 0


def cmd_signin(args) -> int:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with SIGNIN_LOCK.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            notify("Mail sign-in already in progress")
            return 0
        ok = run_authorize("localhostauthcode", BROWSER_TIMEOUT)
        if not ok:
            notify("Trying another way to sign in", "The browser sign-in did not finish; switching to a one-time code.")
            ok = run_authorize("devicecode", DEVICE_TIMEOUT)
    if not ok:
        notify("Mail sign-in did not complete", "Click the mail icon to try again.", "critical")
        return 1
    NEEDS_AUTH.unlink(missing_ok=True)
    refresh_waybar()
    sync_now()
    notify("Hotmail connected", "Syncing your mail now.")
    return 0


def cmd_prompt(args) -> int:
    proc = subprocess.run(
        [
            "notify-send", "-a", "Mail", "-u", "critical", "-i", "mail-unread",
            "-A", "signin=Sign in",
            "Hotmail sign-in expired",
            "Mail stopped syncing. Click Sign in, or the mail icon in the bar.",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.stdout.strip() == "signin":
        return cmd_signin(args)
    return 0


def cmd_mark_needs_auth(args) -> int:
    if NEEDS_AUTH.exists():
        return 0
    RUNTIME.mkdir(parents=True, exist_ok=True)
    NEEDS_AUTH.touch()
    refresh_waybar()
    subprocess.run(
        ["systemd-run", "--user", "--collect", "--quiet", "--unit=mail-signin-prompt", self_bin(), "prompt"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return 0


def cmd_mark_synced(args) -> int:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    NEEDS_AUTH.unlink(missing_ok=True)
    LAST_SYNC.touch()
    refresh_waybar()
    return 0


def cmd_open(args) -> int:
    open_aerc()
    return 0


def cmd_sync(args) -> int:
    sync_now()
    return 0


def cmd_needs_auth(args) -> int:
    return 0 if NEEDS_AUTH.exists() else 1


def main() -> int:
    p = argparse.ArgumentParser(prog="mail-menu")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, func in (
        ("waybar", cmd_waybar),
        ("pick", cmd_pick),
        ("click", cmd_click),
        ("signin", cmd_signin),
        ("prompt", cmd_prompt),
        ("mark-needs-auth", cmd_mark_needs_auth),
        ("mark-synced", cmd_mark_synced),
        ("needs-auth", cmd_needs_auth),
        ("open", cmd_open),
        ("sync", cmd_sync),
    ):
        sub.add_parser(name).set_defaults(func=func)
    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
