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


def test_watch_command_is_reachable_and_lists_templates(db):
    out = asyncio.run(tg._cmd_watch(db, []))
    assert "watch templates" in out


def test_watch_command_with_a_sentence_reaches_the_composer(db, monkeypatch):
    import compose
    import llm

    async def boom(system, prompt):
        raise llm.NoProviderAvailable("no model provider configured")

    monkeypatch.setattr(compose.llm, "complete", boom)
    out = asyncio.run(tg._cmd_watch(db, ["tell", "me", "about", "kindle", "jailbreaks"]))
    assert "no model provider configured" in out
    assert "/watch" in out


def test_watch_command_with_a_template_name_takes_the_model_free_path(db, monkeypatch):
    import compose

    seen = {}

    async def fake_preview(template, args):
        seen["template"] = template
        seen["args"] = args
        return {"plan": {"name": "n", "condition": "c", "stop_after": 0, "sources": []},
                "sources": [], "warnings": [], "usable": 0}

    monkeypatch.setattr(compose, "preview", fake_preview)
    asyncio.run(tg._cmd_watch(db, ["advisory", "spesmilo/electrum"]))
    assert seen == {"template": "advisory", "args": ["spesmilo/electrum"]}


def test_every_command_in_help_has_a_dispatch_branch():
    import re

    plain = re.sub(r"<[^>]+>", " ", tg.HELP)
    advertised = set(re.findall(r"/([a-z]+)", plain))
    dispatch = _module_source().split("async def _dispatch")[1]
    handled = set(re.findall(r'cmd == "/([a-z]+)"', dispatch))
    missing = sorted(advertised - handled - {"watch"})
    assert not missing, f"advertised in HELP but not dispatched: {missing}"
    assert '"/watch"' in dispatch
