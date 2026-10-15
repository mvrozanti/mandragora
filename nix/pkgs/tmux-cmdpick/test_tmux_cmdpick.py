import importlib.util
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("cmdpick", HERE / "tmux-cmdpick.py")
cp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cp)

EXECUTABLES = frozenset({
    "git", "ls", "docker", "nix", "systemctl", "journalctl", "tail", "grep", "find", "cat",
    "watch", "sudo", "convert", "htop", "mandragora-switch", "make", "nvidia-smi", "python3",
    "curl", "ssh", "rsync", "tmux", "zsh", "xargs", "env", "import", "touch", "rm",
    "tmux-cmdpick", "after", "seq", "pgrep", "sleep", "dnsmasq", "chmod",
})
SHELL_NAMES = frozenset({"to", "ll", "g", "f", "jobs", "disable", "cd", "echo", "print"})
SUBS = {
    "git": frozenset({"status", "stash", "push", "pull", "add", "commit", "log", "checkout", "rm", "mv", "clone"}),
    "systemctl": frozenset({"restart", "status", "start", "stop"}),
    "docker": frozenset({"ps", "compose", "run", "logs"}),
    "nix": frozenset({"build", "flake", "run", "develop"}),
}
NAMES = cp.Names(EXECUTABLES | SHELL_NAMES | cp.zsh_names(False), EXECUTABLES, SUBS)

ESC = "\x1b["
CODE = ESC + "38;5;153m"
DIM = ESC + "2m"
OFF = ESC + "39m"
POWERLINE = "    ~/Projects/foo   master  "


def run_all(text, cwd=None, names=NAMES, width=None):
    return cp.extract(text, cwd or tempfile.gettempdir(), names, width)


def run(text, cwd=None, names=NAMES, width=None):
    return [c for c, sure in run_all(text, cwd, names, width) if sure]


def maybes(text, width=None):
    return [c for c, sure in run_all(text, width=width) if not sure]


class Recognises(unittest.TestCase):
    CASES = [
        ("git status", ["git status"]),
        ("  ls -la /tmp", ["ls -la /tmp"]),
        ("cd ..", ["cd .."]),
        ("journalctl -b -u sshd --no-pager | tail -50", ["journalctl -b -u sshd --no-pager | tail -50"]),
        ('git add -p && git commit -m "fix: thing"', ['git add -p && git commit -m "fix: thing"']),
        ("git push origin master", ["git push origin master"]),
        ("FOO=1 BAR=2 make -j8", ["FOO=1 BAR=2 make -j8"]),
        ("sudo systemctl restart nginx", ["sudo systemctl restart nginx"]),
        ("watch -n1 nvidia-smi", ["watch -n1 nvidia-smi"]),
        ('for f in *.png; do convert "$f" -resize 50% "small/$f"; done', ['for f in *.png; do convert "$f" -resize 50% "small/$f"; done']),
        ("ll ~/Projects", ["ll ~/Projects"]),
        ("g TODO src/", ["g TODO src/"]),
        ("sudo -i", ["sudo -i"]),
    ]

    def test_cases(self):
        for text, want in self.CASES:
            with self.subTest(text=text):
                self.assertEqual(run(text), want)


class StripsDecoration(unittest.TestCase):
    CASES = [
        ("m@mandragora:~$ docker ps --format '{{.Names}}'", ["docker ps --format '{{.Names}}'"]),
        ("❯ nix flake update", ["nix flake update"]),
        (POWERLINE + "ls -la", ["ls -la"]),
        ("  2. git push origin master", ["git push origin master"]),
        ("  - systemctl --user restart waybar", ["systemctl --user restart waybar"]),
        ("│ git status          │", ["git status"]),
        ("⎿  rsync -a out/ host:/srv/", ["rsync -a out/ host:/srv/"]),
        ("undo everything: git checkout pre-cleanup-2026-10-10", ["git checkout pre-cleanup-2026-10-10"]),
        ("  68  watch -n1 nvidia-smi", ["watch -n1 nvidia-smi"]),
        ("$ htop", ["htop"]),
        (POWERLINE + "htop", ["htop"]),
    ]

    def test_cases(self):
        for text, want in self.CASES:
            with self.subTest(text=text):
                self.assertEqual(run(text), want)


class FindsCodeInProse(unittest.TestCase):
    CASES = [
        ("⏺ Run " + CODE + "systemctl --user restart waybar" + OFF + " to apply.", ["systemctl --user restart waybar"]),
        ("Use `journalctl -fu waybar` to follow it.", ["journalctl -fu waybar"]),
        ("Both " + CODE + "git rm" + OFF + " and " + CODE + "git mv" + OFF + " work.", ["git mv", "git rm"]),
        (
            "  " + ESC + "35mfor" + OFF + " f " + ESC + "35min" + OFF + " *.png; " + ESC + "35mdo" + OFF
            + " convert " + ESC + '33m"$f"' + OFF + " -resize 50% " + ESC + '33m"small/$f"' + OFF + "; " + ESC + "35mdone" + OFF,
            ['for f in *.png; do convert "$f" -resize 50% "small/$f"; done'],
        ),
        ("You can run git status to see what changed.", ["git status"]),
        ("If that fails, try docker compose up -d and check the logs.", ["docker compose up -d"]),
        ("Then rerun nix flake check.", ["nix flake check"]),
        ('Type "git pull" first.', ["git pull"]),
        ("Otherwise grep -rn TODO src/ will find them.", ["grep -rn TODO src/"]),
    ]

    def test_cases(self):
        for text, want in self.CASES:
            with self.subTest(text=text):
                self.assertEqual(run(text), want)


class SubcommandsDecide(unittest.TestCase):
    def test_line_start_command_with_english_tail(self):
        self.assertEqual(run("systemctl restart waybar if it hangs"), ["systemctl restart waybar"])

    def test_mid_sentence_without_cue_or_flag_is_ambiguous(self):
        self.assertEqual(run("the trick is git stash then pop"), [])
        self.assertEqual(maybes("the trick is git stash then pop"), ["git stash"])

    def test_after_an_article_it_is_a_noun(self):
        self.assertEqual(run_all("Next I'll write the docs and a git log generator."), [])

    def test_wrong_subcommand_is_rejected_even_as_code(self):
        for text in ["git psuh origin master", "`docker restarts`", "docker restarts containers"]:
            with self.subTest(text=text):
                self.assertEqual(run_all(text), [])

    def test_long_flags_before_the_subcommand(self):
        self.assertEqual(run("git --no-pager log -5"), ["git --no-pager log -5"])

    def test_unknown_after_long_flag_is_not_proof_of_error(self):
        self.assertEqual(run("git --git-dir .git status"), ["git --git-dir .git status"])

    def test_tools_without_a_table_are_unaffected(self):
        self.assertEqual(run("journalctl -fu waybar"), ["journalctl -fu waybar"])


class AmbiguousReadings(unittest.TestCase):
    def test_trailing_verb_offers_both(self):
        text = "Pass the flag: journalctl -b --no-pager works."
        self.assertEqual(run(text), ["journalctl -b --no-pager"])
        self.assertEqual(maybes(text), ["journalctl -b --no-pager works"])

    def test_verb_that_might_be_an_argument(self):
        text = "Run git checkout fixes and rebuild."
        self.assertEqual(run(text), ["git checkout"])
        self.assertEqual(maybes(text), ["git checkout fixes"])

    def test_sure_readings_come_before_ambiguous_ones(self):
        text = "journalctl -b --no-pager works for me.\ngit status"
        self.assertEqual(run_all(text), [("git status", True), ("journalctl -b --no-pager", True), ("journalctl -b --no-pager works", False)])

    def test_unambiguous_lines_have_no_alternatives(self):
        self.assertEqual(maybes("git status\nls -la /tmp"), [])

    def test_fzf_marks_and_strips_the_tag(self):
        self.assertEqual(cp.fzf_line("git status", True), "git status")
        self.assertEqual(cp.chosen_command(cp.fzf_line("git checkout fails", False)), "git checkout fails")


class HardWraps(unittest.TestCase):
    TEXT = "  docker compose -f stack.yml up -d --remove-orphans\n  --force-recreate"
    JOINED = "docker compose -f stack.yml up -d --remove-orphans --force-recreate"

    def test_rejoined_when_the_next_word_could_not_fit(self):
        self.assertEqual(run(self.TEXT, width=60), [self.JOINED])

    def test_left_apart_when_the_next_word_would_have_fit(self):
        self.assertEqual(run(self.TEXT, width=80), ["docker compose -f stack.yml up -d --remove-orphans"])

    def test_left_apart_without_a_known_width(self):
        self.assertEqual(run(self.TEXT), ["docker compose -f stack.yml up -d --remove-orphans"])

    def test_three_line_wrap(self):
        text = "  rsync -a --delete --exclude .git\n  --exclude result ./site/\n  host:/srv/site/"
        self.assertEqual(run(text, width=36), ["rsync -a --delete --exclude .git --exclude result ./site/ host:/srv/site/"])

    def test_wrapped_prose_still_finds_the_command(self):
        text = "  If the bar freezes you can run systemctl --user restart\n  waybar to bring it back."
        self.assertEqual(run(text, width=58), ["systemctl --user restart waybar"])

    DIFF = "      7 -    rsync -a --delete ./site/ host:/srv/s\n        -ite/"

    def test_diff_view_breaks_mid_word(self):
        width = len(self.DIFF.split("\n")[0]) + 7
        self.assertEqual(run_all(self.DIFF, width=width), [("rsync -a --delete ./site/ host:/srv/site/", True)])

    def test_diff_context_line_breaks_mid_word(self):
        text = self.DIFF.replace("7 -", "7  ").replace("        -", "         ")
        width = len(text.split("\n")[0]) + 7
        self.assertEqual(run_all(text, width=width), [("rsync -a --delete ./site/ host:/srv/site/", True)])

    def test_only_the_same_marker_continues_a_diff_line(self):
        text = "      7 +    git push origin master\n        Xyz"
        width = len(text.split("\n")[0]) + 7
        self.assertEqual(run(text, width=width), ["git push origin master"])

    def test_numbered_line_starts_a_new_diff_line(self):
        text = self.DIFF.split("\n")[0] + "\n      8 +git push origin master"
        width = len(text.split("\n")[0]) + 7
        self.assertEqual(run(text, width=width), ["git push origin master", "rsync -a --delete ./site/ host:/srv/s"])

    def test_word_ending_on_the_last_column_fits(self):
        self.assertFalse(cp.wraps("a" * 10, "bcd", 14))
        self.assertTrue(cp.wraps("a" * 10, "bcde", 14))

    def test_wide_characters_count_double(self):
        self.assertEqual(cp.display_width("\u754c\u754cab"), 6)
        self.assertTrue(cp.wraps("\u754c" * 5, "abc", 12))
        self.assertFalse(cp.wraps("abcde", "abc", 12))

    def test_truncated_display_is_never_offered(self):
        self.assertEqual(run_all("rsync -a src/ host:/srv/very/long/pa\u2026"), [])


class SubcommandTables(unittest.TestCase):
    def test_lines(self):
        self.assertEqual(cp.parse_subcommands("lines", "add\nstatus\nlg\n"), {"add", "status", "lg"})

    def test_indented_help(self):
        text = "\n".join([
            "Unit Commands:",
            "  [list-units                  List units currently in memory",
            "    [PATTERN\u2026]]",
            "  restart UNIT\u2026              Start or restart one or more units",
            "                               path",
            "  compose*    Docker Compose",
            "  auth:          Authenticate gh",
            "    activewindow        \u2192 Gets the active window",
            "  -h --help    Show this help",
        ])
        self.assertEqual(cp.parse_subcommands("indented", text), {"list-units", "restart", "compose", "auth", "activewindow"})

    def test_tmux(self):
        text = "attach-session (attach) [-dErx]\nclock-mode [-t target-pane]\n"
        self.assertEqual(cp.parse_subcommands("tmux", text), {"attach-session", "attach", "clock-mode"})

    def test_nix(self):
        text = "Help commands:\n  \u00b7 nix help - show help\n  \u00b7 nix flake archive - copy\n"
        self.assertEqual(cp.parse_subcommands("nix", text), {"help", "flake"})

    def test_probes_are_fixed_argv_lists(self):
        for tool, (argv, kind) in cp.SUBCOMMAND_SOURCES.items():
            with self.subTest(tool=tool):
                self.assertEqual(argv[0], tool)
                self.assertIsInstance(argv, tuple)
                self.assertIn(kind, {"lines", "indented", "tmux", "nix"})


class IgnoresProse(unittest.TestCase):
    CASES = [
        "Make sure the tests pass before you commit, and then run the build.",
        "test the change works",
        "for example, run the thing",
        "if you want, rerun it",
        "jobs started through /internal/analysis have no owning user, and the job store skipped",
        "to save",
        DIM + "(disable recaps in /config)" + ESC + "22m",
        "Done.",
        "done",
        "import re",
        "import time",
        "the docker daemon is running",
        "nix flakes are nice",
        "I use git for everything",
        "Error: something failed at line 3",
        "The result was 42, which is fine.",
        "Sources:",
        "# Install",
        "https://example.com/foo",
        "██ 18%",
        "$",
        "$ ",
        "",
        "STOP_LEGACY_TIMERS=0",
        CODE + "~/.config/waybar/config" + OFF,
        CODE + "$EDITOR" + OFF,
        ESC + "1mgit is the culprit here" + ESC + "22m",
        'docker said "no space left on device" when I tried it',
        ESC + "1mjournalctl is the culprit here" + ESC + "22m",
        'curl said "no route to host" when I tried it',
        "the curl binary is missing here",
        "the htop window shows it",
        "the rsync job finished overnight",
        "f = sys.stdin.buffer",
        "g == other",
        "docker restarts containers automatically.",
        "    htop",
        DIM + "(timeout 10m)" + ESC + "22m",
        "(timeout 10m)",
        "watch 5",
    ]

    def test_cases(self):
        for text in self.CASES:
            with self.subTest(text=text):
                self.assertEqual(run_all(text), [])


class SingleWords(unittest.TestCase):
    def test_accepted_after_a_prompt(self):
        self.assertEqual(run("$ htop\n" + POWERLINE + "htop"), ["htop"])

    def test_rejected_elsewhere(self):
        for text in ["    htop", "dnsmasq", "Open `htop` and sort by memory.", CODE + "htop" + OFF]:
            with self.subTest(text=text):
                self.assertEqual(run_all(text), [])


class ClaudeCodeScreens(unittest.TestCase):
    STATUS = ESC + "39m  " + ESC + "36m[Opus 5.5]" + ESC + "38;5;246m \u2502 " + ESC + "33mtmux-cmdpick" + ESC + "38;5;246m " + ESC + "35mgit:(" + ESC + "36mtest/tmux-cmdpick*" + ESC + "35m)" + ESC + "39m"
    DIFF = [
        "     " + ESC + "2m" + ESC + "38;5;231m 53 " + ESC + "0m" + ESC + "38;5;231m     " + ESC + "38;5;81mdef" + ESC + "38;5;231m " + ESC + "38;5;148mtest_cases" + ESC + "38;5;231m(" + ESC + "38;5;208mself" + ESC + "38;5;231m):",
        "     " + ESC + "38;5;77m" + ESC + "48;5;22m 70 +" + ESC + "38;5;231m        (" + ESC + '38;5;186m"$ htop"' + ESC + "38;5;231m, [" + ESC + '38;5;186m"htop"' + ESC + "38;5;231m]),",
    ]
    TOOL_CALL = ESC + "38;5;246m  \u23bf  $ for i in $(seq 1 30); do pgrep -f gource >/dev/null || { echo \"exited after ~${i}x2s\"; break; }; sleep 2; done (23"

    VIEWED_FILE = "     " + ESC + "2m" + ESC + "38;5;231m 55 " + ESC + "0m" + ESC + "38;5;231m   kill rule `STAGE0_KILL_RULE.md`. Day 10: NAV 0.994 at 1x vs CDB 1.003. Liveness = newest sqlite row, nothing else." + ESC + "39m"
    VIEWED_COMMAND = "     " + ESC + "38;5;231m 12 " + ESC + "0m" + ESC + "38;5;231m   git push origin master" + ESC + "39m"

    def test_whole_line_colour_is_not_inline_code(self):
        self.assertEqual(run_all(self.VIEWED_FILE), [])

    def test_command_in_a_viewed_file(self):
        self.assertEqual(run(self.VIEWED_COMMAND), ["git push origin master"])

    HIGHLIGHTED = ESC + "38;5;81mecho" + ESC + "38;5;231m " + ESC + '38;5;186m"exited ' + ESC + "38;5;141mafter ~${i}x2s; break" + ESC + "38;5;231m"

    def test_syntax_highlighted_tokens_are_not_inline_code(self):
        self.assertEqual(run_all(self.HIGHLIGHTED), [])

    def test_status_line(self):
        self.assertEqual(run(self.STATUS), [])

    def test_highlighted_source_in_a_diff(self):
        self.assertEqual(run("\n".join(self.DIFF)), [])

    def test_words_inside_quoted_strings_do_not_start_commands(self):
        self.assertNotIn("after ~${i}x2s", run(self.TOOL_CALL))


class RejectsBrokenShell(unittest.TestCase):
    CASES = [
        "python3 - <<'EOF'",
        "cat <<EOF > out.txt",
        "if true; then",
        'echo "unterminated',
        "git commit -m 'oops",
        "done; ls",
        "frobnicate --all",
        "sudo -u postgres psql -c 'select 1'",
    ]

    def test_cases(self):
        for text in self.CASES:
            with self.subTest(text=text):
                self.assertEqual(run_all(text), [])

    def test_fragment_led_by_a_redirect_offers_only_the_clean_part(self):
        self.assertEqual(run_all("> ~/.config/x.env && chmod 600 ~/.config/x.env"), [("chmod 600 ~/.config/x.env", True)])

    def test_psql_counts_once_installed(self):
        names = cp.Names(NAMES.commands | {"psql"}, NAMES.starters | {"psql"})
        self.assertEqual(run("sudo -u postgres psql -c 'select 1'", names=names), ["sudo -u postgres psql -c 'select 1'"])


class ChecksTheFilesystem(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.cwd = self.dir.name
        script = os.path.join(self.cwd, "run.sh")
        with open(script, "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(script, 0o755)
        with open(os.path.join(self.cwd, "plain.sh"), "w") as f:
            f.write("#!/bin/sh\n")
        with open(os.path.join(self.cwd, "notes.txt"), "w") as f:
            f.write("x\n")

    def tearDown(self):
        self.dir.cleanup()

    def test_relative_executable(self):
        self.assertEqual(run("./run.sh --fast", self.cwd), ["./run.sh --fast"])

    def test_relative_non_executable(self):
        self.assertEqual(run("./plain.sh --fast", self.cwd), [])

    def test_missing_relative_script(self):
        self.assertEqual(run("./configure --prefix=/usr", self.cwd), [])

    def test_collider_with_existing_file(self):
        self.assertEqual(run("tail notes.txt", self.cwd), ["tail notes.txt"])

    def test_collider_with_missing_file(self):
        self.assertEqual(run("tail missing.txt", self.cwd), [])


class Layout(unittest.TestCase):
    def test_newest_first_and_deduplicated(self):
        self.assertEqual(run("git status\nls -la\ngit status"), ["git status", "ls -la"])

    def test_backslash_continuation(self):
        self.assertEqual(run("nix build .#foo \\\n    --dry-run"), ["nix build .#foo --dry-run"])

    def test_osc8_hyperlinks_are_transparent(self):
        link = "\x1b]8;id=1;https://example.com\x1b\\"
        self.assertEqual(run(link + "git log --oneline" + "\x1b]8;;\x1b\\"), ["git log --oneline"])


class NeverExecutes(unittest.TestCase):
    def test_candidates_are_parsed_not_run(self):
        with tempfile.TemporaryDirectory() as d:
            markers = [os.path.join(d, "m%d" % i) for i in range(4)]
            victim = os.path.join(d, "victim")
            os.mkdir(victim)
            text = "\n".join([
                "echo $(touch %s)" % markers[0],
                "git status; touch %s" % markers[1],
                "Run `touch -c %s` now." % markers[2],
                "ls `touch %s`" % markers[3],
                "rm -rf %s" % victim,
            ])
            found = run(text, d)
            self.assertIn("echo $(touch %s)" % markers[0], found)
            self.assertIn("git status; touch %s" % markers[1], found)
            self.assertIn("ls `touch %s`" % markers[3], found)
            self.assertIn("rm -rf %s" % victim, found)
            for m in markers:
                self.assertFalse(os.path.exists(m), m)
            self.assertTrue(os.path.isdir(victim))


class Helpers(unittest.TestCase):
    def test_styled_spans(self):
        line = "a " + CODE + "one" + OFF + " b " + DIM + "quiet" + ESC + "22m " + ESC + "1mtwo" + ESC + "0m " + CODE + "three"
        self.assertEqual(cp.styled_spans(line), ["one", "two", "three"])

    def test_adjacent_colours_split(self):
        self.assertEqual(cp.styled_spans(ESC + "31mred" + ESC + "32mgreen" + ESC + "0m"), ["red", "green"])

    def test_command_word_skips_wrappers(self):
        cases = {
            "sudo -u postgres psql -c x": "psql",
            "env -i FOO=1 git status": "git",
            "nice -n 10 make": "make",
            "timeout 5s curl x": "curl",
            "2>/dev/null git log": "git",
            "do convert x": "convert",
        }
        for cmd, want in cases.items():
            with self.subTest(cmd=cmd):
                self.assertEqual(cp.command_word(cp.tokenize(cmd))[0], want)

    def test_zsh_parse_gate(self):
        cands = ["ls -la", "if true; then", 'echo "x', "for f in a; do echo $f; done", "a && && b"]
        self.assertEqual(cp.parses(cands), [True, False, False, True, False])

    def test_embedded_stops_at_boundary(self):
        self.assertEqual(cp.embedded_commands("now run git status to see it", {"git"}), [("git status", True, False, True)])


BINDING_CONF = os.environ.get("TMUX_CMDPICK_CONF") or str(HERE.parents[2] / ".config" / "tmux" / "cmdpick.conf")


def tool_command():
    built = os.environ.get("TMUX_CMDPICK_BIN")
    return [built] if built else [sys.executable, str(HERE / "tmux-cmdpick.py")]


@unittest.skipUnless(shutil.which("tmux") and shutil.which("fzf"), "tmux and fzf required")
class InsideTmux(unittest.TestCase):
    FIXTURE = "\n".join([
        "  python3 -m http.server 8000 --bind 127.0.0.1 --directory",
        "  /tmp/served",
        "⏺ Run " + CODE + "tmux kill-server" + OFF + " when you are done.",
        "You should run python3 -m http.server 8000 to serve it.",
        "This line is prose and holds nothing.",
        "zsh -fc 'print -l one two three four five six seven eight nine ten eleven twelve'",
        POWERLINE + "tmux list-sessions -F '#{session_name}'",
    ]) + "\n"
    EXPECTED = [
        "tmux list-sessions -F '#{session_name}'",
        "zsh -fc 'print -l one two three four five six seven eight nine ten eleven twelve'",
        "python3 -m http.server 8000",
        "tmux kill-server",
        "python3 -m http.server 8000 --bind 127.0.0.1 --directory /tmp/served",
    ]

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = cls.tmp.name
        bindir = os.path.join(root, "bin")
        os.mkdir(bindir)
        for tool in ("tmux", "fzf", "zsh", "python3", "sh", "cat", "stty"):
            os.symlink(shutil.which(tool), os.path.join(bindir, tool))
        wrapper = os.path.join(bindir, "tmux-cmdpick")
        with open(wrapper, "w") as f:
            f.write("#!%s\nexec %s \"$@\"\n" % (shutil.which("sh"), shlex.join(tool_command())))
        os.chmod(wrapper, 0o755)
        cls.env = {
            "PATH": bindir,
            "HOME": os.path.join(root, "home"),
            "XDG_CACHE_HOME": os.path.join(root, "cache"),
            "TMUX_TMPDIR": root,
            "SHELL": os.path.join(bindir, "sh"),
            "TERM": "xterm-256color",
            "LANG": "C.UTF-8",
        }
        os.mkdir(cls.env["HOME"])
        cls.fixture = os.path.join(root, "fixture.txt")
        with open(cls.fixture, "w", encoding="utf-8") as f:
            f.write(cls.FIXTURE)
        cls.tmux("-f", "/dev/null", "-u", "start-server", ";", "set", "-g", "exit-empty", "off", ";", "set", "-g", "default-terminal", "screen-256color")

    @classmethod
    def tearDownClass(cls):
        subprocess.run(["tmux", "kill-server"], env=cls.env, stderr=subprocess.DEVNULL)
        cls.tmp.cleanup()

    @classmethod
    def tmux(cls, *args):
        return subprocess.run(["tmux", *args], env=cls.env, stdout=subprocess.PIPE, text=True, check=True).stdout

    def wait_for(self, probe, what):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            value = probe()
            if value:
                return value
            time.sleep(0.05)
        self.fail("timed out waiting for " + what)

    def start_target(self, name, width=60):
        typed = os.path.join(self.tmp.name, name + ".typed")
        inner = "cat %s; stty -icanon -echo; exec cat > %s" % (shlex.quote(self.fixture), shlex.quote(typed))
        self.tmux("new-session", "-d", "-s", name, "-x", str(width), "-y", "30", "sh -c " + shlex.quote(inner))
        pane = self.tmux("display-message", "-p", "-t", name, "#{pane_id}").strip()
        self.wait_for(lambda: "list-sessions" in self.tmux("capture-pane", "-p", "-t", pane), "fixture on screen")
        return pane, typed

    def open_picker(self, target):
        cmd = shlex.join(tool_command() + [target])
        picker = self.tmux("split-window", "-P", "-F", "#{pane_id}", "-t", target, "-h", "-l", "120", cmd).strip()
        self.wait_for(lambda: "cmd>" in self.tmux("capture-pane", "-p", "-t", picker), "fzf prompt")
        return picker

    def test_deployed_key_binding_end_to_end(self):
        inner = ["-L", "inner"]
        typed = os.path.join(self.tmp.name, "binding.typed")
        inner_cmd = "cat %s; stty -icanon -echo; exec cat > %s" % (shlex.quote(self.fixture), shlex.quote(typed))
        self.tmux(*inner, "-f", BINDING_CONF, "new-session", "-d", "-s", "work", "-x", "150", "-y", "40", "sh -c " + shlex.quote(inner_cmd))
        self.addCleanup(subprocess.run, ["tmux", *inner, "kill-server"], env=self.env, stderr=subprocess.DEVNULL)
        self.wait_for(lambda: "list-sessions" in self.tmux(*inner, "capture-pane", "-p", "-t", "work"), "fixture in the inner pane")
        self.tmux(*inner, "set-buffer", "sentinel")
        self.tmux("new-session", "-d", "-s", "client", "-x", "160", "-y", "45", "tmux -L inner attach -t work")
        self.wait_for(lambda: "list-sessions" in self.tmux("capture-pane", "-p", "-t", "client"), "inner client on screen")
        self.tmux("send-keys", "-t", "client", "C-b", "e")
        self.wait_for(lambda: "cmd>" in self.tmux("capture-pane", "-p", "-t", "client"), "picker popup over the pane")
        self.tmux("send-keys", "-t", "client", "Enter")
        got = self.wait_for(lambda: (lambda b: b if b != "sentinel" else "")(self.tmux(*inner, "show-buffer")), "buffer update")
        self.assertEqual(got, self.EXPECTED[0])

    def test_empty_pane_opens_no_popup(self):
        slow = os.path.join(self.tmp.name, "slow")
        os.mkdir(slow)
        wrapper = os.path.join(slow, "tmux-cmdpick")
        with open(wrapper, "w") as f:
            f.write("#!%s\nsleep 1\nexec %s \"$@\"\n" % (shutil.which("sh"), shlex.join(tool_command())))
        os.chmod(wrapper, 0o755)
        env = dict(self.env, PATH=slow + ":" + self.env["PATH"])
        os.symlink(shutil.which("sleep"), os.path.join(slow, "sleep"))
        inner = ["tmux", "-L", "quiet"]
        subprocess.run(inner + ["-f", BINDING_CONF, "new-session", "-d", "-s", "work", "-x", "150", "-y", "40", "sh -c 'echo nothing to see here; exec cat'"], env=env, check=True)
        self.addCleanup(subprocess.run, inner + ["kill-server"], env=env, stderr=subprocess.DEVNULL)
        self.tmux("new-session", "-d", "-s", "quiet-client", "-x", "160", "-y", "45", "tmux -L quiet attach -t work")
        self.wait_for(lambda: "nothing to see" in self.tmux("capture-pane", "-p", "-t", "quiet-client"), "inner client on screen")
        self.tmux("send-keys", "-t", "quiet-client", "C-b", "e")
        frames = []

        def notice():
            screen = self.tmux("capture-pane", "-p", "-t", "quiet-client")
            frames.append("\u250c" in screen)
            return "no shell commands" in screen

        self.wait_for(notice, "status-line notice")
        self.assertFalse(any(frames), "a popup opened for an empty pane")

    def test_unknown_pane_fails_loudly(self):
        r = subprocess.run(tool_command() + ["--print", "%999"], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("no tmux pane %999", r.stderr)

    def test_print_mode_reads_the_pane(self):
        pane, _ = self.start_target("printmode")
        out = subprocess.run(tool_command() + ["--print", pane], env=self.env, stdout=subprocess.PIPE, text=True, check=True).stdout
        self.assertEqual(out.splitlines(), self.EXPECTED)

    def test_enter_copies_newest(self):
        pane, _ = self.start_target("copy", 220)
        self.tmux("set-buffer", "sentinel")
        picker = self.open_picker(pane)
        self.tmux("send-keys", "-t", picker, "Enter")
        got = self.wait_for(lambda: (lambda b: b if b != "sentinel" else "")(self.tmux("show-buffer")), "buffer update")
        self.assertEqual(got, self.EXPECTED[0])

    def test_alt_enter_copies_newest(self):
        pane, _ = self.start_target("copy-alt", 220)
        self.tmux("set-buffer", "sentinel")
        picker = self.open_picker(pane)
        self.tmux("send-keys", "-t", picker, "Down", "M-Enter")
        got = self.wait_for(lambda: (lambda b: b if b != "sentinel" else "")(self.tmux("show-buffer")), "buffer update")
        self.assertEqual(got, self.EXPECTED[1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
