import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

ANSI = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[@-Z\\-_]")


def tmux(*args, data=None):
    return subprocess.run(["tmux", *args], input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout


def capture(pane, lines):
    return tmux("capture-pane", "-p", "-J", "-e", "-t", pane, "-S", "-%d" % lines)


def pathlike(word):
    return "/" in word or word == "~" or word.startswith(("~", ".", "$"))


def extract_dirs(text, cwd):
    found = {}
    order = 0
    for line in ANSI.sub("", text).splitlines():
        for word in line.split():
            w = word.strip("\"'`()[],;:<>")
            if not w or not pathlike(w):
                continue
            p = os.path.normpath(os.path.expanduser(os.path.expandvars(w)))
            if not os.path.isabs(p):
                p = os.path.normpath(os.path.join(cwd, p))
            if os.path.isdir(p) and p not in found:
                found[p] = order
                order += 1
    return sorted(found, key=lambda p: found[p], reverse=True)


def open_popup(dirs, client, pane):
    fd, path = tempfile.mkstemp(prefix="tmux-dirpick-", suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(dirs, f)
    picker = shlex.join([sys.executable, os.path.abspath(sys.argv[0]), "--pick-file", path, pane])
    target = ["-c", client] if client else []
    subprocess.run(
        ["tmux", "display-popup", *target, "-E", "-w", "90%", "-h", "50%", picker],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def pick(dirs, pane):
    fzf = subprocess.run(
        ["fzf", "--no-sort", "--layout=reverse", "--prompt=dir> "],
        input="\n".join(dirs),
        stdout=subprocess.PIPE,
        text=True,
    )
    if fzf.returncode != 0:
        return
    chosen = fzf.stdout.rstrip("\n")
    if not chosen:
        return
    args = ["split-window"]
    if pane:
        args += ["-t", pane]
    args += ["-c", chosen, "yazi"]
    tmux(*args)


def main():
    ap = argparse.ArgumentParser(prog="tmux-dirpick")
    ap.add_argument("pane", nargs="?", default="")
    ap.add_argument("--lines", type=int, default=2000)
    ap.add_argument("--print", action="store_true")
    ap.add_argument("--stdin", action="store_true")
    ap.add_argument("--popup", action="store_true")
    ap.add_argument("--client", default="")
    ap.add_argument("--pick-file")
    args = ap.parse_args()

    if args.pick_file:
        with open(args.pick_file) as f:
            dirs = json.load(f)
        os.unlink(args.pick_file)
        pick(dirs, args.pane)
        return

    cwd = os.getcwd()
    if args.stdin:
        text = sys.stdin.read()
    else:
        if not args.pane:
            sys.exit("tmux-dirpick: no tmux pane to read")
        cwd = tmux("display-message", "-p", "-t", args.pane, "#{pane_current_path}").strip() or cwd
        text = capture(args.pane, args.lines)

    dirs = extract_dirs(text, cwd)
    if args.print:
        print("\n".join(dirs))
        return
    if not dirs:
        tmux("display-message", "-d", "1500", "tmux-dirpick: no directories in pane")
        return
    if args.popup:
        open_popup(dirs, args.client, args.pane)
        return
    pick(dirs, args.pane)


if __name__ == "__main__":
    main()
