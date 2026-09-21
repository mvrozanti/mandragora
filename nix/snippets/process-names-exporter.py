import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CLOCK_TICKS = os.sysconf("SC_CLK_TCK")
PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")
CACHE_SECONDS = 5.0

NAME_RULES = [
    ("claude-deepseek", r"cc-pocket-bridge"),
    ("claude-web", r"claude-web/app\.py"),
    ("autoclaude", r"/autoclaude\b"),
    ("claude", r"claude-code-[0-9.]+/lib/claude-code/claude"),
    ("firefox", r"firefox-[0-9.]+/lib/firefox/firefox|/bin/firefox$"),
    ("kitty", r"kitty-[0-9.]+/bin/kitt(y|en)|/bin/kitty\b"),
    ("hyprland", r"/bin/Hyprland\b"),
    ("im-gen-bot", r"im-gen/.*\bbot\.py"),
    ("im-gen-webui", r"im-gen/webui/app\.py"),
    ("ea-desktop", r"EADesktop\.exe|EACefSubProcess\.exe"),
    ("wine", r"\.exe\b"),
]
COMPILED_RULES = [(name, re.compile(pattern)) for name, pattern in NAME_RULES]
SCRIPT_RULE = re.compile(r"python[0-9.]*\s+(?:-[^\s]+\s+)*[^\s]*?([A-Za-z0-9_.-]+\.py)\b")
NIX_BIN_RULE = re.compile(r"^/nix/store/[a-z0-9]+-[^/]+/bin/([A-Za-z0-9_.-]+)")
NIX_LIB_RULE = re.compile(r"^/nix/store/[a-z0-9]+-[^/]+/(?:lib|libexec)/[^\s]*?([A-Za-z0-9_.-]+)(?:\s|$)")

COUNTERS = [
    ("namedprocess_namegroup_cpu_seconds_total", "counter", "cpu"),
    ("namedprocess_namegroup_major_page_faults_total", "counter", "majflt"),
    ("namedprocess_namegroup_minor_page_faults_total", "counter", "minflt"),
    ("namedprocess_namegroup_read_bytes_total", "counter", "read_bytes"),
    ("namedprocess_namegroup_write_bytes_total", "counter", "write_bytes"),
]


def read_text(path):
    try:
        with open(path, "rb") as handle:
            return handle.read().decode("utf-8", "replace")
    except (OSError, UnicodeDecodeError):
        return None


def group_name(cmdline, exe_path):
    for name, pattern in COMPILED_RULES:
        if pattern.search(cmdline):
            return name
    for rule in (SCRIPT_RULE, NIX_BIN_RULE, NIX_LIB_RULE):
        match = rule.search(cmdline)
        if match:
            return match.group(1)
    if exe_path:
        return os.path.basename(exe_path)
    head = cmdline.split()
    return os.path.basename(head[0]) if head else "unknown"


def parse_stat(raw):
    closing = raw.rfind(")")
    if closing < 0:
        return None
    fields = raw[closing + 2:].split()
    if len(fields) < 22:
        return None
    return fields


def collect_process(pid):
    stat_raw = read_text("/proc/%s/stat" % pid)
    if stat_raw is None:
        return None, "unreadable"
    fields = parse_stat(stat_raw)
    if fields is None:
        return None, "unreadable"
    if fields[0] == "Z":
        return None, "zombie"
    cmdline_raw = read_text("/proc/%s/cmdline" % pid)
    cmdline = cmdline_raw.replace("\0", " ").strip() if cmdline_raw else ""
    if not cmdline:
        return None, "kernel"
    try:
        exe_path = os.readlink("/proc/%s/exe" % pid)
    except OSError:
        exe_path = ""
    swapped = 0
    status_raw = read_text("/proc/%s/status" % pid)
    if status_raw:
        for line in status_raw.splitlines():
            if line.startswith("VmSwap:"):
                swapped = int(line.split()[1]) * 1024
                break
    read_bytes = write_bytes = 0
    io_raw = read_text("/proc/%s/io" % pid)
    if io_raw:
        for line in io_raw.splitlines():
            if line.startswith("read_bytes:"):
                read_bytes = int(line.split()[1])
            elif line.startswith("write_bytes:"):
                write_bytes = int(line.split()[1])
    return {
        "name": group_name(cmdline, exe_path),
        "cpu": (int(fields[11]) + int(fields[12])) / CLOCK_TICKS,
        "minflt": int(fields[7]),
        "majflt": int(fields[9]),
        "threads": int(fields[17]),
        "resident": int(fields[21]) * PAGE_SIZE,
        "virtual": int(fields[20]),
        "swapped": swapped,
        "read_bytes": read_bytes,
        "write_bytes": write_bytes,
        "start_ticks": int(fields[19]),
    }, "ok"


def scan():
    boot_time = time.time() - float(read_text("/proc/uptime").split()[0])
    groups = {}
    skipped = {"zombie": 0, "kernel": 0, "unreadable": 0}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        record, reason = collect_process(entry)
        if record is None:
            skipped[reason] += 1
            continue
        bucket = groups.setdefault(
            record["name"],
            {
                "procs": 0,
                "cpu": 0.0,
                "minflt": 0,
                "majflt": 0,
                "threads": 0,
                "resident": 0,
                "virtual": 0,
                "swapped": 0,
                "read_bytes": 0,
                "write_bytes": 0,
                "oldest": None,
            },
        )
        bucket["procs"] += 1
        for key in ("cpu", "minflt", "majflt", "threads", "resident", "virtual", "swapped", "read_bytes", "write_bytes"):
            bucket[key] += record[key]
        started = boot_time + record["start_ticks"] / CLOCK_TICKS
        if bucket["oldest"] is None or started < bucket["oldest"]:
            bucket["oldest"] = started
    return groups, skipped


def escape(value):
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def render(groups, skipped, duration):
    lines = []
    emit = lines.append
    emit("# HELP namedprocess_namegroup_num_procs Number of processes in this group")
    emit("# TYPE namedprocess_namegroup_num_procs gauge")
    for name, bucket in groups.items():
        emit('namedprocess_namegroup_num_procs{groupname="%s"} %d' % (escape(name), bucket["procs"]))
    emit("# HELP namedprocess_namegroup_num_threads Number of threads in this group")
    emit("# TYPE namedprocess_namegroup_num_threads gauge")
    for name, bucket in groups.items():
        emit('namedprocess_namegroup_num_threads{groupname="%s"} %d' % (escape(name), bucket["threads"]))
    emit("# HELP namedprocess_namegroup_memory_bytes Memory held by this group")
    emit("# TYPE namedprocess_namegroup_memory_bytes gauge")
    for name, bucket in groups.items():
        safe = escape(name)
        for memtype in ("resident", "virtual", "swapped"):
            emit('namedprocess_namegroup_memory_bytes{groupname="%s",memtype="%s"} %d' % (safe, memtype, bucket[memtype]))
    for metric, kind, key in COUNTERS:
        emit("# HELP %s Aggregated %s for this group" % (metric, key))
        emit("# TYPE %s %s" % (metric, kind))
        for name, bucket in groups.items():
            emit('%s{groupname="%s"} %s' % (metric, escape(name), repr(bucket[key]) if isinstance(bucket[key], float) else bucket[key]))
    emit("# HELP namedprocess_namegroup_oldest_start_time_seconds Start time of the oldest process in this group")
    emit("# TYPE namedprocess_namegroup_oldest_start_time_seconds gauge")
    for name, bucket in groups.items():
        emit('namedprocess_namegroup_oldest_start_time_seconds{groupname="%s"} %.3f' % (escape(name), bucket["oldest"]))
    emit("# HELP process_names_exporter_skipped_processes Processes not attributed to a group, by reason")
    emit("# TYPE process_names_exporter_skipped_processes gauge")
    for reason, count in sorted(skipped.items()):
        emit('process_names_exporter_skipped_processes{reason="%s"} %d' % (reason, count))
    emit("# HELP process_names_exporter_scrape_duration_seconds Time taken by the last /proc walk")
    emit("# TYPE process_names_exporter_scrape_duration_seconds gauge")
    emit("process_names_exporter_scrape_duration_seconds %.4f" % duration)
    return "\n".join(lines) + "\n"


class Cache:
    def __init__(self):
        self.lock = threading.Lock()
        self.body = ""
        self.stamp = 0.0

    def body_now(self):
        with self.lock:
            if time.time() - self.stamp < CACHE_SECONDS and self.body:
                return self.body
            started = time.time()
            groups, skipped = scan()
            duration = time.time() - started
            self.body = render(groups, skipped, duration)
            self.stamp = time.time()
            return self.body


CACHE = Cache()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path.split("?")[0] not in ("/metrics", "/"):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        payload = CACHE.body_now().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        return


def main():
    host = os.environ.get("PROCESS_NAMES_HOST", "127.0.0.1")
    port = int(os.environ.get("PROCESS_NAMES_PORT", "9256"))
    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    sys.stderr.write("process-names-exporter listening on %s:%d\n" % (host, port))
    sys.stderr.flush()
    server.serve_forever()


if __name__ == "__main__":
    main()
