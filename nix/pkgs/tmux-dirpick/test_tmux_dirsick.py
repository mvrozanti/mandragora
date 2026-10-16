import importlib.util
import os
import pathlib
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("dirpick", HERE / "tmux-dirpick.py")
dp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dp)


class ExtractDirs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = str(pathlib.Path(self.tmp.name))
        os.makedirs(os.path.join(self.base, "src"))
        os.makedirs(os.path.join(self.base, "docs", "nested"))
        with open(os.path.join(self.base, "file.txt"), "w") as f:
            f.write("x")

    def tearDown(self):
        self.tmp.cleanup()

    def test_absolute_dir(self):
        self.assertEqual(dp.extract_dirs(os.path.join(self.base, "src"), self.base), [os.path.join(self.base, "src")])

    def test_relative_dir(self):
        self.assertEqual(dp.extract_dirs("docs/nested", self.base), [os.path.join(self.base, "docs", "nested")])

    def test_file_is_not_a_dir(self):
        self.assertEqual(dp.extract_dirs(os.path.join(self.base, "file.txt"), self.base), [])

    def test_plain_word_ignored(self):
        self.assertEqual(dp.extract_dirs("hello world", self.base), [])

    def test_newest_first_and_dedup(self):
        text = "cd %s\ncd %s\ncd %s\n" % (
            os.path.join(self.base, "src"),
            os.path.join(self.base, "docs"),
            os.path.join(self.base, "src"),
        )
        self.assertEqual(
            dp.extract_dirs(text, self.base),
            [os.path.join(self.base, "docs"), os.path.join(self.base, "src")],
        )

    def test_strips_ansi(self):
        text = "\x1b[38;5;153m" + os.path.join(self.base, "src") + "\x1b[39m"
        self.assertEqual(dp.extract_dirs(text, self.base), [os.path.join(self.base, "src")])


if __name__ == "__main__":
    unittest.main(verbosity=2)
