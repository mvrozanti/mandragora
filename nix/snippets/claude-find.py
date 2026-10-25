import argparse
import json
import os
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
PROJECTS = CLAUDE_DIR / "projects"
HISTORY = CLAUDE_DIR / "history.jsonl"
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
DB_PATH = DATA_HOME / "claude-find" / "index.db"
LIMIT = 80

SCHEMA = """
create table if not exists session(
  sid text primary key, cwd text, title text, started real, last_seen real,
  turns integer default 0, has_transcript integer default 0, mtime real default 0);
create virtual table if not exists turn using fts5(
  sid unindexed, role unindexed, ts unindexed, text,
  tokenize='porter unicode61');
create table if not exists meta(k text primary key, v text);
"""


def open_db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH)
    db.executescript(SCHEMA)
    return db


def transcript_files():
    seen = {}
    for path in PROJECTS.glob("*/*.jsonl"):
        real = path.resolve()
        if real in seen:
            continue
        seen[real] = True
        yield real.stem, real


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text")
    return ""


def epoch(value):
    if isinstance(value, (int, float)):
        return value / 1000 if value > 1e11 else value
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def parse_transcript(path):
    title = custom = cwd = started = None
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            kind = rec.get("type")
            if kind == "ai-title":
                title = rec.get("aiTitle")
            elif kind == "custom-title":
                custom = rec.get("customTitle")
            elif kind in ("user", "assistant"):
                if rec.get("isSidechain"):
                    continue
                text = text_of(rec.get("message", {}).get("content")).strip()
                if not text or (kind == "user" and text.startswith("<")):
                    continue
                cwd = cwd or rec.get("cwd")
                ts = epoch(rec.get("timestamp"))
                started = started if started is not None else ts
                rows.append((kind, ts, text))
    return custom or title, cwd, started, rows


def index_transcripts(db, full):
    indexed = {sid: mtime for sid, mtime in db.execute("select sid, mtime from session where has_transcript=1")}
    present = set()
    changed = 0
    for sid, path in transcript_files():
        present.add(sid)
        mtime = path.stat().st_mtime
        if not full and indexed.get(sid) == mtime:
            continue
        title, cwd, started, rows = parse_transcript(path)
        db.execute("delete from turn where sid=?", (sid,))
        db.executemany("insert into turn(sid, role, ts, text) values(?,?,?,?)", ((sid, r, t, x) for r, t, x in rows))
        db.execute(
            "insert into session(sid, cwd, title, started, last_seen, turns, has_transcript, mtime) values(?,?,?,?,?,?,1,?)"
            " on conflict(sid) do update set cwd=coalesce(excluded.cwd, cwd), title=coalesce(excluded.title, title),"
            " started=coalesce(excluded.started, started), last_seen=excluded.last_seen, turns=excluded.turns,"
            " has_transcript=1, mtime=excluded.mtime",
            (sid, cwd, title, started, mtime, len(rows), mtime))
        changed += 1
    gone = [sid for sid in indexed if sid not in present]
    db.executemany("update session set has_transcript=0 where sid=?", ((s,) for s in gone))
    return changed, len(gone)


def index_history(db):
    if not HISTORY.exists():
        return 0
    offset = int(db.execute("select v from meta where k='history_offset'").fetchone()[0]) if db.execute("select 1 from meta where k='history_offset'").fetchone() else 0
    size = HISTORY.stat().st_size
    if offset > size:
        offset = 0
    added = 0
    with open(HISTORY, "rb") as fh:
        fh.seek(offset)
        for raw in fh:
            offset += len(raw)
            try:
                rec = json.loads(raw)
            except ValueError:
                continue
            sid, text = rec.get("sessionId"), (rec.get("display") or "").strip()
            if not sid or not text:
                continue
            row = db.execute("select has_transcript from session where sid=?", (sid,)).fetchone()
            if row and row[0]:
                continue
            ts = epoch(rec.get("timestamp"))
            db.execute(
                "insert into session(sid, cwd, started, last_seen, turns, has_transcript) values(?,?,?,?,1,0)"
                " on conflict(sid) do update set last_seen=max(last_seen, excluded.last_seen), turns=turns+1",
                (sid, rec.get("project"), ts, ts))
            db.execute("insert into turn(sid, role, ts, text) values(?,?,?,?)", (sid, "user", ts, text))
            added += 1
    db.execute("insert into meta(k, v) values('history_offset', ?) on conflict(k) do update set v=excluded.v", (str(offset),))
    return added


def cmd_index(args):
    db = open_db()
    changed, gone = index_transcripts(db, args.full)
    added = index_history(db)
    db.commit()
    if not args.quiet:
        print(f"transcripts re-indexed: {changed}, vanished: {gone}, history prompts added: {added}")


def behind(db):
    indexed = {sid: (mtime, turns) for sid, mtime, turns in db.execute("select sid, mtime, turns from session where has_transcript=1")}
    stale, empty = [], []
    for sid, path in transcript_files():
        st = path.stat()
        if sid not in indexed or indexed[sid][0] != st.st_mtime:
            stale.append(sid)
        elif indexed[sid][1] == 0 and st.st_size > 32768:
            empty.append(sid)
    return stale, empty


def cmd_doctor(args):
    db = open_db()
    stale, empty = behind(db)
    on_disk = {sid for sid, _ in transcript_files()}
    orphan = [sid for (sid,) in db.execute("select sid from session where has_transcript=1") if sid not in on_disk]
    if args.count:
        print(len(stale) + len(empty))
        return
    sessions, turns = db.execute("select count(*), sum(turns) from session").fetchone()
    print(f"index: {DB_PATH} ({DB_PATH.stat().st_size // 1024} KiB), {sessions} sessions, {turns} turns")
    print(f"transcripts on disk: {len(on_disk)}; not yet indexed or changed since: {len(stale)}")
    print(f"indexed but no text extracted (parser may be stale): {len(empty)}")
    print(f"indexed as present but file gone (run index): {len(orphan)}")
    for label, sids in (("stale", stale), ("empty", empty), ("orphan", orphan)):
        for sid in sids[:20]:
            print(f"  {label}  {sid}")


def cmd_reindex(args):
    db = open_db()
    db.execute("update session set mtime=0 where sid=?", (args.sid,))
    changed, _ = index_transcripts(db, False)
    db.commit()
    print(f"re-indexed {changed} transcript(s) for {args.sid}")


def match_expr(query):
    q = query.strip()
    if not q:
        return None
    if '"' in q or any(op in q.split() for op in ("AND", "OR", "NOT", "NEAR")):
        return q
    terms = [t.replace('"', "") for t in q.split()]
    quoted = [f'"{t}"' for t in terms]
    quoted[-1] += "*"
    return " ".join(quoted)


def search(db, query, here):
    expr = match_expr(query)
    where_cwd = " and (s.cwd = ? or s.cwd like ?)" if here else ""
    cwd_args = (here, here.rstrip("/") + "/%") if here else ()
    if expr is None:
        return db.execute(
            "select s.sid, s.cwd, s.title, s.started, s.last_seen, s.has_transcript, '' as snip, 0 as hits"
            f" from session s where 1=1{where_cwd} order by s.last_seen desc limit ?", (*cwd_args, LIMIT)).fetchall()
    sql = (
        "with t as materialized (select sid, snippet(turn, 3, '', '', '…', 14) as snip, bm25(turn) as r from turn where turn match ?)"
        " select s.sid, s.cwd, s.title, s.started, s.last_seen, s.has_transcript, t.snip, count(*) as hits, min(t.r) as r"
        f" from t join session s on s.sid = t.sid where 1=1{where_cwd} group by t.sid order by r limit ?")
    try:
        return db.execute(sql, (expr, *cwd_args, LIMIT)).fetchall()
    except sqlite3.OperationalError:
        fallback = " ".join(f'"{t}"' for t in query.replace('"', " ").split())
        if not fallback:
            return []
        return db.execute(sql, (fallback, *cwd_args, LIMIT)).fetchall()


def fmt_date(ts):
    if not ts:
        return "          "
    return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone().strftime("%Y-%m-%d")


def short_cwd(cwd):
    home = str(Path.home())
    cwd = cwd or ""
    return "~" + cwd[len(home):] if cwd.startswith(home) else cwd


def cmd_query(args):
    db = open_db()
    query = " ".join(args.terms)
    for sid, cwd, title, started, last_seen, has, snip, *_ in search(db, query, args.here):
        flag = " " if has else "†"
        head = (title or "(untitled)")[:48]
        snip = " ".join((snip or "").split())[:160]
        print("\t".join([sid, f"{flag}{fmt_date(last_seen or started)}", head, short_cwd(cwd), snip]))


def cmd_show(args):
    db = open_db()
    query = " ".join(args.terms)
    expr = match_expr(query)
    row = db.execute("select title, cwd, started, has_transcript, turns from session where sid=?", (args.sid,)).fetchone()
    if not row:
        print("not indexed:", args.sid)
        return
    title, cwd, started, has, turns = row
    print(f"{title or '(untitled)'}\n{short_cwd(cwd)} · {fmt_date(started)} · {turns} turns · {'resumable' if has else 'transcript gone, prompts only'}\n")
    if expr:
        try:
            rows = db.execute(
                "select role, ts, highlight(turn, 3, '>>', '<<') from turn where sid=? and turn match ? order by rank limit 12",
                (args.sid, expr)).fetchall()
        except sqlite3.OperationalError:
            rows = []
    else:
        rows = db.execute("select role, ts, text from turn where sid=? order by ts limit 12", (args.sid,)).fetchall()
    for role, ts, text in rows:
        body = text if args.full else text[:600]
        print(f"[{fmt_date(ts)} {role}]\n{body}\n")


def cmd_ui(args):
    db = open_db()
    index_transcripts(db, False)
    index_history(db)
    db.commit()
    stale, empty = behind(db)
    lag = len(stale) + len(empty)
    header = f"index {lag} session(s) behind, run: claude-find doctor" if lag else "index fresh"
    if empty:
        header = f"{len(empty)} transcript(s) yielded no text: parser may be stale. claude-find doctor"
    me = sys.argv[0]
    here = f" --here {subprocess.list2cmdline([args.here])}" if args.here else ""
    reload = f"{me} query{here} -- {{q}}"
    cmd = [
        "fzf", "--disabled", "--ansi", "--delimiter", "\t", "--with-nth", "2..",
        "--tabstop", "4", "--header", header, "--prompt", "phrase or subject> ",
        "--bind", f"start:reload({reload})", "--bind", f"change:reload({reload})",
        "--preview", f"{me} show {{1}} -- {{q}}", "--preview-window", "right,45%,wrap",
        "--bind", "ctrl-/:toggle-preview", "--no-sort", "--layout", "reverse",
    ]
    try:
        out = subprocess.run(cmd, stdout=subprocess.PIPE, text=True).stdout.strip()
    except FileNotFoundError:
        sys.exit("fzf not on PATH")
    if not out:
        return
    sid = out.split("\t", 1)[0]
    title, cwd, has = db.execute("select title, cwd, has_transcript from session where sid=?", (sid,)).fetchone()
    if not has:
        subprocess.run([sys.executable, me, "show", sid, "--full"], check=False)
        return
    os.execvp("claude-reopen", ["claude-reopen", sid, cwd or str(Path.home()), title or ""])


def main():
    p = argparse.ArgumentParser(prog="claude-find", description="find a Claude Code session by phrase or subject, across every directory, and reopen it where it lived")
    p.add_argument("--here", nargs="?", const=os.getcwd(), default=None, metavar="DIR", help="only sessions whose cwd is DIR or below (default: current directory)")
    sub = p.add_subparsers(dest="cmd")
    s = sub.add_parser("index", help="refresh the index (incremental by mtime)")
    s.add_argument("--full", action="store_true")
    s.add_argument("--quiet", action="store_true")
    s.set_defaults(fn=cmd_index)
    s = sub.add_parser("query", help="print matching sessions as tab-separated rows")
    s.add_argument("--here", nargs="?", const=os.getcwd(), default=None)
    s.add_argument("terms", nargs="*")
    s.set_defaults(fn=cmd_query)
    s = sub.add_parser("show", help="print a session's matching turns")
    s.add_argument("sid")
    s.add_argument("--full", action="store_true")
    s.add_argument("terms", nargs="*")
    s.set_defaults(fn=cmd_show)
    s = sub.add_parser("doctor", help="compare transcripts on disk with the index")
    s.add_argument("--count", action="store_true")
    s.set_defaults(fn=cmd_doctor)
    s = sub.add_parser("reindex", help="force one session to be re-read")
    s.add_argument("sid")
    s.set_defaults(fn=cmd_reindex)
    args = p.parse_args()
    if args.cmd is None:
        cmd_ui(args)
    else:
        args.fn(args)


if __name__ == "__main__":
    main()
