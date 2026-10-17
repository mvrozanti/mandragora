#!/usr/bin/env python3
"""Build graph.json for a markdown vault. Parses both [[wikilinks]] and [text](relative.md) links."""
import json
import re
import sys
from pathlib import Path

WIKILINK = re.compile(r"\[\[([^\]\n|#]+)(?:#[^\]\n|]+)?(?:\|[^\]\n]+)?\]\]")
MDLINK = re.compile(r"\[(?:[^\]]+)\]\(([^)\s]+?\.md)(?:#[^)]*)?\)")
SKIP_DIRS = {".obsidian", ".trash", ".git", "node_modules"}
CODE_SPAN = re.compile(r"`[^`\n]*`")
FENCE = re.compile(r"```.*?```", re.DOTALL)


def heading_title(text: str) -> str:
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("# ") and not s.startswith("## "):
            return s[2:].strip()
    return ""


def scan(vault: Path):
    files, names, paths_by_rel = {}, {}, {}
    for p in vault.rglob("*.md"):
        rel = p.relative_to(vault)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        key = p.stem.lower()
        group = rel.parts[0] if len(rel.parts) > 1 else "_root"
        if key in files:
            key = str(rel).lower().replace("/", "__").removesuffix(".md")
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            text = ""
        files[key] = (p.stem, group, p, str(rel), text)
        paths_by_rel[str(rel).lower()] = key
        for name in (
            p.stem,
            heading_title(text),
            str(rel).removesuffix(".md"),
            str(rel).removesuffix(".md").replace("/", "__"),
        ):
            n = name.strip().lower()
            if n:
                names.setdefault(n, key)
    return files, names, paths_by_rel


def resolve_wikilink(target: str, names: dict):
    t = target.strip().lower()
    if not t:
        return None
    if t in names:
        return names[t]
    seg = t.rsplit("/", 1)[-1].strip()
    return names.get(seg)


def resolve_md_target(raw: str, src_rel: str, paths_by_rel: dict):
    target = raw.strip().split("#", 1)[0]
    if not target:
        return None
    src_dir = Path(src_rel).parent
    candidate = (src_dir / target).as_posix()
    while candidate.startswith("../"):
        candidate = candidate[3:]
    candidate = re.sub(r"/+", "/", candidate).lower()
    return paths_by_rel.get(candidate)


def build(vault: Path):
    files, names, paths_by_rel = scan(vault)
    nodes, links, id_index = [], [], {}
    for key, (label, group, _path, rel, _text) in files.items():
        id_index[key] = len(nodes)
        nodes.append({"id": key, "label": label, "group": group, "path": rel, "deg": 0})

    edge_set = set()
    for key, (_label, _group, path, rel, text) in files.items():
        text = FENCE.sub("", text)
        text = CODE_SPAN.sub("", text)
        targets = set()
        for m in WIKILINK.finditer(text):
            t = resolve_wikilink(m.group(1), names)
            if t is None:
                t = m.group(1).strip().lower()
                if t not in id_index:
                    id_index[t] = len(nodes)
                    nodes.append({"id": t, "label": t, "group": "_unresolved", "deg": 0})
            targets.add(t)
        for m in MDLINK.finditer(text):
            r = resolve_md_target(m.group(1), rel, paths_by_rel)
            if r:
                targets.add(r)
        for t in targets:
            if t == key:
                continue
            pair = (key, t) if key < t else (t, key)
            if pair in edge_set:
                continue
            edge_set.add(pair)
            links.append({"source": key, "target": t})
            nodes[id_index[key]]["deg"] += 1
            nodes[id_index[t]]["deg"] += 1
    return {"nodes": nodes, "links": links}


def main():
    if len(sys.argv) < 2:
        print("usage: build_graph.py <vault-dir> [out.json]")
        sys.exit(2)
    vault = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).parent / "graph.json"
    g = build(vault)
    out.write_text(json.dumps(g, separators=(",", ":")))
    print(f"{len(g['nodes'])} nodes, {len(g['links'])} links → {out}")


if __name__ == "__main__":
    main()
