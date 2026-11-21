import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

os.environ["CLAUDE_BRIDGE_LOCAL_MODELS"] = json.dumps([{"name": "cc-qwen3.6"}, {"name": "cc-gptoss"}])
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app

PERMISSION = """ Bash command

   rm -rf build
   Remove the build folder

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for rm commands
   3. No, and tell Claude what to do differently (esc)
"""


def test_desk_command_starts_or_resumes_with_the_chosen_settings():
    fresh = app.desk_command("s1", "claude", "opus", {"mode": "default", "effort": "high"}, fresh=True)
    assert fresh == ["claude", "--session-id", "s1", "--permission-mode", "manual", "--model", "opus", "--effort", "high"]
    resumed = app.desk_command("s1", "deepseek", None, {"mode": "plan", "effort": None}, fresh=False)
    assert resumed == ["deepseek", "--resume", "s1", "--permission-mode", "plan"]


def test_upload_names_cannot_escape_or_hide():
    escaped = app.upload_name("../../etc/passwd")
    assert "/" not in escaped
    assert not escaped.startswith(".")
    assert escaped.endswith("etc_passwd")
    assert app.upload_name(".bashrc") == "bashrc"
    assert app.upload_name("a\x00b\nc.txt") == "a_b_c.txt"
    assert app.upload_name("   ") == ""
    long = app.upload_name("x" * 300 + ".verylongextension")
    assert len(long) <= 112
    assert long.startswith("x" * 100)


def test_existing_dirs_keeps_only_real_folders(tmp_path):
    (tmp_path / "file").write_text("x")
    paths = [str(tmp_path), str(tmp_path / "file"), str(tmp_path / "missing"), None, ""]
    assert app.existing_dirs(paths) == {str(tmp_path)}


def test_models_map_to_providers_and_aliases():
    assert app.local_name("cc-qwen3.6:latest") == "cc-qwen3.6"
    assert app.local_name("llama") is None
    assert app.provider_of("cc-gptoss") == "local"
    assert app.provider_of("deepseek-v4-flash") == "deepseek"
    assert app.provider_of("claude-opus-5-5") == "claude"
    assert app.provider_of(None) == "claude"
    assert app.model_alias("claude", "claude-opus-5-5") == "opus"
    assert app.model_alias("claude", None) == "default"
    assert app.model_alias("deepseek", "deepseek-v4-flash") == "deepseek-v4-flash"
    assert app.model_alias("deepseek", "something-else") == "deepseek-v4-pro"
    assert app.model_alias("local", "cc-gptoss:latest") == "cc-gptoss"


def test_message_content_reads_as_text_and_blocks():
    assert app.text_of("plain") == "plain"
    assert app.text_of([{"type": "text", "text": "a"}, {"type": "image"}, "junk", {"type": "text", "text": "b"}]) == "a\nb"
    assert app.text_of(None) == ""
    assert app.blocks_of("hi") == [{"type": "text", "text": "hi"}]
    assert app.blocks_of([{"type": "x"}, 3]) == [{"type": "x"}]
    assert app.blocks_of(7) == []


def test_tool_calls_summarize_to_their_first_meaningful_line():
    assert app.summarize("Bash", {"command": "git status\ngit log"}) == "git status"
    assert app.summarize("Read", {"file_path": "/etc/hosts"}) == "/etc/hosts"
    assert app.summarize("Todo", {"items": []}) == "Todo"
    assert len(app.summarize("Bash", {"command": "x" * 500})) == 200


def test_times_normalize_to_milliseconds():
    moment = datetime(2026, 11, 21, 12, 0, tzinfo=timezone.utc)
    expected = int(moment.timestamp() * 1000)
    assert app.to_ms(None) == 0
    assert app.to_ms(moment) == expected
    assert app.to_ms(moment.timestamp()) == expected
    assert app.to_ms(expected) == expected
    assert app.to_ms("2026-11-21T12:00:00Z") == expected
    assert app.to_ms("yesterday") == 0


def test_a_permission_dialog_parses_into_options():
    parsed = app.parse_screen(PERMISSION)
    assert parsed is not None
    assert parsed["question"].endswith("Do you want to proceed?")
    assert [o["key"] for o in parsed["options"]] == ["1", "2", "3"]
    assert parsed["options"][0]["current"]
    assert parsed["options"][2]["text"]
    assert app.parse_screen("nothing to answer here") is None
    assert app.parse_screen(" ❯ 1. Only one choice") is None


def test_the_model_picker_and_effort_read_from_the_pane():
    assert app.picker_options(["Select model", " ❯ 1. Default (recommended)  ✔", "   2. Opus"]) == [(True, "Default (recommended)"), (False, "Opus")]
    assert app.picked_effort(["x", "◐ high effort (default) ←/→ to adjust"]) == ("high", True)
    assert app.picked_effort(["● max effort ←/→"]) == ("max", False)
    assert app.picked_effort(["no effort line"]) is None


def test_plans_are_read_only_from_the_plans_folder(tmp_path, monkeypatch):
    monkeypatch.setattr(app, "PLANS", tmp_path)
    inside = tmp_path / "p.md"
    inside.write_text("the plan")
    outside = tmp_path.parent / "elsewhere.md"
    outside.write_text("not this")
    assert app.plan_text({"planFilePath": str(inside)}) == "the plan"
    assert app.plan_text({"planFilePath": str(outside), "plan": "inline"}) == "inline"
    assert app.plan_text({}) is None


@pytest.mark.parametrize(
    ("content", "expected"),
    [('{"model": "opus"}', "opus"), ('{"model": ""}', "default"), ("not json", "default"), ("[]", "default")],
)
def test_the_configured_model_falls_back_to_default(tmp_path, monkeypatch, content, expected):
    settings = tmp_path / "settings.json"
    settings.write_text(content)
    monkeypatch.setattr(app, "USER_SETTINGS", settings)
    assert app.configured_model() == expected


def transcript_line(kind: str, model: str | None = None, sidechain: bool = False) -> str:
    record = {"type": kind, "uuid": "u", "isSidechain": sidechain, "message": {"role": kind}}
    if model is not None:
        record["message"]["model"] = model
    return json.dumps(record)


def test_the_last_main_assistant_model_names_the_conversation():
    lines = [
        transcript_line("assistant", "claude-opus-5-5"),
        transcript_line("assistant", "deepseek-v4-pro"),
        transcript_line("assistant", "claude-haiku-4-5", sidechain=True),
        transcript_line("assistant", "<synthetic>"),
        transcript_line("user"),
        "not json \"assistant\"",
    ]
    assert app.assistant_model("\n".join(lines).encode()) == "deepseek-v4-pro"
    assert app.assistant_model(transcript_line("user").encode()) is None


def test_transcript_models_read_tails_and_remember_them(tmp_path, monkeypatch):
    monkeypatch.setattr(app, "TRANSCRIPTS", tmp_path)
    monkeypatch.setattr(app, "TAIL_REACH", (64, 1 << 20))
    monkeypatch.setattr(app, "tail_models", {})
    folder = tmp_path / "-home-m"
    folder.mkdir()
    early = folder / "s1.jsonl"
    early.write_text(transcript_line("assistant", "cc-gptoss") + "\n" + transcript_line("user") * 4 + "\n")
    (folder / "s2.jsonl").write_text(transcript_line("user") + "\n")
    assert app.transcript_models(["s1", "s2", "s3"]) == {"s1": "cc-gptoss"}
    with early.open("a") as handle:
        handle.write("x" * 2048 + "\n")
    monkeypatch.setattr(app, "TAIL_REACH", (64,))
    assert app.transcript_models(["s1"]) == {"s1": "cc-gptoss"}
    assert app.tail_model(folder / "gone.jsonl") is None
