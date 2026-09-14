import ast
import asyncio
import inspect
import pathlib

import pytest

import telegram as tg


def _module_source() -> str:
    return pathlib.Path(inspect.getfile(tg)).read_text()


def _find_func(func_name: str):
    tree = ast.parse(_module_source())
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == func_name:
            return node
    raise AssertionError(f"{func_name} is not defined in telegram.py")


def _bound_inside(node) -> set[str]:
    bound = {a.arg for a in node.args.args + node.args.kwonlyargs}
    if node.args.vararg:
        bound.add(node.args.vararg.arg)
    if node.args.kwarg:
        bound.add(node.args.kwarg.arg)
    for sub in ast.walk(node):
        if isinstance(sub, ast.Name) and isinstance(sub.ctx, (ast.Store, ast.Del)):
            bound.add(sub.id)
        elif isinstance(sub, (ast.Import, ast.ImportFrom)):
            for a in sub.names:
                bound.add(a.asname or a.name.split(".")[0])
        elif isinstance(sub, ast.ExceptHandler) and sub.name:
            bound.add(sub.name)
        elif isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef)) and sub is not node:
            bound.add(sub.name)
    return bound


def _free_names(func_name: str) -> set[str]:
    node = _find_func(func_name)
    loaded = {
        sub.id for sub in ast.walk(node)
        if isinstance(sub, ast.Name) and isinstance(sub.ctx, ast.Load)
    }
    return loaded - _bound_inside(node)


def _module_level_names() -> set[str]:
    tree = ast.parse(_module_source())
    names = set()
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name):
                    names.add(t.id)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            names.add(node.target.id)
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            for a in node.names:
                names.add(a.asname or a.name.split(".")[0])
    return names


@pytest.mark.parametrize("entry", ["_dispatch", "_handle_callback"])
def test_every_name_an_entrypoint_calls_actually_exists(entry):
    import builtins

    known = _module_level_names() | set(dir(tg)) | set(dir(builtins))
    missing = sorted(n for n in _free_names(entry) if n not in known)
    assert not missing, f"{entry} references names that do not exist: {missing}"


def test_watch_command_with_no_args_asks_for_a_condition(db):
    out = asyncio.run(tg._cmd_watch(db, []))
    assert "condition" in out.lower()


def test_watch_command_with_a_sentence_reaches_the_composer(db, monkeypatch):
    import compose
    import llm

    async def boom(system, prompt):
        raise llm.NoProviderAvailable("no model provider configured")

    monkeypatch.setattr(compose.llm, "complete", boom)
    out = asyncio.run(tg._cmd_watch(db, ["tell", "me", "about", "kindle", "jailbreaks"]))
    assert "no model provider configured" in out
    assert "/add" in out


def _leaked_kinds(text: str) -> list[str]:
    import sources

    return [k for k in sources.SOURCE_KINDS if k in text]


def test_the_help_never_names_a_source_kind(db):
    assert _leaked_kinds(tg.HELP) == []


def test_the_watch_prompt_never_names_a_source_kind(db):
    out = asyncio.run(tg._cmd_watch(db, []))
    assert _leaked_kinds(out) == []


def test_the_created_reply_names_the_condition_not_the_plumbing(db, monkeypatch):
    import compose

    async def fake_quick(text):
        return {
            "plan": {"name": "bf on linux", "condition": text, "stop_after": 0, "sources": []},
            "sources": [],
            "rows": [{"condition": text, "kind": "anticheat_game", "target": "battlefield",
                      "name": "bf on linux", "match_rule": '"now Supported"',
                      "stop_after": 0, "watch_group": "g1"}],
            "warnings": [], "provider": "stub", "estimates": {},
        }

    monkeypatch.setattr(compose, "quick_create", fake_quick)
    out = asyncio.run(tg._cmd_watch(db, "a battlefield game runs on linux".split()))
    assert "a battlefield game runs on linux" in out
    assert _leaked_kinds(out) == []
    assert "now Supported" not in out


def test_the_list_shows_conditions_not_targets(db, make_watcher):
    wid = make_watcher(kind="anticheat_game", target="battlefield", ai_spec=None)
    c = db()
    c.execute("UPDATE watchers SET condition = ? WHERE id = ?",
              ("a battlefield game runs on linux", wid))
    c.close()
    out = asyncio.run(tg._cmd_list(db))
    assert "a battlefield game runs on linux" in out
    assert _leaked_kinds(out) == []


def test_every_command_in_help_has_a_dispatch_branch():
    import re

    plain = re.sub(r"<[^>]+>", " ", tg.HELP)
    advertised = set(re.findall(r"/([a-z]+)", plain))
    dispatch = _module_source().split("async def _dispatch")[1]
    handled = set(re.findall(r'cmd == "/([a-z]+)"', dispatch))
    missing = sorted(advertised - handled - {"watch"})
    assert not missing, f"advertised in HELP but not dispatched: {missing}"
    assert '"/watch"' in dispatch
