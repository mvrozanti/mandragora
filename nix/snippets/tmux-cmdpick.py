import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

NON_SGR = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-ln-~]|\x1b[@-Z\\-_]")
SGR = re.compile(r"\x1b\[([0-9;:]*)m")
DEFAULT_SGR = {"", "0", "39", "49", "22", "23", "24", "27", "39;49", "0;39"}
BACKTICK = re.compile(r"`([^`\n]+)`")
DECORATION = re.compile(r"^[\s│┃┆┊|⎿⏺●•◦▪▸►*>+-]*(?:\d+[.)]\s+)?")
GUTTER = re.compile(r"^\s*\d+\s+[+-]?\s?")
PROMPT = re.compile(r"^.{0,60}?(?:\$|%|#|❯|➜|λ|»|›)\s+(?=\S)")
PUA = re.compile(r"^.*[-\U000f0000-\U000fffff]\s*")
LABEL = re.compile(r"^.*?:\s+(?=\S)")
BOX = re.compile(r"[─-▟⎿⏺●]")

OPERATORS = {"|", "||", "&&", ";", "&", "|&", ";;", "(", ")", "{", "}", "!", "&!", "&|"}
REDIRECTS = {">", ">>", "<", "<<", "<<<", ">&", "<&", "&>", "&>>", ">|", ">>|"}
LEADING_KEYWORDS = {"do", "then", "else", "elif", "{", "!"}
CLOSING_KEYWORDS = {"done", "fi", "esac", "}", "end", "]]"}
COMPOUND_START = {"if", "for", "while", "until", "case", "select", "function", "repeat", "foreach", "[[", "time", "coproc", "!"}
WRAPPERS = {
    "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U"},
    "doas": {"-u", "-C"},
    "run0": {"-u", "--user", "-g", "--group"},
    "env": {"-u", "-C", "-S"},
    "command": set(),
    "builtin": set(),
    "exec": {"-a"},
    "noglob": set(),
    "nocorrect": set(),
    "nohup": set(),
    "nice": {"-n"},
    "ionice": {"-c", "-n", "-p"},
    "timeout": {"-s", "-k"},
    "stdbuf": set(),
    "unbuffer": set(),
    "setsid": set(),
    "xargs": {"-I", "-n", "-P", "-d", "-L", "-s", "-E", "-a"},
    "watch": {"-n", "-d"},
    "cage": set(),
    "rtk": set(),
    "chronic": set(),
    "pkexec": {"--user"},
    "strace": {"-e", "-o", "-p", "-s"},
    "gdb": set(),
    "valgrind": set(),
}
STOPWORDS = {
    "the", "a", "an", "to", "is", "are", "was", "were", "of", "and", "or", "you", "your",
    "this", "that", "it", "its", "for", "with", "on", "at", "be", "we", "i", "but", "not",
    "will", "can", "should", "would", "so", "as", "by", "from", "into", "what", "which",
    "when", "how", "why", "just", "also", "now", "here", "there", "all", "any", "some",
    "my", "me", "our", "has", "have", "had", "been", "they", "them", "than", "too", "very",
}
ENGLISH_COLLIDERS = {
    "a", "test", "time", "which", "file", "find", "sort", "look", "watch", "yes", "man",
    "more", "less", "last", "top", "kill", "join", "split", "paste", "cut", "touch", "sleep",
    "wait", "read", "type", "print", "say", "help", "see", "open", "run", "set", "unset",
    "source", "stat", "link", "write", "wall", "w", "cal", "date", "id", "groups", "users",
    "who", "true", "false", "eval", "exit", "fold", "head", "tail", "expand", "pr", "tee",
    "script", "dig", "host", "pass", "shift", "trap", "times", "history", "hash", "local",
    "export", "hold", "note", "size", "free", "clear", "reset", "make", "info", "echo", "up",
    "go", "fix", "check", "build", "update", "install", "remove", "status", "list", "show",
    "start", "stop", "next", "back", "view", "tree", "let", "return", "break", "continue",
    "where", "limit", "enable", "disable", "alias", "logout", "jobs", "wc", "ok",
    "import", "from", "do", "done", "then", "else", "end", "new", "add", "get", "put",
}
SENTENCE_END = (".", ":", "?", "!", ",", ";")
HEREDOC = re.compile(r"<<-?\s*['\"]?\w")
QUIET_SGR = {"2", "3"}
USER_NAME = re.compile(r"[a-z][\w.-]{2,}")


def cache_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "tmux-cmdpick", "names")


def zsh_names(interactive):
    zsh = shutil.which("zsh")
    if not zsh:
        return set()
    flag = "-ic" if interactive else "-fc"
    script = "print -rl -- ${(k)builtins} ${(k)reswords} ${(k)aliases} ${(k)functions}"
    try:
        out = subprocess.run(
            [zsh, flag, script],
            stdin=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            capture_output=False,
            stdout=subprocess.PIPE,
            text=True,
            timeout=5,
        ).stdout
    except (subprocess.SubprocessError, OSError):
        return set()
    return {n for n in out.split("\n") if re.fullmatch(r"[\w.+:@-]+|\[\[|\[|!|\{|\}", n)}


def user_shell_names():
    path = cache_path()
    try:
        if time.time() - os.path.getmtime(path) < 86400:
            with open(path) as f:
                return set(f.read().split())
    except OSError:
        pass
    names = {n for n in zsh_names(True) if USER_NAME.fullmatch(n) and n not in STOPWORDS}
    if names:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            f.write("\n".join(sorted(names)))
        os.replace(tmp, path)
    return names


def path_names():
    names = set()
    for d in os.environ.get("PATH", "").split(":"):
        try:
            with os.scandir(d) as it:
                for e in it:
                    names.add(e.name)
        except OSError:
            continue
    return names


def known_names():
    return path_names() | zsh_names(False) | user_shell_names()


def clean(line):
    return SGR.sub("", line)


def styled_spans(line):
    spans = []
    state = ""
    buf = []
    pos = 0
    for m in SGR.finditer(line):
        if m.start() > pos:
            buf.append(line[pos:m.start()])
        params = m.group(1)
        quiet = bool(QUIET_SGR & set(re.split("[;:]", params)))
        new = "" if params in DEFAULT_SGR or quiet else params
        if new != state:
            if state and buf:
                spans.append("".join(buf))
            buf = []
            state = new
        pos = m.end()
    if state and pos < len(line):
        buf.append(line[pos:])
        spans.append("".join(buf))
    return [s.strip() for s in spans if s.strip()]


def logical_lines(raw_lines):
    out = []
    pending = None
    for raw in raw_lines:
        text = clean(raw).rstrip()
        if pending is not None:
            text = pending + " " + text.strip()
            pending = None
        if text.endswith(" \\") or text.endswith("\t\\"):
            pending = text[:-1].rstrip()
            continue
        out.append((raw, text))
    if pending is not None:
        out.append((pending, pending))
    return out


def line_variants(text):
    base = text.strip()
    deco = DECORATION.sub("", base).strip()
    variants = {base, deco}
    for rx in (GUTTER, PROMPT, PUA, LABEL):
        for v in (base, deco):
            stripped = rx.sub("", v, count=1).strip()
            if stripped != v:
                variants.add(stripped)
    return variants


def tokenize(cmd):
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segments(tokens):
    seg = []
    for t in tokens:
        if t in OPERATORS:
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def command_word(seg):
    i = 0
    wrapper = None
    while i < len(seg):
        t = seg[i]
        if t in REDIRECTS or re.fullmatch(r"\d*[<>]+&?", t):
            i += 2
            continue
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=.*", t):
            i += 1
            continue
        if wrapper is not None:
            if t.startswith("-") and len(t) > 1:
                i += 2 if t in WRAPPERS[wrapper] else 1
                continue
            if re.fullmatch(r"\d+(\.\d+)?[smhd]?", t):
                i += 1
                continue
        if wrapper is None and t in LEADING_KEYWORDS:
            i += 1
            continue
        if t in WRAPPERS:
            wrapper = t
            i += 1
            continue
        return t, wrapper
    return None, wrapper


def resolves(word, known, cwd):
    if len(word) > 1 and word[0] in "$`":
        return True
    if "/" in word:
        p = os.path.expanduser(word)
        if not os.path.isabs(p):
            p = os.path.join(cwd, p)
        return os.path.isfile(p) and os.access(p, os.X_OK)
    return word in known


def strong_signal(cmd, tokens):
    if any(t in OPERATORS - {"(", ")"} or t in REDIRECTS for t in tokens):
        return True
    if any(c in cmd for c in "'\"$~*="):
        return True
    return any(len(t) > 1 and t.startswith("-") for t in tokens[1:])


def path_exists(token, cwd):
    p = os.path.expanduser(token)
    return os.path.exists(p if os.path.isabs(p) else os.path.join(cwd, p))


def has_signal(cmd, tokens, cwd, strict):
    if strong_signal(cmd, tokens):
        return True
    for t in tokens[1:]:
        if "/" in t or re.search(r"\w\.\w", t):
            if not strict or path_exists(t, cwd):
                return True
        if re.fullmatch(r"[\w.-]+@[\w.-]+(:\S*)?", t):
            return True
    return False


def is_prose(tokens):
    if len(tokens) < 4:
        return False
    words = [t.rstrip(",.") for t in tokens if re.fullmatch(r"[A-Za-z']+[,.]?", t)]
    stops = sum(1 for w in words if w.lower() in STOPWORDS)
    commas = sum(1 for t in tokens[:-1] if re.fullmatch(r"[A-Za-z']+,", t))
    ratio = stops / len(tokens)
    return ratio >= 0.25 or (len(tokens) >= 8 and ratio >= 0.12) or (commas and len(tokens) >= 6)


def judge(cmd, known, cwd, from_code):
    if len(cmd) < 2 or len(cmd) > 600 or BOX.search(cmd) or HEREDOC.search(cmd):
        return False
    try:
        tokens = tokenize(cmd)
    except ValueError:
        return False
    if not tokens or (tokens[0].lower() in STOPWORDS and tokens[0] not in COMPOUND_START):
        return False
    if len(tokens) == 1 and (len(tokens[0]) <= 2 or tokens[0] in COMPOUND_START or tokens[0] in ENGLISH_COLLIDERS):
        return False
    first_seen = None
    resolved = 0
    for seg in segments(tokens):
        word, wrapper = command_word(seg)
        if word is None:
            if wrapper is not None:
                word = wrapper
            else:
                continue
        if first_seen is None:
            first_seen = word
        if word in COMPOUND_START or (word in CLOSING_KEYWORDS and first_seen != word):
            continue
        if not resolves(word, known, cwd):
            return False
        resolved += 1
    if first_seen is None or not resolved:
        return False
    if tokens[0] in {"then", "else", "elif", "fi", "do", "done", "esac", "in", "end", "}", "]]"}:
        return False
    signal = has_signal(cmd, tokens, cwd, first_seen in ENGLISH_COLLIDERS)
    if first_seen in ENGLISH_COLLIDERS and len(tokens) > 1 and not signal:
        return False
    if is_prose(tokens) and not (signal and from_code):
        return False
    if from_code:
        return True
    if signal:
        return not cmd.endswith(SENTENCE_END) or cmd.endswith(";")
    return len(tokens) <= 3 and first_seen not in ENGLISH_COLLIDERS and not cmd.endswith(SENTENCE_END)


def parses(cands):
    zsh = shutil.which("zsh")
    if not zsh or not cands:
        return [True] * len(cands)
    script = 'while IFS= read -r -d "" c; do unfunction __p 2>/dev/null; functions[__p]=$c 2>/dev/null; print -n -- $(( $+functions[__p] )); done'
    payload = "".join(c.replace("\0", "") + "\0" for c in cands)
    try:
        out = subprocess.run([zsh, "-fc", script], input=payload, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=10).stdout
    except (subprocess.SubprocessError, OSError):
        return [True] * len(cands)
    if len(out) != len(cands):
        return [True] * len(cands)
    return [ch == "1" for ch in out]


def extract(raw_text, cwd):
    known = known_names()
    raw_text = NON_SGR.sub("", raw_text)
    found = {}
    order = 0
    for raw, text in logical_lines(raw_text.split("\n")):
        pool = []
        for v in line_variants(text):
            pool.append((v, False))
        for span in BACKTICK.findall(text):
            pool.append((span.strip(), True))
        for span in styled_spans(raw):
            pool.append((span, True))
            for v in line_variants(span):
                pool.append((v, True))
        for cand, from_code in pool:
            cand = re.sub(r"\s+", " ", cand).strip()
            if cand and judge(cand, known, cwd, from_code):
                order += 1
                found[cand] = order
    ranked = sorted(found, key=lambda c: found[c], reverse=True)
    return [c for c, ok in zip(ranked, parses(ranked)) if ok]


def tmux(*args, data=None):
    return subprocess.run(["tmux", *args], input=data, stdout=subprocess.PIPE, text=True).stdout


def capture(pane, lines):
    return tmux("capture-pane", "-p", "-J", "-e", "-t", pane, "-S", "-%d" % lines)


def pick(cands, pane):
    header = "enter copy · alt-enter insert into pane · tab multi"
    fzf = subprocess.run(
        ["fzf", "--multi", "--no-sort", "--layout=reverse", "--prompt=cmd> ", "--header=" + header, "--expect=alt-enter"],
        input="\n".join(cands),
        stdout=subprocess.PIPE,
        text=True,
    )
    lines = fzf.stdout.rstrip("\n").split("\n")
    if fzf.returncode != 0 or len(lines) < 2:
        return
    key, chosen = lines[0], lines[1:]
    text = "\n".join(chosen)
    if key == "alt-enter":
        tmux("send-keys", "-t", pane, "-l", "--", text)
        return
    tmux("load-buffer", "-", data=text)
    if shutil.which("wl-copy"):
        subprocess.run(["wl-copy", "--", text])
    tmux("display-message", "-d", "1500", "copied: " + chosen[0][:80] + (" (+%d)" % (len(chosen) - 1) if len(chosen) > 1 else ""))


def main():
    ap = argparse.ArgumentParser(prog="tmux-cmdpick")
    ap.add_argument("pane", nargs="?", default=os.environ.get("TMUX_PANE", ""))
    ap.add_argument("--lines", type=int, default=2000)
    ap.add_argument("--print", action="store_true", dest="print_only")
    ap.add_argument("--stdin", action="store_true")
    args = ap.parse_args()
    cwd = os.getcwd()
    if args.stdin:
        text = sys.stdin.read()
    else:
        if not args.pane:
            sys.exit("tmux-cmdpick: no pane given and not inside tmux")
        cwd = tmux("display-message", "-p", "-t", args.pane, "#{pane_current_path}").strip() or cwd
        text = capture(args.pane, args.lines)
    cands = extract(text, cwd)
    if args.print_only:
        print("\n".join(cands))
        return
    if not cands:
        tmux("display-message", "-d", "1500", "tmux-cmdpick: no shell commands in pane")
        return
    pick(cands, args.pane)


if __name__ == "__main__":
    main()
