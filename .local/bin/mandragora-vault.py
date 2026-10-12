import argparse
import datetime
import difflib
import fcntl
import io
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

VAULT = os.path.realpath(os.path.expanduser(os.environ.get("MANDRAGORA_VAULT", "~/Documents/mandragora-desktop-obsidian-vault")))
FLAKE = os.environ.get("MANDRAGORA_FLAKE", "/etc/nixos/mandragora")
SECRET_PATTERNS = os.environ.get("MANDRAGORA_SECRET_PATTERNS", "@secretPatterns@")
DEPLOY = os.path.expanduser(os.environ.get("MANDRAGORA_VAULT_DEPLOY", os.path.join(FLAKE, "nix/hosts/mandragora-vps/compose/demo/publish-vault.sh")))
STATE = os.path.join(os.path.expanduser(os.environ.get("XDG_STATE_HOME") or "~/.local/state"), "mandragora-vault")
REVIEW_MODEL = os.environ.get("MANDRAGORA_VAULT_REVIEW_MODEL", "claude-haiku-4-5")
SITE_PROBE = os.environ.get("MANDRAGORA_VAULT_PROBE", "https://demo.mvr.ac/vault/_Home.md")
PUBLISHED = "refs/heads/published"
LEDGER = ".sync-ledger"
BASELINE = ".sync-state"
DOCS = "/etc/nixos/mandragora/docs/vault.md"
AGENT_MARKERS = ("MANDRAGORA_AGENT", "AI_AGENT", "CLAUDECODE", "GEMINI_CLI")

CATEGORIES = {
    "agents": "agent",
    "atlas": "moc",
    "concepts": "concept",
    "decisions": "decision",
    "eras": "era",
    "features": "feature",
    "hosts": "host",
    "incidents": "incident",
    "modules": "module",
    "principles": "principle",
    "programs": "program",
    "services": "service",
}
NEW_NOTE_CATEGORIES = sorted(set(CATEGORIES) - {"atlas", "eras"})
CURRENT_ERA = "multi-host"

BAD_NAME = re.compile(r'[#^\[\]|\\/:*?"<>]')
WIKILINK = re.compile(r"\[\[([^\]|#^]+)")
FENCE = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`[^`\n]*`")
CODE = re.compile(r"(```.*?```|`[^`\n]*`)", re.S)
FULL_LINK = re.compile(r"\[\[(.+?)\]\](?!\])")
VAULT_LINE = re.compile(r"^[ \t]*vault:[ \t]*(.+?)[ \t]*$", re.I | re.M)
EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b")
EMAIL_ALLOWED = re.compile(r"^(git@|noreply@|.*@users\.noreply\.github\.com$|.*@example\.(com|org|net)$)", re.I)
IPV4 = re.compile(r"(?<![\d.])(\d{1,3}(?:\.\d{1,3}){3})(?!\d|\.\d|/\d)")
TAILNET = ipaddress.ip_network("100.64.0.0/10")
LAN_RANGES = [ipaddress.ip_network(n) for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]
GENERIC_LAST_OCTETS = {"0", "1", "255"}
CONVENTIONAL = re.compile(r"^(docs|chore|fix|refactor)(\([a-z0-9_./ -]+\))?!?: \S")
LEDGER_LINE = re.compile(r"^[0-9a-f]{40}\t(note|none)\t\S.*$")
SKIP_SUBJECTS = ("Merge ", 'Revert "', "fixup!", "squash!", "amend!")
SCISSORS = "# ------------------------ >8 ------------------------"

SHRINK_FLOOR = 8
SHRINK_RATIO = 0.25
SIMILAR_LINE = 0.6
NEW_NOTE_MAX_LINES = 400
GROWTH_MAX_LINES = 400
MIN_BODY_LINES = 3
NOTE_RECENT_DAYS = 14
CHUNK_CHARS = 60000
REVIEW_TIMEOUT = 240

REVIEW_PROMPT = """You review text that is about to be published on a public website indexed by search engines: additions to a personal engineering knowledge vault. The owner is the person behind the public handle "mvrozanti" and the domain mvr.ac; that handle, that domain and its subdomains may appear freely.

Hold any added text that contains:
- a credential or any fragment of one: password, token, API key, private key, cookie, session id, connection string, bot id, a value from a .env file - even partial, even if described as revoked
- personal data about anyone: a real person's name other than the owner, an email address, a phone number, a street address, a precise location, a Wi-Fi network name (SSID), a device serial number, a MAC address
- specifics of the owner's employer, clients or day job: company names, internal system names, colleagues, contract or business details
- the owner's home network: the public IP address of the home connection, router or ISP account details
- identifiers of the owner's devices and network: phone, laptop or other device model numbers, hostnames of personal devices (any hostname that contains a person's name or names a phone, tablet or laptop), and the address of any specific machine on the tailnet (100.64.0.0/10) or the LAN (10.x, 172.16-31.x, 192.168.x) - say "the VPS's tailnet address" or "the phone" instead
- financial identifiers: bank or card details, seed phrases, exchange account ids, wallet addresses tied to the owner

Do not hold: mechanisms, architecture, configuration shapes, incident timelines, file paths, the project's own machine names (mandragora-desktop, mandragora-vps, mandragora-kindle, mandragora-wsl), public service domains under mvr.ac, network ranges written as CIDR, well-known addresses (public DNS resolvers, link-local, cloud metadata, a Docker bridge gateway), commit hashes, package and product names.

Reply with exactly one JSON object and nothing else:
{"hold": [{"file": "<path>", "excerpt": "<at most 80 chars around the problem, with the sensitive part replaced by ***>", "reason": "<which rule>"}]}
Reply {"hold": []} when nothing qualifies."""

NOTE_STEPS = """How to give a commit its vault verdict:
  If the change carries a non-obvious why (a decision, a constraint, an incident lesson):
    1. mandragora-vault find <keywords>             patch an existing note when one fits
    2. mandragora-vault new <category> "<Title>"     only when none fits, then write the body
    3. mandragora-vault commit -m "<what the note now explains>" <note path>
    4. end the commit message with:   Vault: <note path>
  Otherwise end the commit message with:
       Vault: none (<why there is nothing non-obvious to record>)
Rules: """ + DOCS


class Fail(Exception):
    pass


class Unavailable(Exception):
    pass


class Change:
    def __init__(self, status, path, old=None):
        self.status = status
        self.path = path
        self.old = old


class Problems:
    def __init__(self):
        self.items = []

    def add(self, path, problem, fix=None):
        self.items.append((path, problem, fix))

    def __bool__(self):
        return bool(self.items)

    def report(self):
        for path, problem, fix in self.items:
            print(f"✗ {path}: {problem}", file=sys.stderr)
            if fix:
                print(f"    fix: {fix}", file=sys.stderr)


GIT_LOCATION_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
                     "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_PREFIX", "GIT_NAMESPACE")
INHERIT_GIT_LOCATION = False


def git_env():
    if INHERIT_GIT_LOCATION:
        return None
    return {k: v for k, v in os.environ.items() if k not in GIT_LOCATION_VARS}


def git_run(args, repo):
    return subprocess.run(["git", "-C", repo, "-c", "core.quotePath=false", *args], capture_output=True, text=True, env=git_env())


def git(*args, repo=VAULT):
    r = git_run(args, repo)
    if r.returncode != 0:
        raise Fail(f"git {' '.join(args)}: {(r.stderr or r.stdout).strip()}")
    return r.stdout


def git_maybe(*args, repo=VAULT):
    r = git_run(args, repo)
    return r.stdout if r.returncode == 0 else None


def show(rev, path):
    return git_maybe("show", f"{rev}:{path}")


def is_agent():
    return any(os.environ.get(k) for k in AGENT_MARKERS)


def human_at_terminal():
    if is_agent():
        return False
    try:
        os.close(os.open("/dev/tty", os.O_RDWR))
        return True
    except OSError:
        return False


def quoted(path):
    return "'" + path.replace("'", "'\\''") + "'"


def rel(path):
    p = path.strip()
    if p.startswith("[[") and p.endswith("]]"):
        p = p[2:-2]
    p = p.strip("`'\" ")
    if os.path.isabs(p):
        real = os.path.realpath(p)
        if real != VAULT and not real.startswith(VAULT + os.sep):
            raise Fail(f"{path} is outside the vault ({VAULT})")
        p = os.path.relpath(real, VAULT)
    return os.path.normpath(p)


def walk_vault():
    for root, dirs, names in os.walk(VAULT):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for n in names:
            yield os.path.relpath(os.path.join(root, n), VAULT)


def stem_index():
    idx = {}
    for p in walk_vault():
        if p.lower().endswith(".md"):
            idx.setdefault(os.path.basename(p)[:-3].lower(), []).append(p)
    return idx


def link_index():
    names = set()
    for p in walk_vault():
        low = p.lower()
        names.add(os.path.basename(low))
        parts = (low[:-3] if low.endswith(".md") else low).split("/")
        for i in range(len(parts)):
            names.add("/".join(parts[i:]))
    return names


def links(text):
    if not text:
        return set()
    text = INLINE_CODE.sub("", FENCE.sub("", text))
    return {m.strip() for m in WIKILINK.findall(text) if m.strip()}


def frontmatter(text):
    if not text or not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end < 0 or text[end + 4:end + 5] not in ("\n", ""):
        return None
    keys = {}
    for line in text[4:end].splitlines():
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if m:
            keys[m.group(1)] = m.group(2).strip()
    return keys


def body(text):
    if frontmatter(text) is None:
        return text
    end = text.find("\n---", 4)
    return text[end + 4:]


def substantive(text):
    return [line for line in text.splitlines() if line.strip()]


def line_delta(old, new):
    a = substantive(old)
    b = substantive(new)
    removed = 0
    added = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag in ("insert", "replace"):
            added.extend(b[j1:j2])
        if tag == "delete":
            removed += i2 - i1
        elif tag == "replace":
            block = b[j1:j2]
            for line in a[i1:i2]:
                if not any(difflib.SequenceMatcher(None, line, cand).ratio() >= SIMILAR_LINE for cand in block):
                    removed += 1
    return removed, added, len(a)


def secret_patterns():
    pats = []
    try:
        with open(SECRET_PATTERNS, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                name, _, pattern = line.partition(":")
                pats.append((name, re.compile(pattern.replace("[:space:]", r"\s"))))
    except OSError:
        raise Fail(f"secret pattern list missing: {SECRET_PATTERNS}")
    return pats


def check_secrets(path, text, problems):
    for name, pat in secret_patterns():
        for n, line in enumerate(text.splitlines(), 1):
            if pat.search(line):
                problems.add(f"{path}:{n}", f"looks like a {name}; the vault is public at demo.mvr.ac",
                             "remove the value and describe the mechanism instead; if it was ever real, rotate it")


def check_ledger(old, new, problems):
    if old and not new.startswith(old):
        problems.add(LEDGER, "the ledger is append-only; existing lines changed",
                     f"restore it (git -C {quoted(VAULT)} checkout HEAD -- {LEDGER}) and record verdicts with: mandragora-vault verdict")
    for n, line in enumerate(new.splitlines(), 1):
        if line.startswith("#") or not line.strip():
            continue
        if not LEDGER_LINE.match(line):
            problems.add(f"{LEDGER}:{n}", "malformed ledger line", "record verdicts with: mandragora-vault verdict")


def check_new_name(c, stems, problems):
    parts = c.path.split("/")
    stem = os.path.basename(c.path)[:-3]
    if len(parts) != 2 or parts[0] not in NEW_NOTE_CATEGORIES:
        problems.add(c.path, "a note lives directly inside one category folder (a '/' in a title makes nested folders)",
                     "create it with: mandragora-vault new <category> \"<Title>\"  (categories: " + ", ".join(NEW_NOTE_CATEGORIES) + ")")
    if any(part.startswith(".") for part in parts):
        problems.add(c.path, "hidden paths are not notes")
    if BAD_NAME.search(stem) or stem != stem.strip() or not stem.strip() or len(stem) > 120:
        problems.add(c.path, "the title has characters Obsidian links cannot carry (# ^ [ ] | \\ / : * ? \" < >), leading or trailing spaces, or is empty or too long",
                     "pick a plain title")
    others = [p for p in stems.get(stem.lower(), []) if p != c.path]
    if others:
        problems.add(c.path, f"a note with this title already exists: {others[0]}",
                     f"patch {others[0]} instead (and delete the duplicate file if one was created)")


def check_addresses(path, lines, problems, old=None):
    known = set(IPV4.findall(old or ""))
    for addr in sorted({m for line in lines for m in IPV4.findall(line)} - known):
        try:
            ip = ipaddress.ip_address(addr)
        except ValueError:
            continue
        if ip in TAILNET:
            kind = "tailnet"
        elif any(ip in n for n in LAN_RANGES) and addr.rsplit(".", 1)[1] not in GENERIC_LAST_OCTETS:
            kind = "LAN"
        else:
            continue
        problems.add(path, f"names a specific {kind} address ({addr.rsplit('.', 2)[0]}.*.*); public notes describe machines, not their addresses",
                     "write \"the VPS's tailnet address\" or \"the desktop's LAN address\" instead")


def link_forms(path):
    low = path.lower()[:-3] if path.lower().endswith(".md") else path.lower()
    parts = low.split("/")
    return {"/".join(parts[i:]) for i in range(len(parts))}


def rewrite_links(text, forms, title):
    def sub(m):
        inner = m.group(1)
        name, rest = re.match(r"^(.*?)([#|].*)?$", inner, re.S).groups()
        key = name.strip().lower()
        key = key[:-3] if key.endswith(".md") else key
        if key not in forms:
            return m.group(0)
        return f"[[{title}{rest or ''}]]"
    parts = CODE.split(text)
    return "".join(FULL_LINK.sub(sub, s) if i % 2 == 0 else s for i, s in enumerate(parts))


def notes_linking(path):
    forms = link_forms(path) - link_index()
    if not forms:
        return []
    hits = []
    for p in walk_vault():
        if p.lower().endswith(".md"):
            with open(os.path.join(VAULT, p), encoding="utf-8", errors="replace") as f:
                text = f.read()
            if rewrite_links(text, forms, "x") != text:
                hits.append(p)
    return hits


def check_rename(c, stems, problems):
    check_new_name(c, stems, problems)
    left = notes_linking(c.old)
    if left:
        problems.add(c.path, f"renamed from {c.old}, but {len(left)} note(s) still link the old name ({', '.join(left[:3])})",
                     f"move it back (git -C {quoted(VAULT)} mv -- {quoted(c.path)} {quoted(c.old)}) and run: mandragora-vault rename {quoted(c.old)} \"<new title>\"")


def check_agent(c, old, new, stems, names, problems):
    if c.status == "A":
        check_new_name(c, stems, problems)
    new_fm = frontmatter(new)
    if old is None:
        top = c.path.split("/")[0]
        if new_fm is None:
            problems.add(c.path, "a new note needs frontmatter (type, era, tags)",
                         "create notes with: mandragora-vault new <category> \"<Title>\"")
        else:
            expected = CATEGORIES.get(top)
            if expected and new_fm.get("type") != expected:
                problems.add(c.path, f"frontmatter type is '{new_fm.get('type')}', the {top}/ folder needs '{expected}'")
            for key in ("era", "tags"):
                if key not in new_fm:
                    problems.add(c.path, f"frontmatter has no '{key}'")
        if len([line for line in substantive(body(new)) if not line.startswith("#")]) < MIN_BODY_LINES:
            problems.add(c.path, "the note has no body yet", "write what the reader needs to know, then commit")
        if len(new.splitlines()) > NEW_NOTE_MAX_LINES:
            problems.add(c.path, f"over {NEW_NOTE_MAX_LINES} lines; a note explains a why, it is not a dump",
                         "keep the reasoning, link to the code instead of pasting it")
        added = substantive(new)
    else:
        old_fm = frontmatter(old)
        if old_fm is not None:
            if new_fm is None:
                problems.add(c.path, "the frontmatter block was damaged or removed",
                             f"restore the --- block exactly as it was (git -C {quoted(VAULT)} diff -- {quoted(c.path)})")
            else:
                gone = sorted(set(old_fm) - set(new_fm))
                if gone:
                    problems.add(c.path, f"frontmatter keys removed: {', '.join(gone)}", "put them back")
                if "type" in old_fm and old_fm.get("type") != new_fm.get("type"):
                    problems.add(c.path, f"frontmatter type changed from '{old_fm.get('type')}' to '{new_fm.get('type')}'", "put it back")
        removed, added, total = line_delta(old, new)
        if removed > max(SHRINK_FLOOR, SHRINK_RATIO * total):
            problems.add(c.path, f"{removed} of its {total} lines are gone; that is a rewrite, not a patch",
                         f"restore it (git -C {quoted(VAULT)} checkout HEAD -- {quoted(c.path)}) and change only the lines that are wrong or missing")
        if len(added) > GROWTH_MAX_LINES:
            problems.add(c.path, f"{len(added)} lines added in one go", "keep the reasoning, link to the code instead of pasting it")
    for email in sorted({m for line in added for m in EMAIL.findall(line)}):
        if not EMAIL_ALLOWED.match(email):
            problems.add(c.path, f"contains an email address ({email.split('@')[0][:2]}***@{email.split('@')[1]})", "remove it")
    check_addresses(c.path, added, problems, old)
    for target in sorted(links(new) - links(old)):
        t = target.lower()
        if t not in names and (t[:-3] if t.endswith(".md") else t) not in names:
            problems.add(c.path, f"[[{target}]] matches no note in the vault",
                         f"link an existing title (mandragora-vault find {target.split()[0]}) or drop the brackets")


def run_checks(changes, content, profile):
    problems = Problems()
    stems = stem_index() if profile == "agent" else {}
    names = link_index() if profile == "agent" else set()
    for c in changes:
        old, new = content(c)
        if c.path == BASELINE:
            if profile == "agent":
                problems.add(c.path, "the coverage baseline is changed by a human only", f"restore it: git -C {quoted(VAULT)} checkout HEAD -- {BASELINE}")
            continue
        if c.path == LEDGER:
            if new is not None:
                check_ledger(old or "", new, problems)
            continue
        if c.status == "D":
            if profile == "agent":
                problems.add(c.path, "agents do not delete notes", f"restore it: git -C {quoted(VAULT)} checkout HEAD -- {quoted(c.path)}")
            elif profile == "publish":
                problems.add(c.path, "deleted since the last publish", "a human approves with: mandragora-vault publish --approve")
            continue
        if c.status == "R" and profile == "agent":
            check_rename(c, stems, problems)
        if not c.path.lower().endswith(".md"):
            if profile == "agent":
                problems.add(c.path, "agents commit notes (.md) only", "leave other files alone")
            continue
        if new is None:
            continue
        check_secrets(c.path, new, problems)
        if profile == "agent":
            check_agent(c, old, new, stems, names, problems)
        elif profile == "publish":
            added = substantive(new)
            if old is not None:
                removed, added, total = line_delta(old, new)
                if removed > max(SHRINK_FLOOR, SHRINK_RATIO * total):
                    problems.add(c.path, f"lost {removed} of {total} lines since the last publish",
                                 "a human approves with: mandragora-vault publish --approve")
            check_addresses(c.path, added, problems, old)
    return problems


def parse_porcelain(out):
    items = out.split("\0")
    res = []
    i = 0
    while i < len(items):
        entry = items[i]
        i += 1
        if len(entry) < 4:
            continue
        xy, path = entry[:2], entry[3:]
        old = None
        if "R" in xy or "C" in xy:
            old = items[i]
            i += 1
        if xy == "??" or "A" in xy:
            status = "A"
        elif "D" in xy:
            status = "D"
        elif "R" in xy:
            status = "R"
        else:
            status = "M"
        res.append(Change(status, path, old))
    return res


def parse_name_status(out):
    items = out.split("\0")
    res = []
    i = 0
    while i < len(items):
        s = items[i]
        i += 1
        if not s:
            continue
        if s[0] in "RC":
            old, new = items[i], items[i + 1]
            i += 2
            res.append(Change("R" if s[0] == "R" else "A", new, old if s[0] == "R" else None))
        else:
            res.append(Change({"A": "A", "D": "D"}.get(s[0], "M"), items[i]))
            i += 1
    return res


def worktree_content(c):
    p = os.path.join(VAULT, c.path)
    new = None
    if os.path.isfile(p):
        with open(p, encoding="utf-8", errors="replace") as f:
            new = f.read()
    return show("HEAD", c.old or c.path), new


def staged_content(c):
    return show("HEAD", c.old or c.path), show("", c.path)


def range_content(base, head):
    return lambda c: (show(base, c.old or c.path), show(head, c.path))


def worktree_changes(paths):
    out = git("status", "--porcelain=v1", "-z", "--untracked-files=all", "--", *paths)
    return [c for c in parse_porcelain(out) if paths or c.path.lower().endswith(".md") or c.path in (LEDGER, BASELINE)]


def commit_paths(paths, subject):
    present = [p for p in paths if os.path.exists(os.path.join(VAULT, p))]
    for _ in range(20):
        add = git_run(["add", "--", *present], VAULT)
        if add.returncode == 0:
            r = git_run(["commit", "--only", "-q", "-m", subject, "--", *paths], VAULT)
            if r.returncode == 0:
                return git("rev-parse", "HEAD").strip()
            err = r.stderr + r.stdout
        else:
            err = add.stderr + add.stdout
        if "index.lock" not in err:
            raise Fail(f"vault commit failed:\n{err.strip()}")
        time.sleep(0.5)
    raise Fail("vault index stayed locked for 10s; another commit is running, retry shortly")


def compose_subject(message, paths):
    subject = " ".join(message.split()).rstrip(".")
    if not subject:
        raise Fail("empty message; say what the note now explains")
    if not CONVENTIONAL.match(subject):
        top = paths[0].split("/")[0] if "/" in paths[0] else "vault"
        subject = f"docs({top}): {subject[0].lower()}{subject[1:]}"
    if len(subject) > 100:
        raise Fail("message too long; one line under 100 characters")
    return subject


def resolve_note(ref):
    try:
        p = rel(ref)
    except Fail as e:
        return None, str(e)
    if not p.lower().endswith(".md") and os.path.isfile(os.path.join(VAULT, p + ".md")):
        p += ".md"
    if os.path.isfile(os.path.join(VAULT, p)) and p.lower().endswith(".md"):
        return p, None
    hits = stem_index().get(os.path.basename(p)[:-3].lower() if p.lower().endswith(".md") else os.path.basename(p).lower(), [])
    if len(hits) == 1:
        return hits[0], None
    return None, f"no note '{ref}' in the vault (paths are relative to {VAULT})"


def committed_note_problem(path, recent):
    if git_maybe("ls-files", "--error-unmatch", "--", path) is None:
        return f"{path} is not committed to the vault; run: mandragora-vault commit -m \"<what it explains>\" {quoted(path)}"
    if git("status", "--porcelain", "--", path).strip():
        return f"{path} has uncommitted edits; run: mandragora-vault commit -m \"<what it explains>\" {quoted(path)}"
    if recent:
        ts = git("log", "-1", "--format=%ct", "--", path).strip()
        age = (time.time() - int(ts or 0)) / 86400
        if age > NOTE_RECENT_DAYS:
            return (f"{path} was last changed {int(age)} days ago; cite the note you wrote or patched for this change, "
                    f"or use: Vault: none (already documented in {os.path.basename(path)[:-3]})")
    return None


def verdict_problems(value, recent=True):
    m = re.match(r"^none\b(.*)$", value, re.I | re.S)
    if m:
        reason = m.group(1).strip().lstrip("-—–:(").rstrip(")").strip()
        if len(reason.split()) < 3:
            return [f"'Vault: {value}' needs a reason of three or more words, e.g. Vault: none (only retunes a timeout)"]
        return []
    out = []
    for ref in [x for x in (s.strip() for s in value.split(",")) if x]:
        path, err = resolve_note(ref)
        if err:
            out.append(err)
            continue
        err = committed_note_problem(path, recent)
        if err:
            out.append(err)
    return out


def message_problems(text):
    subject = next((line for line in text.splitlines() if line.strip()), "")
    if subject.startswith(SKIP_SUBJECTS):
        return []
    values = VAULT_LINE.findall(text)
    if not values:
        return ["the message has no Vault: line"]
    out = []
    for v in values:
        out += verdict_problems(v)
    return out


def clean_message(text):
    text = text.split(SCISSORS)[0]
    return "\n".join(line for line in text.splitlines() if not line.startswith("#"))


def read_baseline():
    path = os.path.join(VAULT, BASELINE)
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"^commit:\s*([0-9a-f]{7,40})\s*$", line)
                if m:
                    return git("rev-parse", "--verify", m.group(1) + "^{commit}", repo=FLAKE).strip()
    except OSError:
        pass
    raise Fail(f"no 'commit:' baseline in {path}")


def read_ledger():
    path = os.path.join(VAULT, LEDGER)
    out = {}
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                if LEDGER_LINE.match(line.rstrip("\n")):
                    h, kind, detail = line.rstrip("\n").split("\t", 2)
                    out[h] = (kind, detail)
    return out


def coverage(baseline):
    out = git("log", "--no-merges", "--format=%H%x1f%s%x1f%B%x1e", f"{baseline}..refs/heads/master", repo=FLAKE)
    ledger = read_ledger()
    rows = []
    for rec in out.split("\x1e"):
        rec = rec.strip("\n")
        if not rec:
            continue
        h, s, b = rec.split("\x1f", 2)
        src = "message" if VAULT_LINE.search(b) else ("ledger" if h in ledger else None)
        rows.append((h, s, src))
    return rows


def held_path():
    return os.path.join(STATE, "held.json")


def load_held():
    try:
        with open(held_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_held(head, items):
    os.makedirs(STATE, exist_ok=True)
    with open(held_path(), "w", encoding="utf-8") as f:
        json.dump({"head": head, "at": datetime.datetime.now().isoformat(timespec="seconds"), "items": items}, f, indent=1)


def clear_held():
    try:
        os.remove(held_path())
    except OSError:
        pass


def notify(summary, text):
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", "mandragora-vault", "-u", "critical", summary, text], capture_output=True)


def review_blocks(base, head):
    diff = git("diff", "--unified=0", "--no-color", base, head, "--", "*.md")
    blocks = []
    current = None
    lines = []
    for line in diff.splitlines():
        if line.startswith("+++ "):
            if current and lines:
                blocks.append((current, lines))
            current = line[6:] if line.startswith("+++ b/") else None
            lines = []
        elif line.startswith("+") and current:
            lines.append(line[1:])
    if current and lines:
        blocks.append((current, lines))
    return blocks


def review_chunks(blocks):
    chunks = []
    buf = ""
    for path, lines in blocks:
        part = f"### {path}\n"
        for line in lines:
            if len(part) + len(line) + 1 > CHUNK_CHARS:
                chunks.append(part)
                part = f"### {path} (continued)\n"
            part += line + "\n"
        if buf and len(buf) + len(part) > CHUNK_CHARS:
            chunks.append(buf)
            buf = ""
        buf += part + "\n"
    if buf:
        chunks.append(buf)
    return chunks


def model_review(base, head):
    if not shutil.which("claude"):
        raise Unavailable("claude CLI not on PATH")
    holds = []
    os.makedirs(STATE, exist_ok=True)
    for chunk in review_chunks(review_blocks(base, head)):
        cmd = ["claude", "-p", "--model", REVIEW_MODEL, "--no-session-persistence", "--tools", "", "--strict-mcp-config",
               "--system-prompt", REVIEW_PROMPT, "Review the added lines on standard input. Reply with the JSON object only."]
        try:
            r = subprocess.run(cmd, input=chunk, capture_output=True, text=True, timeout=REVIEW_TIMEOUT, cwd=STATE)
        except subprocess.TimeoutExpired:
            raise Unavailable(f"review timed out after {REVIEW_TIMEOUT}s")
        if r.returncode != 0:
            raise Unavailable(f"claude exited {r.returncode}: {(r.stderr or r.stdout).strip()[:200]}")
        text = r.stdout
        start, end = text.find("{"), text.rfind("}")
        try:
            verdict = json.loads(text[start:end + 1])
        except ValueError:
            raise Unavailable(f"review reply was not JSON: {text.strip()[:200]}")
        items = verdict.get("hold") if isinstance(verdict, dict) else None
        if not isinstance(items, list):
            raise Unavailable(f"review reply had no hold list: {text.strip()[:200]}")
        for item in items:
            if isinstance(item, dict):
                holds.append({"file": str(item.get("file", "?")), "problem": str(item.get("reason", "private material")),
                              "excerpt": str(item.get("excerpt", ""))[:120]})
    return holds


def served_status():
    try:
        with urllib.request.urlopen(SITE_PROBE, timeout=20) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except OSError as e:
        return str(e)


def deploy(rev):
    tmp = tempfile.mkdtemp(prefix="mandragora-vault-publish-")
    os.chmod(tmp, 0o755)
    try:
        archive = subprocess.run(["git", "-C", VAULT, "archive", "--format=tar", rev], capture_output=True, check=True, env=git_env()).stdout
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(tmp, filter="data")
        for name in (LEDGER, BASELINE, ".gitignore"):
            p = os.path.join(tmp, name)
            if os.path.exists(p):
                os.remove(p)
        return subprocess.run([DEPLOY], env={**os.environ, "VAULT": tmp}).returncode == 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def cmd_find(a):
    words = [w.lower() for w in a.words]
    scored = []
    for p in walk_vault():
        if not p.lower().endswith(".md"):
            continue
        title = os.path.basename(p)[:-3].lower()
        try:
            with open(os.path.join(VAULT, p), encoding="utf-8", errors="replace") as f:
                text = f.read().lower()
        except OSError:
            continue
        score = sum(10 for w in words if w in title) + sum(min(text.count(w), 5) for w in words)
        if score and all(w in title or w in text for w in words):
            scored.append((score, p))
    for score, p in sorted(scored, key=lambda x: (-x[0], x[1]))[:a.limit]:
        print(p)
    if not scored:
        print("no note mentions all of: " + " ".join(a.words), file=sys.stderr)
    return 0


def category_dir(name):
    cat = name.lower().strip("/")
    if cat not in CATEGORIES:
        cat = next((d for d, t in CATEGORIES.items() if t == cat), cat)
    if cat not in NEW_NOTE_CATEGORIES:
        raise Fail(f"category '{name}' is not one of: {', '.join(NEW_NOTE_CATEGORIES)}")
    return cat


def cmd_rename(a):
    old, err = resolve_note(a.old)
    if err:
        raise Fail(err)
    if git("status", "--porcelain", "--", old).strip():
        raise Fail(f"{old} has uncommitted edits; commit them first: mandragora-vault commit -m \"<what changed>\" {quoted(old)}")
    title = " ".join(a.title.split())
    if title.lower().endswith(".md"):
        title = title[:-3].rstrip()
    if "/" in title:
        raise Fail("give the new title only; move it to another category with --to <category>")
    folder = category_dir(a.to) if a.to else old.split("/")[0]
    path = f"{folder}/{title}.md"
    if path == old:
        raise Fail("that is already its name")
    problems = Problems()
    check_new_name(Change("A", path), {k: [p for p in v if p != old] for k, v in stem_index().items()}, problems)
    if problems:
        problems.report()
        return 1
    forms = link_forms(old)
    old_title = os.path.basename(old)[:-3]
    git("mv", "--", old, path)
    touched = [path]
    for p in walk_vault():
        if not p.lower().endswith(".md"):
            continue
        full = os.path.join(VAULT, p)
        with open(full, encoding="utf-8", errors="replace") as f:
            text = f.read()
        fixed = rewrite_links(text, forms, title)
        if p == path:
            fixed = re.sub(r"^# " + re.escape(old_title) + r"[ \t]*$", "# " + title, fixed, count=1, flags=re.M)
        if fixed != text:
            with open(full, "w", encoding="utf-8") as f:
                f.write(fixed)
            touched.append(p)
    subject = f"refactor(vault): rename {old_title} to {title}"
    if len(subject) > 100:
        subject = f"refactor(vault): rename a note to {title}"[:100].rstrip()
    try:
        sha = commit_paths(sorted(set([old] + touched)), subject)
    except Fail:
        git_run(["reset", "-q", "--", old, path], VAULT)
        if os.path.exists(os.path.join(VAULT, path)):
            os.remove(os.path.join(VAULT, path))
        git_run(["checkout", "-q", "HEAD", "--", *sorted(set([old] + touched) - {path})], VAULT)
        raise
    others = sorted(set(touched) - {path})
    print(f"renamed {old} -> {path} and rewrote links in {len(others)} note(s): {sha[:8]}")
    return 0


def cmd_new(a):
    cat = category_dir(a.category)
    title = " ".join(a.title.split())
    path = f"{cat}/{title}.md"
    problems = Problems()
    check_new_name(Change("A", path), stem_index(), problems)
    if problems:
        problems.report()
        return 1
    today = datetime.date.today().isoformat()
    with open(os.path.join(VAULT, path), "x", encoding="utf-8") as f:
        f.write(f"---\ntype: {CATEGORIES[cat]}\nera: {CURRENT_ERA}\ndate: {today}\ntags: [{CATEGORIES[cat]}]\n---\n\n# {title}\n\n")
    print(os.path.join(VAULT, path))
    print(f"write the body under the heading, then: mandragora-vault commit -m \"<what it explains>\" {quoted(path)}", file=sys.stderr)
    return 0


def cmd_check(a):
    global INHERIT_GIT_LOCATION
    if a.staged:
        INHERIT_GIT_LOCATION = True
        changes = parse_name_status(git("diff", "--cached", "--name-status", "-z", "-M"))
        problems = run_checks(changes, staged_content, "agent" if is_agent() else "human")
    else:
        paths = [rel(p) for p in a.paths]
        problems = run_checks(worktree_changes(paths), worktree_content, "agent")
    if problems:
        problems.report()
        print(f"vault check failed. Rules: {DOCS}", file=sys.stderr)
        return 1
    return 0


def cmd_commit(a):
    paths = [rel(p) for p in a.paths]
    changes = worktree_changes(paths)
    touched = {c.path for c in changes} | {c.old for c in changes if c.old}
    idle = [p for p in paths if p not in touched]
    if idle:
        raise Fail("nothing changed in: " + ", ".join(idle))
    problems = run_checks(changes, worktree_content, "agent")
    if problems:
        problems.report()
        print("nothing committed.", file=sys.stderr)
        return 1
    subject = compose_subject(a.message, paths)
    sha = commit_paths(sorted(touched), subject)
    notes = [c.path for c in changes if c.path.lower().endswith(".md")]
    print(f"committed {sha[:8]} {subject}")
    if notes:
        print("end your mandragora commit message with:  Vault: " + ", ".join(notes))
    return 0


def cmd_trailer_check(a):
    if not is_agent():
        return 0
    with open(a.file, encoding="utf-8", errors="replace") as f:
        problems = message_problems(clean_message(f.read()))
    if not problems:
        return 0
    print("This commit comes from an agent, so its message needs a valid Vault: line.", file=sys.stderr)
    for p in problems:
        print(f"  ✗ {p}", file=sys.stderr)
    print(NOTE_STEPS, file=sys.stderr)
    return 1


def cmd_gate(a):
    base = a.range.split("..")[0]
    bad = []
    for h in git("rev-list", "--no-merges", "--reverse", a.range, repo=a.repo).split():
        msg = git("log", "-1", "--format=%B", h, repo=a.repo)
        problems = message_problems(msg)
        if problems:
            bad.append((h, msg.splitlines()[0] if msg.strip() else "", problems))
    if not bad:
        return 0
    print("These commits have no valid Vault: line:", file=sys.stderr)
    for h, subject, problems in bad:
        print(f"  {h[:8]} {subject}", file=sys.stderr)
        for p in problems:
            print(f"      ✗ {p}", file=sys.stderr)
    print(NOTE_STEPS, file=sys.stderr)
    print("To fix commits that already exist:", file=sys.stderr)
    print('  only the newest one:  git commit --amend --no-edit --trailer "Vault: <note path or none (reason)>"', file=sys.stderr)
    print(f'  several:              git reset --soft {base[:12]} && git commit -m "<subject>" -m "Vault: <...>"', file=sys.stderr)
    return 1


def cmd_verdict(a):
    entries = []
    if a.from_file:
        with open(a.from_file, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                line = line.rstrip("\n")
                if not line.strip() or line.startswith("#"):
                    continue
                parts = line.split("\t", 2)
                if len(parts) != 3 or parts[1] not in ("note", "none"):
                    raise Fail(f"{a.from_file}:{n}: expected <commit>TAB<note|none>TAB<note path or reason>")
                entries.append(tuple(parts))
    elif a.commit and (a.note or a.none):
        entries.append((a.commit, "note", a.note) if a.note else (a.commit, "none", a.none))
    else:
        raise Fail("give <commit> with --note <path> or --none \"<reason>\", or --from-file <tsv>")
    baseline = read_baseline()
    rows = {h: src for h, _, src in coverage(baseline)}
    lines = []
    errors = []
    seen = set()
    for commit, kind, detail in entries:
        full = (git_maybe("rev-parse", "--verify", "-q", commit + "^{commit}", repo=FLAKE) or "").strip()
        if full not in rows:
            errors.append(f"{commit}: not a non-merge commit between the baseline and master")
            continue
        if rows[full] or full in seen:
            errors.append(f"{commit}: already has a verdict")
            continue
        detail = " ".join(detail.split())
        if kind == "none":
            probs = verdict_problems("none (" + detail + ")", recent=False)
        else:
            path, err = resolve_note(detail)
            err = err or committed_note_problem(path, False)
            probs = [err] if err else []
            detail = path or detail
        if probs:
            errors += [f"{commit}: {p}" for p in probs]
            continue
        seen.add(full)
        lines.append(f"{full}\t{kind}\t{detail}")
    if errors:
        for e in errors:
            print(f"✗ {e}", file=sys.stderr)
        print("nothing recorded.", file=sys.stderr)
        return 1
    path = os.path.join(VAULT, LEDGER)
    existing = ""
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            existing = f.read()
    with open(path, "a", encoding="utf-8") as f:
        if existing and not existing.endswith("\n"):
            f.write("\n")
        f.write("\n".join(lines) + "\n")
    sha = commit_paths([LEDGER], f"chore(vault): record verdicts for {len(lines)} commit(s)")
    print(f"recorded {len(lines)} verdict(s) in {sha[:8]}")
    return 0


def cmd_status(a):
    baseline = read_baseline()
    rows = coverage(baseline)
    if a.missing:
        for h, s, src in rows:
            if src is None:
                print(f"{h}\t{s}")
        return 0
    n_msg = sum(1 for r in rows if r[2] == "message")
    n_led = sum(1 for r in rows if r[2] == "ledger")
    n_miss = len(rows) - n_msg - n_led
    print(f"mandragora commits since baseline {baseline[:8]}: {len(rows)}")
    print(f"  verdict in the commit message  {n_msg}")
    print(f"  verdict in the ledger          {n_led}")
    print(f"  no verdict                     {n_miss}" + ("   (list: mandragora-vault status --missing)" if n_miss else ""))
    head = git("rev-parse", "HEAD").strip()
    pub = (git_maybe("rev-parse", "--verify", "-q", PUBLISHED) or "").strip()
    if not pub:
        print("demo.mvr.ac: no published ref yet (a human runs: mandragora-vault publish --init <live vault commit>)")
    elif pub == head:
        print("demo.mvr.ac: current with the vault")
    else:
        n = git("rev-list", "--count", f"{pub}..{head}").strip()
        print(f"demo.mvr.ac: {n} vault commit(s) not published yet")
    unlinkable = [p for p in walk_vault() if p.lower().endswith(".md") and (BAD_NAME.search(os.path.basename(p)[:-3]) or os.path.basename(p)[:-3] != os.path.basename(p)[:-3].strip())]
    if unlinkable:
        print(f"names Obsidian cannot link: {len(unlinkable)}  (fix: mandragora-vault rename '<path>' \"<plain title>\")")
        for p in unlinkable:
            print(f"  {p}")
    waiting = [c.path for c in worktree_changes([]) if c.path.lower().endswith(".md") and c.status in ("A", "M")]
    if waiting:
        print(f"notes waiting for their author (uncommitted, not published): {len(waiting)}")
        for p in waiting:
            full = os.path.join(VAULT, p)
            age = (time.time() - os.path.getmtime(full)) / 3600 if os.path.exists(full) else 0
            print(f"  {p}  (untouched {age:.0f}h)")
    held = load_held()
    if held:
        print(f"held since {held['at']} at vault {held['head'][:8]}:")
        for item in held["items"]:
            print(f"  ✗ {item['file']}: {item['problem']}" + (f"  [{item['excerpt']}]" if item.get("excerpt") else ""))
    return 0


def cmd_publish(a):
    os.makedirs(STATE, exist_ok=True)
    with open(os.path.join(STATE, "publish.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return publish(a)


def publish(a):
    head = git("rev-parse", "HEAD").strip()
    pub = (git_maybe("rev-parse", "--verify", "-q", PUBLISHED) or "").strip()
    if a.init:
        if pub:
            raise Fail(f"already initialised at {pub[:8]}")
        target = git("rev-parse", "--verify", a.init + "^{commit}").strip()
        git("update-ref", PUBLISHED, target, "")
        print(f"published ref set to {target[:8]}")
        return 0
    if not pub:
        raise Fail("no published ref yet; a human runs once: mandragora-vault publish --init <vault commit that is live>")
    if pub == head:
        clear_held()
        print("demo.mvr.ac is current with the vault")
        return 0
    if git_run(["merge-base", "--is-ancestor", pub, head], VAULT).returncode != 0:
        raise Fail(f"published ref {pub[:8]} is not an ancestor of vault HEAD; history was rewritten")
    if a.approve and not human_at_terminal():
        raise Fail("--approve is for a human at a terminal")
    changes = parse_name_status(git("diff", "--name-status", "-z", "-M", pub, head))
    problems = run_checks(changes, range_content(pub, head), "publish")
    holds = [{"file": p, "problem": prob, "excerpt": ""} for p, prob, _ in problems.items]
    try:
        holds += model_review(pub, head)
    except Unavailable as e:
        if not a.approve:
            print(f"vault publish skipped: no review model ({e}); nothing published, the next agent switch retries", file=sys.stderr)
            return 3
    if holds and not a.approve:
        save_held(head, holds)
        notify("demo.mvr.ac publish held", f"{len(holds)} item(s) need a look: mandragora-vault status")
        print("vault publish held; nothing published:", file=sys.stderr)
        for h in holds:
            print(f"  ✗ {h['file']}: {h['problem']}" + (f"  [{h['excerpt']}]" if h["excerpt"] else ""), file=sys.stderr)
        print("fix the note and commit it (mandragora-vault commit), or a human approves: mandragora-vault publish --approve", file=sys.stderr)
        return 4
    count = git("rev-list", "--count", f"{pub}..{head}").strip()
    if not deploy(head):
        print("deploy failed; the published ref is unchanged", file=sys.stderr)
        return 5
    git("update-ref", PUBLISHED, head, pub)
    clear_held()
    status = served_status()
    if status != 200:
        notify("demo.mvr.ac broken after publish", f"{SITE_PROBE} answers {status}")
        print(f"deployed, but {SITE_PROBE} answers {status}; the site is not serving the vault", file=sys.stderr)
        return 6
    print(f"published vault {head[:8]} to demo.mvr.ac ({count} commit(s))")
    return 0


def main():
    ap = argparse.ArgumentParser(prog="mandragora-vault", description=f"Write, check and publish knowledge-vault notes safely. Rules: {DOCS}")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("find", help="list notes matching all keywords")
    p.add_argument("words", nargs="+")
    p.add_argument("--limit", type=int, default=12)
    p.set_defaults(fn=cmd_find)
    p = sub.add_parser("new", help="create a note with correct frontmatter")
    p.add_argument("category")
    p.add_argument("title")
    p.set_defaults(fn=cmd_new)
    p = sub.add_parser("rename", help="rename a note and rewrite every link to it")
    p.add_argument("old")
    p.add_argument("title")
    p.add_argument("--to")
    p.set_defaults(fn=cmd_rename)
    p = sub.add_parser("check", help="validate changed notes")
    p.add_argument("paths", nargs="*")
    p.add_argument("--staged", action="store_true")
    p.set_defaults(fn=cmd_check)
    p = sub.add_parser("commit", help="check and commit exactly these notes")
    p.add_argument("-m", "--message", required=True)
    p.add_argument("paths", nargs="+")
    p.set_defaults(fn=cmd_commit)
    p = sub.add_parser("trailer-check", help="commit-msg gate for agent commits")
    p.add_argument("file")
    p.set_defaults(fn=cmd_trailer_check)
    p = sub.add_parser("gate", help="require a Vault: line on every commit in a range")
    p.add_argument("range")
    p.add_argument("--repo", default=FLAKE)
    p.set_defaults(fn=cmd_gate)
    p = sub.add_parser("verdict", help="record a verdict for a landed commit that has none")
    p.add_argument("commit", nargs="?")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--note")
    g.add_argument("--none")
    p.add_argument("--from-file")
    p.set_defaults(fn=cmd_verdict)
    p = sub.add_parser("status", help="coverage, publish state and holds")
    p.add_argument("--missing", action="store_true")
    p.set_defaults(fn=cmd_status)
    p = sub.add_parser("publish", help="review unpublished notes and deploy demo.mvr.ac")
    p.add_argument("--approve", action="store_true")
    p.add_argument("--init")
    p.set_defaults(fn=cmd_publish)
    a = ap.parse_args()
    try:
        sys.exit(a.fn(a))
    except Fail as e:
        print(f"mandragora-vault: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
