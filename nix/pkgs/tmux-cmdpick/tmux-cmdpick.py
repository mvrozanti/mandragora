import argparse
import collections
import os
import re
import shlex
import json
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata

NON_SGR = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-ln-~]|\x1b[@-Z\\-_]")
SGR = re.compile(r"\x1b\[([0-9;:]*)m")
DEFAULT_SGR = {"", "0", "39", "49", "22", "23", "24", "27", "39;49", "0;39"}
QUIET_SGR = {"2", "3"}
BACKTICK = re.compile(r"`([^`\n]+)`")
DECORATION = re.compile(r"^[\s│┃┆┊|⎿⏺●•◦▪▸►*>+-]*(?:\d+[.)]\s+)?")
TRAILING_BOX = re.compile(r"\s*[│┃┆┊║]+\s*$")
GUTTER = re.compile(r"^\s*\d+\s+[+-]?\s?")
PROMPT = re.compile(r"^.{0,60}?(?:\$|%|#|❯|➜|λ|»|›)\s+(?=\S)")
PUA = re.compile(r"^.*[-\U000f0000-\U000fffff]\s*")
LABEL = re.compile(r"^.*?:\s+(?=\S)")
BOX = re.compile(r"[─-▟⎿⏺●…]")
HEREDOC = re.compile(r"<<-?\s*['\"]?\w")
SENTENCE_END = re.compile(r"[\w)\"'`][.:?!,]$")
TRAILING_PUNCT = re.compile(r"(.*[\w/~*\]}-])([.,;:!?\"'”’)]+)")
LEADING_PUNCT = "\"'“‘("
USER_NAME = re.compile(r"[A-Za-z@][\w.+@-]*")
DIFF_HEAD = re.compile(r"^(\s*\d+ )([ +-])")
DIFF_MARGIN = 16
HIGHLIGHTED_STYLES = 3
SUBCOMMAND = re.compile(r"[a-z][\w-]*")
INDENTED = re.compile(r"^ {2,4}\[?([a-z][\w-]*)\]?[:*]?(?=\s|$)")
TMUX_COMMAND = re.compile(r"^([a-z][\w-]*)(?: \(([\w-]+)\))?")
NIX_COMMAND = re.compile(r"^\s*\u00b7\s*nix ([a-z][\w-]*)")

CODE = "code"
LINE = "line"
PROMPTED = "prompted"
CUED = "cued"
EMBEDDED = "embedded"
DETERMINERS = {"a", "an", "the", "this", "that", "these", "those", "my", "your", "our", "their", "its", "his", "her", "each", "every", "no"}
SPACED_ASSIGNMENT = {"=", "==", "+=", "-=", ":=", "!="}
CUES = {"run", "rerun", "try", "type", "execute", "exec", "invoke", "enter", "paste", "$"}

OPERATORS = {"|", "||", "&&", ";", "&", "|&", ";;", "(", ")", "{", "}", "!", "&!", "&|"}
REDIRECTS = {">", ">>", "<", "<<", "<<<", ">&", "<&", "&>", "&>>", ">|", ">>|"}
LEADING_KEYWORDS = {"do", "then", "else", "elif", "{", "!"}
CLOSING_KEYWORDS = {"done", "fi", "esac", "}", "end", "]]"}
DANGLING_KEYWORDS = {"then", "else", "elif", "fi", "do", "done", "esac", "in", "end", "}", "]]", "-"}
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
BOUNDARY = STOPWORDS | {
    "first", "again", "then", "instead", "before", "after", "afterwards", "later",
    "manually", "yourself", "once", "if", "until", "while", "since", "because", "where",
    "whose", "e.g.", "i.e.", "see", "inside", "outside", "without",
}
VERBS = {
    "works", "worked", "fails", "failed", "runs", "ran", "hangs", "hung", "shows", "showed",
    "prints", "printed", "returns", "returned", "exits", "exited", "succeeds", "succeeded",
    "breaks", "broke", "crashes", "crashed", "helps", "helped", "does", "did", "finishes",
    "finished", "completes", "completed", "outputs", "says", "said", "reports", "reported",
    "gives", "gave", "lists", "listed", "needs", "needed", "requires", "required", "handles",
    "handled", "tells", "told", "fixes", "fixed", "solves", "solved",
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
    "convert", "display", "compare", "patch", "identify", "stream", "rename", "sync",
    "mount", "unlink", "column", "factor", "units", "locale", "logger", "shred", "animate",
    "montage", "composite", "sum", "diff", "nl", "od", "tr", "as", "at", "ln", "ex", "ed",
}

SUBCOMMAND_SOURCES = {
    "git": (("git", "--list-cmds=main,others,alias,nohelpers"), "lines"),
    "systemctl": (("systemctl", "--help"), "indented"),
    "loginctl": (("loginctl", "--help"), "indented"),
    "hostnamectl": (("hostnamectl", "--help"), "indented"),
    "timedatectl": (("timedatectl", "--help"), "indented"),
    "resolvectl": (("resolvectl", "--help"), "indented"),
    "networkctl": (("networkctl", "--help"), "indented"),
    "busctl": (("busctl", "--help"), "indented"),
    "coredumpctl": (("coredumpctl", "--help"), "indented"),
    "machinectl": (("machinectl", "--help"), "indented"),
    "bootctl": (("bootctl", "--help"), "indented"),
    "docker": (("docker", "--help"), "indented"),
    "podman": (("podman", "--help"), "indented"),
    "hyprctl": (("hyprctl", "--help"), "indented"),
    "cargo": (("cargo", "--list"), "indented"),
    "gh": (("gh", "--help"), "indented"),
    "kubectl": (("kubectl", "--help"), "indented"),
    "tmux": (("tmux", "list-commands"), "tmux"),
    "nix": (("nix", "--help"), "nix"),
}
STATIC_SUBCOMMANDS = {
    "nixos-rebuild": {
        "switch", "boot", "test", "build", "dry-build", "dry-run", "dry-activate", "edit",
        "repl", "build-vm", "build-vm-with-bootloader", "build-image", "list-generations",
    },
}
HELP_ENV = {"PAGER": "cat", "MANPAGER": "cat", "SYSTEMD_PAGER": "cat", "GIT_PAGER": "cat", "NO_COLOR": "1", "SYSTEMD_COLORS": "0"}

Names = collections.namedtuple("Names", "commands starters subs", defaults=(None,))


def cache_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "tmux-cmdpick", "names-v2")


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
            stdout=subprocess.PIPE,
            text=True,
            timeout=5,
        ).stdout
    except (subprocess.SubprocessError, OSError):
        return set()
    return {n for n in out.split("\n") if re.fullmatch(r"[\w.+:@/-]+|\[\[|\[|!|\{|\}", n)}


def user_shell_names():
    path = cache_path()
    try:
        if time.time() - os.path.getmtime(path) < 86400:
            with open(path) as f:
                return set(f.read().split())
    except OSError:
        pass
    names = {n for n in zsh_names(True) if USER_NAME.fullmatch(n)}
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


def parse_subcommands(kind, text):
    found = set()
    for line in text.splitlines():
        if kind == "lines":
            if SUBCOMMAND.fullmatch(line.strip()):
                found.add(line.strip())
            continue
        rx = {"indented": INDENTED, "tmux": TMUX_COMMAND, "nix": NIX_COMMAND}[kind]
        m = rx.match(line)
        if m:
            found.update(g for g in m.groups() if g)
    return found


def probe_subcommands(executables):
    env = dict(os.environ, **HELP_ENV)
    running = {}
    for tool, (argv, kind) in SUBCOMMAND_SOURCES.items():
        if tool not in executables:
            continue
        try:
            running[tool] = (subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env), kind)
        except OSError:
            continue
    table = {t: set(v) for t, v in STATIC_SUBCOMMANDS.items() if t in executables}
    for tool, (proc, kind) in running.items():
        try:
            out, _ = proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            continue
        names = parse_subcommands(kind, out)
        if names:
            table[tool] = names
    return table


def subcommand_table(executables):
    path = os.path.join(os.path.dirname(cache_path()), "subcommands-v1.json")
    try:
        if time.time() - os.path.getmtime(path) < 86400:
            with open(path) as f:
                return {t: frozenset(v) for t, v in json.load(f).items()}
    except (OSError, ValueError):
        pass
    table = probe_subcommands(executables)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({t: sorted(v) for t, v in table.items()}, f)
    os.replace(tmp, path)
    return {t: frozenset(v) for t, v in table.items()}


def load_names():
    executables = path_names()
    return Names(executables | zsh_names(False) | user_shell_names(), executables, subcommand_table(executables))


def display_width(text):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def wraps(line, following, width):
    line = line.rstrip()
    words = following.split()
    if not line.strip() or not words:
        return False
    used = display_width(line)
    return used <= width < used + 1 + display_width(words[0])


def clean(line):
    return SGR.sub("", line)


def styled_spans(line):
    styles = {p for p in SGR.findall(line) if p not in DEFAULT_SGR and not QUIET_SGR & set(re.split("[;:]", p))}
    if len(styles) >= HIGHLIGHTED_STYLES:
        return []
    spans = []
    state = ""
    buf = []
    pos = 0
    for m in SGR.finditer(line):
        if state:
            buf.append(line[pos:m.start()])
        params = m.group(1)
        quiet = bool(QUIET_SGR & set(re.split("[;:]", params)))
        new = "" if params in DEFAULT_SGR or quiet else params
        if new != state:
            if buf:
                spans.append("".join(buf))
            buf = []
            state = new
        pos = m.end()
    if state:
        buf.append(line[pos:])
    if buf:
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
    base = TRAILING_BOX.sub("", text).strip()
    deco = DECORATION.sub("", base).strip()
    variants = [(base, False), (deco, False)]
    for rx in (GUTTER, PROMPT, PUA, LABEL):
        for v in (base, deco):
            stripped = rx.sub("", v, count=1).strip()
            if stripped != v:
                variants.append((stripped, rx in (PROMPT, PUA)))
    return list(dict.fromkeys(variants))


def embedded_commands(text, starters):
    words = text.split()
    out = []
    for i, w in enumerate(words):
        lead = w.lstrip(LEADING_PUNCT)
        m = TRAILING_PUNCT.fullmatch(lead)
        core = m.group(1) if m else lead
        if len(core) < 2 or not core[0].islower() or core not in starters:
            continue
        if core in ENGLISH_COLLIDERS or core.lower() in STOPWORDS:
            continue
        if sum(x.count('"') + x.count("`") for x in words[:i]) % 2:
            continue
        prev = words[i - 1].strip(LEADING_PUNCT + ":,").lower() if i else ""
        if prev in DETERMINERS:
            continue
        cued = prev in CUES
        at_start = not DECORATION.sub("", " ".join(words[:i])).strip()
        parts = []
        alternative = None
        for j in range(i, len(words)):
            tok = lead if j == i else words[j]
            m = TRAILING_PUNCT.fullmatch(tok)
            bare = m.group(1) if m else tok
            if j > i and bare.lower() in BOUNDARY:
                break
            if j > i and bare.lower() in VERBS:
                alternative = parts + [bare]
                break
            parts.append(bare)
            if m:
                break
        out.append((" ".join(parts), cued, at_start, True))
        if alternative:
            out.append((" ".join(alternative), cued, at_start, False))
    return out


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
        if t.isdigit() and i + 1 < len(seg) and seg[i + 1] in REDIRECTS:
            i += 3
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
        return t, wrapper, i
    return None, wrapper, len(seg)


def subcommand_verdict(seg, index, word, subs):
    table = subs.get(word)
    if not table or index + 1 >= len(seg) or not SUBCOMMAND.fullmatch(seg[index + 1]):
        return None
    return seg[index + 1] in table


def resolves(word, commands, cwd):
    if len(word) > 1 and word[0] in "$`":
        return True
    if "/" in word:
        p = os.path.expanduser(word)
        if not os.path.isabs(p):
            p = os.path.join(cwd, p)
        return os.path.isfile(p) and os.access(p, os.X_OK)
    return word in commands


def structural(cmd, tokens):
    if any(t in OPERATORS - {"(", ")"} or t in REDIRECTS for t in tokens):
        return True
    return any(c in cmd for c in "'\"$=`")


def strong_signal(cmd, tokens):
    if structural(cmd, tokens) or any(c in cmd for c in "~*"):
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


def judge(cmd, names, cwd, kind, tail_verb=False):
    if len(cmd) < 2 or len(cmd) > 600 or BOX.search(cmd) or HEREDOC.search(cmd):
        return False
    try:
        tokens = tokenize(cmd)
    except ValueError:
        return False
    if not tokens or tokens[0] in DANGLING_KEYWORDS or tokens[0] in REDIRECTS or tokens[0].startswith("`"):
        return False
    if len(tokens) > 1 and tokens[1] in SPACED_ASSIGNMENT:
        return False
    if tokens[0].lower() in STOPWORDS and tokens[0] not in COMPOUND_START:
        return False
    if len(tokens) == 1 and (kind != PROMPTED or len(tokens[0]) <= 2 or tokens[0][0] in "$`" or tokens[0] in COMPOUND_START or tokens[0] in ENGLISH_COLLIDERS):
        return False
    first = None
    resolved = 0
    verified = False
    subs = names.subs or {}
    for seg in segments(tokens):
        word, wrapper, index = command_word(seg)
        if word is None:
            if wrapper is None:
                continue
            if not all(t.startswith("-") for t in seg[1:]):
                return False
            word = wrapper
        if first is None:
            first = word
        if word in COMPOUND_START or (word in CLOSING_KEYWORDS and first != word):
            continue
        if not resolves(word, names.commands, cwd):
            return False
        verdict = subcommand_verdict(seg, index, word, subs)
        if verdict is False:
            return False
        verified = verified or bool(verdict)
        resolved += 1
    if first is None or not resolved:
        return False
    if kind == EMBEDDED and not (verified or strong_signal(cmd, tokens)):
        return False
    collider = first in ENGLISH_COLLIDERS
    signal = has_signal(cmd, tokens, cwd, collider)
    if collider and len(tokens) > 1 and not signal:
        return False
    if is_prose(tokens) and not (signal and kind == CODE):
        return False
    if kind == CODE:
        return True
    if SENTENCE_END.search(cmd):
        return False
    tail = tokens[1:-1] if tail_verb else tokens[1:]
    if not structural(cmd, tokens) and any(t.lower() in BOUNDARY or t.lower() in VERBS for t in tail):
        return False
    return signal or (len(tokens) <= 6 and not collider)


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


def inline(span, text):
    rest = GUTTER.sub("", DECORATION.sub("", text.replace(span, " ", 1)))
    return len(re.findall(r"[A-Za-z]", rest)) >= 3


def line_candidates(raw, text, names, cwd):
    pool = [(v, PROMPTED if prompted else LINE) for v, prompted in line_variants(text)]
    pool += [(span.strip(), CODE) for span in BACKTICK.findall(text)]
    for span in styled_spans(raw):
        kind = CODE if inline(span, text) else LINE
        pool.append((span, kind))
        pool += [(v, kind) for v, _ in line_variants(span)]
    accepted = {}
    for cand, kind in pool:
        cand = re.sub(r"\s+", " ", cand).strip()
        if cand and cand not in accepted and judge(cand, names, cwd, kind):
            accepted[cand] = True
    if accepted:
        return list(accepted.items())
    for cand, cued, at_start, reading in embedded_commands(text, names.starters):
        if accepted.get(cand) or not judge(cand, names, cwd, CUED if cued else EMBEDDED, not reading):
            continue
        accepted[cand] = reading and (cued or at_start or strong_signal(cand, tokenize(cand)))
    return list(accepted.items())


def continuation(head, previous, line, width):
    if head:
        col = len(head.group(1))
        body = line[col + 1:]
        if display_width(previous.rstrip()) >= width - DIFF_MARGIN and not line[:col].strip() and line[col:col + 1] == head.group(2) and body.strip():
            return body.rstrip(), ""
        return None
    if wraps(previous, line, width):
        return line.strip(), " "
    return None


def units_of(lines, width):
    units = [([i], raw, text) for i, (raw, text) in enumerate(lines)]
    if not width:
        return units
    i = 0
    while i < len(lines):
        head = DIFF_HEAD.match(lines[i][1])
        members, raw, text = [i], lines[i][0], lines[i][1].rstrip()
        j = i + 1
        while j < len(lines):
            step = continuation(head, lines[j - 1][1], lines[j][1], width)
            if step is None:
                break
            body, sep = step
            members.append(j)
            raw += sep + (body if head else lines[j][0])
            text += sep + body
            j += 1
        if len(members) > 1:
            units.append((members, raw, text))
        i = j
    return units


def extract(raw_text, cwd, names=None, width=None):
    names = names or load_names()
    lines = logical_lines(NON_SGR.sub("", raw_text).split("\n"))
    per_unit = [(members, line_candidates(raw, text, names, cwd)) for members, raw, text in units_of(lines, width)]
    joined = collections.defaultdict(list)
    for members, cands in per_unit:
        if len(members) > 1:
            for k in members:
                joined[k] += [c for c, _ in cands]
    found = {}
    seq = 0
    for members, cands in per_unit:
        pos = members[-1] + (0.5 if len(members) > 1 else 0)
        for cand, sure in cands:
            if len(members) == 1 and any(cand != m and cand in m for m in joined[members[0]]):
                continue
            seq += 1
            if cand not in found or (sure, pos, seq) > found[cand]:
                found[cand] = (sure, pos, seq)
    ranked = sorted(found, key=lambda c: found[c], reverse=True)
    return [(c, found[c][0]) for c, ok in zip(ranked, parses(ranked)) if ok]


def fzf_line(cand, sure):
    return cand if sure else cand + "\t?"


def chosen_command(line):
    return line.split("\t", 1)[0]


def tmux(*args, data=None):
    return subprocess.run(["tmux", *args], input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout


def capture(pane, lines):
    return tmux("capture-pane", "-p", "-J", "-e", "-t", pane, "-S", "-%d" % lines)


def notify(client, text):
    target = ["-c", client] if client else []
    tmux("display-message", *target, "-d", "1500", text)


def open_popup(cands, pane, client):
    fd, path = tempfile.mkstemp(prefix="tmux-cmdpick-", suffix=".json", dir=os.environ.get("XDG_RUNTIME_DIR") or None)
    with os.fdopen(fd, "w") as f:
        json.dump(cands, f)
    picker = shlex.join([sys.executable, os.path.abspath(sys.argv[0]), "--pick-file", path, pane])
    target = ["-c", client] if client else []
    opened = subprocess.run(["tmux", "display-popup", *target, "-E", "-w", "90%", "-h", "50%", picker], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if opened.returncode != 0 and os.path.exists(path):
        os.unlink(path)


def pick(cands):
    header = "enter copy · tab multi · ? ambiguous reading"
    fzf = subprocess.run(
        ["fzf", "--multi", "--no-sort", "--layout=reverse", "--prompt=cmd> ", "--header=" + header, "--expect=alt-enter", "--delimiter=\t", "--nth=1"],
        input="\n".join(fzf_line(c, sure) for c, sure in cands),
        stdout=subprocess.PIPE,
        text=True,
    )
    lines = fzf.stdout.rstrip("\n").split("\n")
    if fzf.returncode != 0 or len(lines) < 2:
        return
    chosen = [chosen_command(line) for line in lines[1:]]
    text = "\n".join(chosen)
    tmux("load-buffer", "-", data=text)
    if shutil.which("wl-copy"):
        subprocess.run(["wl-copy", "--", text], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    more = " (+%d)" % (len(chosen) - 1) if len(chosen) > 1 else ""
    tmux("display-message", "-d", "1500", "copied: " + chosen[0][:80] + more)


def main():
    ap = argparse.ArgumentParser(prog="tmux-cmdpick")
    ap.add_argument("pane", nargs="?", default="")
    ap.add_argument("--lines", type=int, default=2000)
    ap.add_argument("--print", action="store_true", dest="print_only")
    ap.add_argument("--stdin", action="store_true")
    ap.add_argument("--width", type=int)
    ap.add_argument("--popup", action="store_true")
    ap.add_argument("--client", default="")
    ap.add_argument("--pick-file")
    args = ap.parse_args()
    if args.pick_file:
        with open(args.pick_file) as f:
            cands = [(c, sure) for c, sure in json.load(f)]
        os.unlink(args.pick_file)
        pick(cands)
        return
    cwd = os.getcwd()
    width = args.width
    if args.stdin:
        text = sys.stdin.read()
    else:
        target = ["-t", args.pane] if args.pane else []
        info = tmux("display-message", "-p", *target, "#{pane_id}\t#{pane_width}\t#{pane_current_path}").rstrip("\n").split("\t")
        if len(info) != 3 or not info[0]:
            message = "tmux-cmdpick: no tmux pane %s" % (args.pane or "to read (not inside tmux?)")
            if args.popup:
                notify(args.client, message)
            sys.exit(message)
        args.pane = info[0]
        width = width or int(info[1])
        cwd = info[2] or cwd
        text = capture(args.pane, args.lines)
    cands = extract(text, cwd, width=width)
    if args.print_only:
        print("\n".join(fzf_line(c, sure) for c, sure in cands))
        return
    if not cands:
        notify(args.client, "tmux-cmdpick: no shell commands in pane")
        return
    if args.popup:
        open_popup(cands, args.pane, args.client)
        return
    pick(cands)


if __name__ == "__main__":
    main()
