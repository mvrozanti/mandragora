import os
import sys
import tempfile
from collections import defaultdict

ROOT = "/home/m"
OUTDIR = "/var/lib/prometheus-node-exporter-textfiles"
MAX_DEPTH = 5
SIZE_THRESHOLD = 104857600
INODE_THRESHOLD = 100


def scan(path, depth, sizes, inodes, seen):
    try:
        st = os.lstat(path)
    except OSError:
        return 0, 0
    total_bytes = st.st_blocks * 512
    total_inodes = 1
    try:
        with os.scandir(path) as it:
            entries = list(it)
    except OSError:
        entries = []
    for entry in entries:
        if entry.is_dir(follow_symlinks=False):
            b, n = scan(entry.path, depth + 1, sizes, inodes, seen)
        else:
            try:
                est = entry.stat(follow_symlinks=False)
            except OSError:
                continue
            if est.st_nlink > 1:
                key = (est.st_dev, est.st_ino)
                if key in seen:
                    continue
                seen.add(key)
            b, n = est.st_blocks * 512, 1
        total_bytes += b
        total_inodes += n
    if depth <= MAX_DEPTH:
        sizes[path] = total_bytes
        inodes[path] = total_inodes
    return total_bytes, total_inodes


def label(path):
    if path == ROOT:
        return "~"
    return "~" + path[len(ROOT):]


def emit(out, name, help_text, values, threshold):
    out.write(f"# HELP {name} {help_text}\n")
    out.write(f"# TYPE {name} gauge\n")
    for path, value in values.items():
        if value >= threshold:
            out.write(f'{name}{{path="{label(path)}"}} {value}\n')


def main():
    sys.setrecursionlimit(20000)
    sizes = defaultdict(int)
    inodes = defaultdict(int)
    scan(ROOT, 0, sizes, inodes, set())
    fd, tmp = tempfile.mkstemp(prefix=".dirsize.prom.", dir=OUTDIR)
    try:
        with os.fdopen(fd, "w") as out:
            emit(out, "dirsize_bytes",
                 "Disk usage of directory in bytes", sizes,
                 SIZE_THRESHOLD)
            emit(out, "dir_inode_count",
                 "Number of inodes (files/dirs) in directory", inodes,
                 INODE_THRESHOLD)
        os.chmod(tmp, 0o644)
        os.replace(tmp, os.path.join(OUTDIR, "dirsize.prom"))
    except BaseException:
        os.unlink(tmp)
        raise


main()
