#!/usr/bin/env python3
import os
import queue
import socket
import socketserver
import subprocess
import sys
import threading
import time

BIN = os.environ.get("CHESS_ENGINE_BIN", "stockfish")
BIND = os.environ.get("CHESS_ENGINE_BIND", "0.0.0.0")
PORT = int(os.environ.get("CHESS_ENGINE_PORT", "6613"))
DEFAULT_MOVETIME = int(os.environ.get("CHESS_ENGINE_DEFAULT_MOVETIME", "1000"))
MAX_MOVETIME = int(os.environ.get("CHESS_ENGINE_MAX_MOVETIME", "5000"))
THREADS = int(os.environ.get("CHESS_ENGINE_THREADS", "2"))
HASH_MB = int(os.environ.get("CHESS_ENGINE_HASH", "64"))

MIN_MOVETIME = 10
MIN_SKILL = 0
MAX_SKILL = 20
EVAL_SKILL = 20
HANDSHAKE_TIMEOUT = 15.0
SEARCH_SLACK = 10.0
MAX_REQUEST = 1024
IDLE_TIMEOUT = 300
SIDES = ("w", "b")
BOARD_CHARS = set("rnbqkpRNBQKP12345678/")
NO_MOVE = ("(none)", "none", "0000")


class EngineDown(Exception):
    pass


class Engine:
    def __init__(self):
        self.lock = threading.Lock()
        self.proc = None
        self.lines = None
        self.skill = None

    def warm(self):
        with self.lock:
            if not self._alive():
                self._start()

    def search(self, fen, skill, movetime):
        with self.lock:
            for last_attempt in (False, True):
                try:
                    if not self._alive():
                        self._start()
                    self._set_skill(skill)
                    return self._search(fen, movetime)
                except EngineDown:
                    self._stop()
                    if last_attempt:
                        raise

    def _alive(self):
        return self.proc is not None and self.proc.poll() is None

    def _start(self):
        self._stop()
        try:
            proc = subprocess.Popen(
                [BIN],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
        except OSError as exc:
            raise EngineDown("spawn failed: %s" % exc)
        sink = queue.Queue()
        threading.Thread(target=drain, args=(proc, sink), daemon=True).start()
        self.proc = proc
        self.lines = sink
        self.skill = None
        self._write("uci")
        self._await("uciok", HANDSHAKE_TIMEOUT)
        self._write("setoption name Threads value %d" % THREADS)
        self._write("setoption name Hash value %d" % HASH_MB)
        self._sync()

    def _stop(self):
        proc = self.proc
        self.proc = None
        self.lines = None
        self.skill = None
        if proc is None:
            return
        try:
            proc.stdin.close()
        except (OSError, ValueError):
            pass
        try:
            proc.terminate()
            proc.wait(timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            proc.kill()

    def _write(self, line):
        if not self._alive():
            raise EngineDown("engine is not running")
        try:
            self.proc.stdin.write(line + "\n")
            self.proc.stdin.flush()
        except (OSError, ValueError) as exc:
            raise EngineDown("write failed: %s" % exc)

    def _read(self, timeout):
        if timeout <= 0:
            raise EngineDown("timed out")
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty:
            raise EngineDown("timed out")
        if line is None:
            raise EngineDown("engine exited")
        return line

    def _await(self, token, timeout):
        deadline = time.monotonic() + timeout
        while True:
            line = self._read(deadline - time.monotonic())
            if line.split(" ", 1)[0] == token:
                return line

    def _sync(self):
        self._write("isready")
        self._await("readyok", HANDSHAKE_TIMEOUT)

    def _set_skill(self, skill):
        if self.skill == skill:
            return
        self._write("setoption name Skill Level value %d" % skill)
        self.skill = skill

    def _search(self, fen, movetime):
        self._write("ucinewgame")
        self._sync()
        self._write("position fen " + fen)
        self._write("go movetime %d" % movetime)
        deadline = time.monotonic() + movetime / 1000.0 + SEARCH_SLACK
        score = None
        while True:
            fields = self._read(deadline - time.monotonic()).split()
            if not fields:
                continue
            if fields[0] == "info":
                found = read_score(fields)
                if found is not None:
                    score = found
            elif fields[0] == "bestmove":
                move = fields[1] if len(fields) > 1 else "(none)"
                return move, score


def drain(proc, sink):
    for raw in proc.stdout:
        sink.put(raw.rstrip("\n"))
    sink.put(None)


def read_score(fields):
    if "lowerbound" in fields or "upperbound" in fields:
        return None
    try:
        at = fields.index("score")
        return fields[at + 1], int(fields[at + 2])
    except (ValueError, IndexError):
        return None


def valid_fen(fen):
    fields = fen.split()
    if len(fields) < 2 or fields[1] not in SIDES:
        return False
    board = fields[0]
    return board.count("/") == 7 and set(board) <= BOARD_CHARS


def parse_skill(text):
    try:
        return max(MIN_SKILL, min(MAX_SKILL, int(text)))
    except ValueError:
        return None


def parse_movetime(text):
    try:
        value = int(text)
    except ValueError:
        return None
    if value <= 0:
        value = DEFAULT_MOVETIME
    return max(MIN_MOVETIME, min(MAX_MOVETIME, value))


def bestmove(rest):
    fields = rest.split(None, 2)
    if len(fields) < 3:
        return "ERR usage BESTMOVE <skill> <movetime_ms> <fen>"
    skill = parse_skill(fields[0])
    movetime = parse_movetime(fields[1])
    if skill is None or movetime is None:
        return "ERR skill and movetime must be integers"
    fen = fields[2].strip()
    if not valid_fen(fen):
        return "ERR malformed fen"
    try:
        move, _ = ENGINE.search(fen, skill, movetime)
    except EngineDown as exc:
        return "ERR engine %s" % exc
    return "MOVE none" if move in NO_MOVE else "MOVE " + move


def evaluate(rest):
    fields = rest.split(None, 1)
    if len(fields) < 2:
        return "ERR usage EVAL <movetime_ms> <fen>"
    movetime = parse_movetime(fields[0])
    if movetime is None:
        return "ERR movetime must be an integer"
    fen = fields[1].strip()
    if not valid_fen(fen):
        return "ERR malformed fen"
    try:
        _, score = ENGINE.search(fen, EVAL_SKILL, movetime)
    except EngineDown as exc:
        return "ERR engine %s" % exc
    if score is None:
        return "ERR no score"
    kind, value = score
    if kind == "mate":
        return "MATE %d" % value
    return "CP %d" % value


def dispatch(line):
    verb, _, rest = line.partition(" ")
    verb = verb.upper()
    if verb == "PING":
        return "PONG"
    if verb == "QUIT":
        return None
    if verb == "BESTMOVE":
        return bestmove(rest)
    if verb == "EVAL":
        return evaluate(rest)
    if not verb:
        return "ERR empty request"
    return "ERR unknown verb %s" % verb


class Handler(socketserver.StreamRequestHandler):
    timeout = IDLE_TIMEOUT

    def handle(self):
        try:
            self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        while True:
            raw = self.rfile.readline(MAX_REQUEST)
            if not raw:
                return
            reply = dispatch(raw.decode("ascii", "replace").strip())
            if reply is None:
                return
            self.wfile.write(reply.encode("ascii", "replace") + b"\n")
            self.wfile.flush()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def handle_error(self, request, client_address):
        exc = sys.exc_info()[1]
        if isinstance(
            exc, (BrokenPipeError, ConnectionResetError, TimeoutError, socket.timeout)
        ):
            return
        super().handle_error(request, client_address)


ENGINE = Engine()


def main():
    try:
        ENGINE.warm()
    except EngineDown as exc:
        print("engine unavailable at startup: %s" % exc, file=sys.stderr)
    Server((BIND, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
