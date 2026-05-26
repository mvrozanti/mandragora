import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import requests


def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def walk_vault(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for f in filenames:
            if f.startswith(".") or not f.endswith(".md"):
                continue
            yield Path(dirpath) / f


def load_state(path):
    if path.exists():
        return json.loads(path.read_text())
    return {"sources": {}}


def save_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2, sort_keys=True))


def get_or_create_notebook(api, name):
    r = requests.get(f"{api}/api/notebooks", timeout=30)
    r.raise_for_status()
    for nb in r.json():
        if nb.get("name") == name:
            return nb["id"]
    r = requests.post(
        f"{api}/api/notebooks",
        json={"name": name, "description": "Mandragora knowledge vault mirror"},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["id"]


def list_sources_in_notebook(api, notebook_id):
    r = requests.get(
        f"{api}/api/sources",
        params={"notebook_id": notebook_id, "limit": 10000},
        timeout=60,
    )
    r.raise_for_status()
    data = r.json()
    return data.get("items", data) if isinstance(data, dict) else data


def create_source(api, notebook_id, title, content, embed):
    r = requests.post(
        f"{api}/api/sources/json",
        json={
            "type": "text",
            "title": title,
            "content": content,
            "notebooks": [notebook_id],
            "embed": embed,
            "async_processing": False,
        },
        timeout=120,
    )
    r.raise_for_status()
    return r.json()["id"]


def delete_source(api, source_id):
    r = requests.delete(f"{api}/api/sources/{source_id}", timeout=30)
    if r.status_code not in (200, 204, 404):
        r.raise_for_status()


def main():
    ap = argparse.ArgumentParser(description="Sync vault markdown into Open Notebook")
    ap.add_argument(
        "--vault",
        default=os.environ.get(
            "NB_VAULT_DIR", "/home/m/Documents/mandragora-desktop-obsidian-vault"
        ),
    )
    ap.add_argument(
        "--api",
        default=os.environ.get("NB_API_URL", "http://100.84.78.83:5055"),
        help="Open Notebook API base (default: tailnet-bound 5055 on VPS).",
    )
    ap.add_argument("--notebook", default=os.environ.get("NB_NOTEBOOK", "vault"))
    ap.add_argument(
        "--state",
        default=os.environ.get(
            "NB_STATE", os.path.expanduser("~/.local/state/nb-vault-sync/state.json")
        ),
    )
    ap.add_argument("--embed", action="store_true", help="Embed content (LLM cost).")
    ap.add_argument(
        "--dry-run", action="store_true", help="Print actions without API calls."
    )
    args = ap.parse_args()

    vault = Path(args.vault).resolve()
    if not vault.is_dir():
        print(f"vault not found: {vault}", file=sys.stderr)
        sys.exit(2)

    state_path = Path(args.state)
    state = load_state(state_path)
    src_state = state.setdefault("sources", {})

    api = args.api.rstrip("/")
    notebook_id = (
        get_or_create_notebook(api, args.notebook) if not args.dry_run else "DRY"
    )
    print(f"notebook '{args.notebook}' id={notebook_id}")

    files = {}
    for p in walk_vault(vault):
        rel = str(p.relative_to(vault))
        files[rel] = p

    created = updated = deleted = unchanged = 0

    for rel, p in sorted(files.items()):
        content = p.read_text(encoding="utf-8", errors="replace")
        h = sha256(content)
        prev = src_state.get(rel)

        if prev and prev.get("sha256") == h:
            unchanged += 1
            continue

        if prev and prev.get("source_id"):
            print(f"~ {rel}")
            if not args.dry_run:
                delete_source(api, prev["source_id"])
            updated += 1
        else:
            print(f"+ {rel}")
            created += 1

        if args.dry_run:
            new_id = "DRY"
        else:
            new_id = create_source(api, notebook_id, rel, content, args.embed)
        src_state[rel] = {"source_id": new_id, "sha256": h}

    for rel in list(src_state.keys()):
        if rel not in files:
            print(f"- {rel}")
            if not args.dry_run and src_state[rel].get("source_id"):
                delete_source(api, src_state[rel]["source_id"])
            del src_state[rel]
            deleted += 1

    if not args.dry_run:
        save_state(state_path, state)

    print(
        f"done: created={created} updated={updated} deleted={deleted} unchanged={unchanged}"
    )


if __name__ == "__main__":
    main()
