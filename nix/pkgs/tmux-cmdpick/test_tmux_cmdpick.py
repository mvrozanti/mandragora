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
    "tmux-cmdpick", "after", "seq", "pgrep", "sleep", "dnsmasq",
})
SHELL_NAMES = frozenset({"to", "ll", "g", "jobs", "disable", "cd", "echo", "print"})
NAMES = cp.Names(EXECUTABLES | SHELL_NAMES | cp.zsh_names(False), EXECUTABLES)

ESC = "\x1b["
CODE = ESC + "38;5;153m"
DIM = ESC + "2m"
OFF = ESC + "39m"
POWERLINE = "    ~/Projects/foo   master  "


def run(text, cwd=None, names=NAMES):
    return cp.extract(text, cwd or tempfile.gettempdir(), names)


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
        "docker restarts containers automatically.",
        "systemctl restart waybar if it hangs",
        "    htop",
        DIM + "(timeout 10m)" + ESC + "22m",
        "(timeout 10m)",
        "watch 5",
    ]

    def test_cases(self):
        for text in self.CASES:
            with self.subTest(text=text):
                self.assertEqual(run(text), [])


class SingleWords(unittest.TestCase):
    def test_accepted_after_a_prompt(self):
        self.assertEqual(run("$ htop\n" + POWERLINE + "htop"), ["htop"])

    def test_rejected_elsewhere(self):
        for text in ["    htop", "dnsmasq", "Open `htop` and sort by memory.", CODE + "htop" + OFF]:
            with self.subTest(text=text):
                self.assertEqual(run(text), [])


class ClaudeCodeScreens(unittest.TestCase):
    STATUS = ESC + "39m  " + ESC + "36m[Opus 5.5]" + ESC + "38;5;246m \u2502 " + ESC + "33mtmux-cmdpick" + ESC + "38;5;246m " + ESC + "35mgit:(" + ESC + "36mtest/tmux-cmdpick*" + ESC + "35m)" + ESC + "39m"
    DIFF = [
        "     " + ESC + "2m" + ESC + "38;5;231m 53 " + ESC + "0m" + ESC + "38;5;231m     " + ESC + "38;5;81mdef" + ESC + "38;5;231m " + ESC + "38;5;148mtest_cases" + ESC + "38;5;231m(" + ESC + "38;5;208mself" + ESC + "38;5;231m):",
        "     " + ESC + "38;5;77m" + ESC + "48;5;22m 70 +" + ESC + "38;5;231m        (" + ESC + '38;5;186m"$ htop"' + ESC + "38;5;231m, [" + ESC + '38;5;186m"htop"' + ESC + "38;5;231m]),",
    ]
    TOOL_CALL = ESC + "38;5;246m  \u23bf  $ for i in $(seq 1 30); do pgrep -f gource >/dev/null || { echo \"exited after ~${i}x2s\"; break; }; sleep 2; done (23"

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
                self.assertEqual(run(text), [])

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


class KnownLimitations(unittest.TestCase):
    @unittest.expectedFailure
    def test_trailing_english_verb_is_kept(self):
        self.assertEqual(run("Pass the flag: journalctl -b --no-pager works."), ["journalctl -b --no-pager"])

    @unittest.expectedFailure
    def test_hard_wrapped_command_is_not_rejoined(self):
        text = "  docker compose -f stack.yml up -d --remove-orphans\n  --force-recreate"
        self.assertEqual(run(text), ["docker compose -f stack.yml up -d --remove-orphans --force-recreate"])

    @unittest.expectedFailure
    def test_line_start_command_with_english_tail(self):
        self.assertEqual(run("systemctl restart waybar if it hangs"), ["systemctl restart waybar"])

    @unittest.expectedFailure
    def test_unformatted_command_without_cue_or_flag(self):
        self.assertEqual(run("the trick is git stash then pop"), ["git stash"])


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
        self.assertEqual(cp.embedded_commands("now run git status to see it", {"git"}), [("git status", True)])


def slurp(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def tool_command():
    built = os.environ.get("TMUX_CMDPICK_BIN")
    return [built] if built else [sys.executable, str(HERE / "tmux-cmdpick.py")]


@unittest.skipUnless(shutil.which("tmux") and shutil.which("fzf"), "tmux and fzf required")
class InsideTmux(unittest.TestCase):
    FIXTURE = "\n".join([
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
    ]

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = cls.tmp.name
        bindir = os.path.join(root, "bin")
        os.mkdir(bindir)
        for tool in ("tmux", "fzf", "zsh", "python3", "sh", "cat", "stty"):
            os.symlink(shutil.which(tool), os.path.join(bindir, tool))
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

    def test_alt_enter_types_without_running(self):
        pane, typed = self.start_target("insert", 220)
        picker = self.open_picker(pane)
        self.tmux("send-keys", "-t", picker, "Down", "M-Enter")
        want = self.EXPECTED[1]
        self.wait_for(lambda: len(slurp(typed)) >= len(want), "typed text")
        got = slurp(typed)
        self.assertEqual(got, self.EXPECTED[1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
