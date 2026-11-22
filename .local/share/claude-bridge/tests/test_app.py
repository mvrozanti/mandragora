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


QUESTION = """──────────────────────────────────────────────────────────────
←  ☐ Format  ☒ Scope  ✔ Submit  →
Which output format do you want for this task?
❯ 1. Short summary (Recommended)
     A few sentences with the key result. Fastest to read.
  2. Detailed report
     Full explanation with every step and supporting detail.
  3. Type something.
──────────────────────────────────────────────────────────────
  4. Chat about this
Enter to select · Tab/Arrow keys to navigate · Esc to cancel
"""

CHECKBOXES = """──────────────────────────────────────────────────────────────
←  ☐ Format  ☒ Scope  ✔ Submit  →
Which areas should I include in the work?
❯ 1. [✔] Code changes
         Edit files in the repository as needed.
  2. [ ] Verification
         Run checks or tests after making changes.
  3. [ ] Type something
     Submit
──────────────────────────────────────────────────────────────
  4. Chat about this
Enter to select · Tab/Arrow keys to navigate · Esc to cancel
"""

REVIEW = """──────────────────────────────────────────────────────────────
←  ☐ Format  ☒ Scope  ✔ Submit  →
Review your answers
⚠ Some questions are unanswered
❯ 1. Submit answers
  2. Cancel
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


def parsed_screen(screen: str) -> dict:
    result = app.parse_screen(screen)
    assert result is not None
    return result


def test_a_permission_dialog_splits_its_question_from_the_command():
    parsed = parsed_screen(PERMISSION)
    assert parsed["title"] == "Do you want to proceed?"
    assert "rm -rf build" in parsed["context"]
    assert parsed["steps"] == []
    assert [o["checked"] for o in parsed["options"]] == [None, None, None]


def test_a_question_dialog_carries_its_steps_and_options():
    parsed = parsed_screen(QUESTION)
    assert parsed["steps"] == [{"label": "Format", "done": False}, {"label": "Scope", "done": True}, {"label": "Submit", "done": False}]
    assert parsed["title"] == "Which output format do you want for this task?"
    assert parsed["context"] == ""
    assert "☐" not in parsed["question"]
    options = parsed["options"]
    assert options[0]["label"] == "Short summary (Recommended)"
    assert options[0]["detail"].startswith("A few sentences")
    assert options[2]["text"]
    assert [o["aside"] for o in options] == [False, False, False, True]


def test_checkboxes_come_without_their_boxes():
    options = parsed_screen(CHECKBOXES)["options"]
    assert [(o["label"], o["checked"]) for o in options[:3]] == [("Code changes", True), ("Verification", False), ("Type something", False)]
    assert options[2]["text"]


def test_ticking_a_box_makes_a_new_screen():
    ticked = CHECKBOXES.replace("[ ] Verification", "[✔] Verification")
    assert app.screen_id("s1", parsed_screen(ticked)) != app.screen_id("s1", parsed_screen(CHECKBOXES))
    assert app.screen_id("s1", parsed_screen(CHECKBOXES)) == app.screen_id("s1", parsed_screen(CHECKBOXES))

def test_the_step_shown_is_found_from_the_pending_question():
    pending = [{"name": "AskUserQuestion", "input": {"questions": [
        {"question": "Which output format do you want for this task?"},
        {"question": "Which areas should I include in the work?"},
    ]}}]
    assert app.screen_step(parsed_screen(QUESTION), pending) == 0
    assert app.screen_step(parsed_screen(CHECKBOXES), pending) == 1
    assert app.screen_step(parsed_screen(REVIEW), pending) == 2
    assert app.screen_step(parsed_screen(QUESTION), []) == -1
    assert app.screen_step(parsed_screen(PERMISSION), pending) == -1


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


def record(uid: str, parent: str | None, kind: str, content, source: str | None = None) -> str:
    line = {"type": kind, "uuid": uid, "parentUuid": parent, "isSidechain": False, "message": {"role": kind, "content": content}}
    if source is not None:
        line["promptSource"] = source
    return json.dumps(line)


def user_texts(entries: list[dict]) -> list[str]:
    return [part["text"] for entry in entries if entry["info"]["role"] == "user" for part in entry["parts"] if part.get("type") == "text"]


def test_a_prompt_dequeued_into_a_rejected_tool_call_still_shows(tmp_path):
    call = [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {}}]
    rejected = [{"type": "tool_result", "tool_use_id": "t1", "content": "rejected", "is_error": True}]
    path = tmp_path / "s.jsonl"
    path.write_text("\n".join([
        record("a1", None, "user", "check the vps disk", "typed"),
        record("a2", "a1", "assistant", call),
        record("q1", "a2", "user", "in the phone app i mean", "queued"),
        record("r1", "a2", "user", rejected),
        record("r2", "r1", "user", [{"type": "text", "text": "[Request interrupted by user for tool use]"}]),
        record("a3", "r2", "user", "in the phone app", "typed"),
    ]) + "\n")
    assert user_texts(app.transcript_entries("s", path, 0)) == ["check the vps disk", "in the phone app i mean", "in the phone app"]


def test_a_stray_prompt_said_again_later_shows_once(tmp_path):
    call = [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {}}]
    rejected = [{"type": "tool_result", "tool_use_id": "t1", "content": "rejected", "is_error": True}]
    path = tmp_path / "s.jsonl"
    path.write_text("\n".join([
        record("a1", None, "user", "go", "typed"),
        record("a2", "a1", "assistant", call),
        record("q1", "a2", "user", "again", "queued"),
        record("r1", "a2", "user", rejected),
        record("a3", "r1", "user", "again", "typed"),
    ]) + "\n")
    assert user_texts(app.transcript_entries("s", path, 0)) == ["go", "again"]


def test_a_rewound_typed_prompt_stays_hidden(tmp_path):
    path = tmp_path / "s.jsonl"
    path.write_text("\n".join([
        record("a1", None, "user", "first", "typed"),
        record("a2", "a1", "assistant", [{"type": "text", "text": "ok"}]),
        record("old", "a2", "user", "abandoned edit", "typed"),
        record("new", "a2", "user", "rewritten", "typed"),
    ]) + "\n")
    assert user_texts(app.transcript_entries("s", path, 0)) == ["first", "rewritten"]
