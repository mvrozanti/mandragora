#!/usr/bin/env python3
import importlib.util
import json
import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("progress_hud", os.path.join(HERE, "progress_hud.py"))
assert SPEC is not None and SPEC.loader is not None
sl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sl)

def slurp(path):
    with open(path) as f:
        return f.read()


G, M, C, Y, D, R = sl.TONE["parsed"], sl.TONE["unknown"], sl.TONE["estimate"], sl.TONE["over"], sl.DIM, sl.RESET

BASH_TOOL_WRAPPER = [
    "/run/current-system/sw/bin/zsh",
    "-c",
    "source /home/m/.claude/shell-snapshots/snapshot-zsh-1791805252015-jwwynd.sh 2>/dev/null || true"
    " && setopt NO_EXTENDED_GLOB NO_BARE_GLOB_QUAL 2>/dev/null || true"
    " && { \\builtin unalias -- 'unsetenv'; \\builtin unset -f -- 'unsetenv'; } >/dev/null 2>&1 || true"
    " && eval 'cd /tmp && rtk nix build .#x 2>&1 | tail -3' && pwd -P >| /tmp/claude-f0ec-cwd",
]

NOW = 1045.0
TASKS = [
    {"key": "nix build .#x", "start": 1000.0, "mtime": 1040.0, "last": "building derivation 3", "progress": None, "estimate": None},
    {"key": "nix build .#x", "start": 1000.0, "mtime": 1040.0, "last": "[3/40 built]", "progress": 0.075, "estimate": 120.0},
    {"key": "nix build .#x", "start": 1000.0, "mtime": 1040.0, "last": "", "progress": None, "estimate": 120.0},
    {"key": "nix build .#x", "start": 900.0, "mtime": 1000.0, "last": "x", "progress": None, "estimate": 100.0},
    {"key": "a" * 80, "start": 1000.0, "mtime": 1000.0, "last": "y" * 200, "progress": 0.5, "estimate": None},
]
ROWS = {
    (0, 20): f"{M}⠴{R} nix build .… {D}░░{R}{M}███{R}{D}░{R} 45s",
    (0, 60): f"{M}⠴{R} nix build .#x {D}░░{R}{M}███{R}{D}░░░░░░░{R} 45s  {D}building derivation 3{R}",
    (0, 120): f"{M}⠴{R} nix build .#x {D}░░░░░░░░░░{R}{M}███{R}{D}░░░░░░░░░░░{R} 45s  {D}building derivation 3{R}",
    (1, 20): f"{G}⠴{R} nix build .… {G}▍{R}{D}░░░░░{R}   8% 45s",
    (1, 60): f"{G}⠴{R} nix build .#x {G}▉{R}{D}░░░░░░░░░░░{R}   8% 45s  {D}[3/40 built]{R}",
    (1, 120): f"{G}⠴{R} nix build .#x {G}█▊{R}{D}░░░░░░░░░░░░░░░░░░░░░░{R}   8% 45s  {D}[3/40 built]{R}",
    (2, 20): f"{C}⠴{R} nix build .… {C}██▎{R}{D}░░░{R} ~38% 45s/~2m00s",
    (2, 60): f"{C}⠴{R} nix build .#x {C}████▌{R}{D}░░░░░░░{R} ~38% 45s/~2m00s",
    (2, 120): f"{C}⠴{R} nix build .#x {C}█████████{R}{D}░░░░░░░░░░░░░░░{R} ~38% 45s/~2m00s",
    (3, 20): f"{Y}⠴{R} nix build .… {Y}██████{R}{D}{R} 2m25s +45s",
    (3, 60): f"{Y}⠴{R} nix build .#x {Y}████████████{R}{D}{R} 2m25s +45s  {Y}quiet 45s{R}",
    (3, 120): f"{Y}⠴{R} nix build .#x {Y}████████████████████████{R}{D}{R} 2m25s +45s  {Y}quiet 45s{R}",
    (4, 20): f"{G}⠴{R} aaaaaaaaaaa… {G}███{R}{D}░░░{R}  50% 45s",
    (4, 60): f"{G}⠴{R} aaaaaaaaaaaaaa… {G}██████{R}{D}░░░░░░{R}  50% 45s  {Y}quiet 45s{R}",
    (4, 120): f"{G}⠴{R} {'a' * 29}… {G}████████████{R}{D}░░░░░░░░░░░░{R}  50% 45s  {Y}quiet 45s{R}",
    (4, 200): f"{G}⠴{R} {'a' * 47}… {G}████████████{R}{D}░░░░░░░░░░░░{R}  50% 45s  {Y}quiet 45s{R}",
}


class CommandKeys(unittest.TestCase):
    def test_bash_tool_wrapper_yields_the_users_command(self):
        self.assertEqual(sl.extract_command(BASH_TOOL_WRAPPER), "cd /tmp && rtk nix build .#x 2>&1 | tail -3")
        self.assertEqual(sl.normalize(sl.extract_command(BASH_TOOL_WRAPPER)), "nix build .#x 2>&1 | tail -3")

    def test_plain_argv_is_joined(self):
        self.assertEqual(sl.extract_command(["sleep", "5"]), "sleep 5")

    def test_normalize_strips_prefixes_and_wrappers(self):
        cases = {
            "  spaced   out  ": "spaced out",
            "FOO=1 BAR=2 sudo nixos-rebuild switch": "nixos-rebuild switch",
            "cd /tmp && rtk git status": "git status",
            "cd a; cd b && time make -j8": "make -j8",
            "timeout -k 2 10s nix build .#x": "nix build .#x",
            "timeout 5 tail -f /dev/null": "tail -f /dev/null",
            "rtk": "rtk",
            "x" * 300: "x" * 200,
            "rtk cd $W && python3 - <<x": "python3 - <<x",
            "X=1 && git status": "git status",
            "cd /a && FOO=1 rtk cd /b; timeout 9 make": "make",
        }
        for command, key in cases.items():
            self.assertEqual(sl.normalize(command), key, command)

    def test_family_is_program_plus_subcommand(self):
        cases = {
            "/usr/bin/make -j8": "make",
            "for i in $(seq 1 3); do :; done": "for i",
            "git -C /x status": "git",
            "mandragora-switch": "mandragora-switch",
            "nix build .#x": "nix build",
            "tail -f /dev/null": "tail",
        }
        for key, group in cases.items():
            self.assertEqual(sl.family(key), group, key)


class Parsing(unittest.TestCase):
    def test_progress_from_output(self):
        cases = [
            (["downloading 15%", "downloading 16%"], 0.16),
            (["[3/40 built] compiling"], 0.075),
            (["step 2 of 10"], 0.2),
            (["2026/10/12 nothing"], None),
            (["45% then", "installing collected packages"], 0.45),
            (["150% nope"], None),
            (["1/1"], None),
            (["0/5"], 0.0),
            (["a/b", "x of y"], None),
            ([], None),
        ]
        for lines, expected in cases:
            self.assertEqual(sl.parse_progress(lines), expected, lines)

    def test_output_tail_splits_carriage_returns_and_strips_ansi(self):
        with tempfile.NamedTemporaryFile("wb", delete=False) as f:
            f.write(b"\x1b[32mstart\x1b[0m\n" + b"\r".join(b"%d%%" % i for i in range(0, 100, 10)) + b"\n")
            path = f.name
        try:
            lines = sl.output_lines(path)
        finally:
            os.unlink(path)
        self.assertEqual(lines[-1], "90%")
        self.assertEqual(len(lines), sl.TAIL_LINES)
        self.assertEqual(sl.output_lines("/nonexistent"), [])


class History(unittest.TestCase):
    def test_estimate_prefers_exact_then_agreeing_family(self):
        exact = {"nix build": [10, 12, 14], "long": list(range(20))}
        families = {"nix": [100, 20], "tail": [5, 6, 7]}
        cases = [("nix build", "nix", 12), ("nix other", "nix", None), ("tail -f x", "tail", 6), ("zzz", "zzz", None), ("long", "x", 16)]
        for key, group, expected in cases:
            self.assertEqual(sl.estimate({"key": key, "family": group}, exact, families), expected, key)

    def test_median(self):
        for samples, expected in [([1], 1), ([1, 2], 1.5), ([5, 1, 3], 3), ([1, 2, 3, 4], 2.5)]:
            self.assertEqual(sl.median(samples), expected)

    def test_history_ignores_damaged_lines(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write('garbage\n{"k":1}\n{"k":"a","f":"b","d":"3.5","t":1}\n{"k":"a","f":"b","d":4}\n')
            path = f.name
        try:
            exact, families = sl.load_history(path)
        finally:
            os.unlink(path)
        self.assertEqual(exact, {"a": [3.5, 4.0]})
        self.assertEqual(families, {"b": [3.5, 4.0]})
        self.assertEqual(sl.load_history("/nonexistent"), ({}, {}))

    def test_track_records_a_task_once_it_is_gone(self):
        with tempfile.TemporaryDirectory() as d:
            state, history, out = (os.path.join(d, n) for n in ("state.json", "history.jsonl", "task.output"))
            open(out, "w").close()
            os.utime(out, (1004.0, 1004.0))
            task = {"pid": "7", "out": out, "start": 1000.0, "key": "sleep 5", "family": "sleep"}
            sl.track(state, history, [task], 1001.0)
            sl.track(state, history, [task], 1004.5)
            self.assertFalse(os.path.exists(history))
            finished = sl.track(state, history, [], 1010.0)
            entry = json.loads(slurp(history).strip())
            self.assertEqual((entry["k"], entry["f"], entry["d"]), ("sleep 5", "sleep", 4.5))
            saved = json.loads(slurp(state))
            self.assertEqual(saved["tasks"], {})
            self.assertEqual([(d["key"], d["duration"]) for d in finished], [("sleep 5", 4.5)])
            self.assertEqual(sl.track(state, history, [], 1010.0 + sl.LINGER + 1), [])
            sl.track(state, history, [{**task, "start": 1002.0}], 1003.0)
            sl.track(state, history, [], 1004.0)
            self.assertEqual(len(slurp(history).splitlines()), 1)


class Rendering(unittest.TestCase):
    def test_clock(self):
        cases = {-3: "0s", 0: "0s", 59: "59s", 60: "1m00s", 61: "1m01s", 3599: "59m59s", 3600: "1h00m", 3661: "1h01m", 86399: "23h59m"}
        for seconds, text in cases.items():
            self.assertEqual(sl.clock(seconds), text)

    def test_bar(self):
        cases = {
            -1: f"{G}{R}{D}░░░░░░░░{R}",
            0: f"{G}{R}{D}░░░░░░░░{R}",
            0.05: f"{G}▍{R}{D}░░░░░░░{R}",
            0.33: f"{G}██▋{R}{D}░░░░░{R}",
            0.5: f"{G}████{R}{D}░░░░{R}",
            0.999: f"{G}███████▉{R}{D}{R}",
            1: f"{G}████████{R}{D}{R}",
            1.5: f"{G}████████{R}{D}{R}",
        }
        for fraction, text in cases.items():
            self.assertEqual(sl.bar(fraction, 8, G), text, fraction)

    def test_bounce(self):
        cases = {
            0: f"{D}{R}{M}███{R}{D}░░░{R}",
            0.5: f"{D}░{R}{M}███{R}{D}░░{R}",
            1: f"{D}░░{R}{M}███{R}{D}░{R}",
            7: f"{D}░░{R}{M}███{R}{D}░{R}",
            13: f"{D}░░{R}{M}███{R}{D}░{R}",
            21.3: f"{D}{R}{M}███{R}{D}░░░{R}",
        }
        for now, text in cases.items():
            self.assertEqual(sl.bounce(6, now, M), text, now)

    def test_rows_match_goldens(self):
        for (index, cols), expected in ROWS.items():
            self.assertEqual(sl.render(dict(TASKS[index]), NOW, cols), expected, (index, cols))

    def test_rows_fit_the_terminal(self):
        for task in TASKS:
            for cols in (40, 41, 60, 61, 80, 120, 200):
                row = sl.render(dict(task), NOW, cols)
                self.assertLessEqual(len(sl.ANSI.sub("", row)), cols, (task["key"][:12], cols))

    def test_overflow_line(self):
        hidden = [{"key": "a", "start": 0}, {"key": "b", "start": 0}]
        self.assertEqual(sl.rows([], NOW, 80, [], "today"), [])
        self.assertEqual(sl.rows([], NOW, 80, hidden, "today"), [f"{D}  +2 more running{R}"])
        self.assertEqual(sl.rows([], NOW, 80, hidden, "rise"), [f"{D}  +2 more · a, b{R}"])

    def test_oldest_task_comes_first_and_young_ones_wait(self):
        tasks = [{"start": 1040.0}, {"start": 1000.0}, {"start": 1044.0}, {"start": 1020.0}]
        self.assertEqual([t["start"] for t in sl.visible_tasks(tasks, NOW)], [1000.0, 1020.0, 1040.0])

    def test_enrich(self):
        task = {"key": "nix build", "family": "nix", "start": 1000.0}
        got = sl.enrich(task, ["a", "50%"], 999.0, {"nix build": [30]}, {})
        self.assertEqual((got["mtime"], got["last"], got["progress"], got["estimate"]), (1000.0, "50%", 0.5, 30))


MODES = {
    "parsed %": {"progress": 0.38, "src": "38%", "ratio": None, "estimate": None, "samples": [], "last": "    412,048,117  38%   24.71MB/s"},
    "parsed n/m": {"progress": 124 / 312, "src": "124/312", "ratio": (124, 312), "estimate": None, "samples": [], "last": "Building [====>  ] 124/312: tokio"},
    "estimate": {"progress": None, "estimate": 272.8, "samples": [236.6, 309.0], "last": "building '/nix/store/x-system-units.drv'..."},
    "over": {"progress": None, "estimate": 30.0, "samples": [30.0], "last": "==> mixing trailer"},
    "unknown": {"progress": None, "estimate": None, "samples": [], "last": ""},
}


def task_in(mode, **extra):
    return {"key": "mandragora-switch 2>&1 | tail -40", "family": "mandragora-switch", "start": 1000.0, "mtime": 1040.0, **MODES[mode], **extra}


class Styles(unittest.TestCase):
    def test_default_is_rising_dots(self):
        self.assertEqual(sl.DEFAULT_STYLE, "rise")
        self.assertEqual(sl.options([])[2], "rise")

    def test_every_style_draws_every_mode_inside_the_terminal(self):
        for style in sl.STYLES:
            for mode in MODES:
                for cols in (40, 61, 80, 120, 200):
                    lines = sl.rows([task_in(mode)], NOW, cols, [], style)
                    self.assertTrue(lines, (style, mode, cols))
                    for line in lines:
                        self.assertLessEqual(len(sl.ANSI.sub("", line)), cols, (style, mode, cols))

    def test_facts_name_the_mode(self):
        expected = {"parsed %": "parsed", "parsed n/m": "parsed", "estimate": "estimate", "over": "over", "unknown": "unknown"}
        for mode, name in expected.items():
            self.assertEqual(sl.facts(task_in(mode), NOW)["mode"], name)
        done = sl.facts({"key": "x", "start": 900.0, "duration": 61.0, "done": True}, NOW)
        self.assertEqual((done["mode"], done["elapsed"]), ("done", 61.0))

    def test_rising_dots_fill_bottom_up(self):
        full = sl.facts(task_in("parsed %", progress=1.0, src="100%"), NOW)
        gauge = "".join(text for text, _ in sl.rise_gauge(full, NOW, 10))
        self.assertEqual(gauge, "⣿" * 10)
        half = "".join(text for text, _ in sl.rise_gauge(sl.facts(task_in("parsed %", progress=0.5, src="50%"), NOW), NOW, 10))
        self.assertEqual(half, "⣿" * 5 + "⣀" * 5)
        first = "".join(text for text, _ in sl.rise_gauge(sl.facts(task_in("parsed %", progress=1 / 80, src="1%"), NOW), NOW, 10))
        self.assertEqual(first[0], "⡀")
        estimate = "".join(text for text, _ in sl.rise_gauge(sl.facts(task_in("estimate"), NOW), NOW, 10))
        self.assertTrue(set(estimate) <= {"⣤", "⣀", "⡀", "⡄", "⣄", "⣠", "⢀", "⣤"}, estimate)

    def test_field_lingers_as_done_and_reads_a_kitty_palette(self):
        lines = sl.rows([{"key": "make", "start": 900.0, "duration": 61.0, "done": True}], NOW, 120, [], "field")
        self.assertEqual(len(lines), 2)
        self.assertIn("✓ 1m01s", sl.ANSI.sub("", lines[0]))
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("foreground #dee3e5\nbackground #000000\ncolor12 #83d2e3\ncolor1 nonsense\n")
            path = f.name
        try:
            palette = sl.load_palette(path)
        finally:
            os.unlink(path)
        self.assertEqual((palette["run"], palette["back"]), ([0x83, 0xD2, 0xE3], [0, 0, 0]))
        self.assertEqual(sl.load_palette("/nonexistent"), sl.DEFAULT_PALETTE)

    def test_parse_match_keeps_what_it_read(self):
        self.assertEqual(sl.parse_match(["downloading 38 %"]), (0.38, "38%", None))
        self.assertEqual(sl.parse_match(["[3/40 built]"]), (0.075, "3/40", (3, 40)))
        self.assertIsNone(sl.parse_match(["nothing here"]))

    def test_graph_draws_output_activity(self):
        t = sl.facts(task_in("estimate", sizes=[[1000.0, 0], [1020.0, 0], [1030.0, 5000], [1045.0, 5000]]), NOW)
        cells = "".join(text for text, _ in sl.graph_gauge(t, NOW, 20))
        self.assertEqual(cells[1], "⣸")
        self.assertTrue(set(cells[4:]) <= {"⣀"}, cells)


class Options(unittest.TestCase):
    def test_flags(self):
        cases = [
            ([], (None, 3, "rise", None)),
            (["--wrap", ""], ("", 3, "rise", None)),
            (["--wrap=x y"], ("x y", 3, "rise", None)),
            (["--max-rows", "5"], (None, 5, "rise", None)),
            (["--max-rows=2", "--wrap", "z"], ("z", 2, "rise", None)),
            (["--style", "field", "--palette", "~/c.conf"], (None, 3, "field", "~/c.conf")),
            (["--style=today"], (None, 3, "today", None)),
        ]
        for argv, expected in cases:
            self.assertEqual(sl.options(argv), expected, argv)

    def test_rejects_bad_flags(self):
        for argv in (["--max-rows", "0"], ["--max-rows", "x"], ["--bogus"], ["--max-rows"], ["--style", "nope"], ["--palette"]):
            with self.assertRaises(SystemExit):
                sl.options(argv)


if __name__ == "__main__":
    unittest.main()
