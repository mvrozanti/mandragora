import asyncio
import os
import signal
import socket
import subprocess
import sys
import time

LISTEN_FD = 3
LISTEN_FDS = int(os.environ.get("LISTEN_FDS", "0") or "0")

UPSTREAM_ADDR = os.environ.get("UPSTREAM_ADDR", "127.0.0.1")
UPSTREAM_PORT = int(os.environ.get("UPSTREAM_PORT", "18000"))
IDLE_TIMEOUT = float(os.environ.get("IDLE_TIMEOUT", "900"))
STARTUP_TIMEOUT = float(os.environ.get("STARTUP_TIMEOUT", "180"))


class IdleSupervisor:
    def __init__(self):
        self.child = None
        self.last_activity = time.monotonic()
        self.exit_code = 0

    def start_child(self):
        self.child = subprocess.Popen(sys.argv[1:])

    def child_alive(self):
        return self.child is not None and self.child.poll() is None

    def stop_child(self):
        if self.child is None or self.child.poll() is not None:
            return
        self.child.terminate()
        try:
            self.child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.child.kill()
            self.child.wait()

    async def wait_ready(self):
        deadline = time.monotonic() + STARTUP_TIMEOUT
        while time.monotonic() < deadline:
            if not self.child_alive():
                self.exit_code = self.child.returncode or 1
                return False
            try:
                _, writer = await asyncio.open_connection(UPSTREAM_ADDR, UPSTREAM_PORT)
                writer.close()
                return True
            except OSError:
                await asyncio.sleep(0.2)
        self.exit_code = 1
        return False

    async def copy(self, reader, writer):
        try:
            while True:
                data = await reader.read(65536)
                if not data:
                    break
                self.last_activity = time.monotonic()
                writer.write(data)
                await writer.drain()
        except (asyncio.IncompleteReadError, ConnectionError, OSError):
            pass

    async def proxy(self, client_reader, client_writer):
        self.last_activity = time.monotonic()
        try:
            upstream_reader, upstream_writer = await asyncio.open_connection(
                UPSTREAM_ADDR, UPSTREAM_PORT
            )
        except OSError:
            client_writer.close()
            return
        try:
            upstream_to_client = asyncio.create_task(
                self.copy(upstream_reader, client_writer)
            )
            client_to_upstream = asyncio.create_task(
                self.copy(client_reader, upstream_writer)
            )
            await asyncio.wait(
                {upstream_to_client, client_to_upstream},
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in (upstream_to_client, client_to_upstream):
                task.cancel()
        finally:
            for writer in (client_writer, upstream_writer):
                try:
                    writer.close()
                except OSError:
                    pass


async def run():
    if len(sys.argv) < 2:
        return 2
    if LISTEN_FDS < 1:
        return 0

    supervisor = IdleSupervisor()
    supervisor.start_child()
    if not await supervisor.wait_ready():
        supervisor.stop_child()
        return supervisor.exit_code

    loop = asyncio.get_running_loop()
    listen_sock = socket.socket(fileno=LISTEN_FD)
    listen_sock.setblocking(False)
    server = await asyncio.start_server(supervisor.proxy, sock=listen_sock)

    stop = asyncio.Event()

    def request_stop():
        stop.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, request_stop)

    async def watchdog():
        while True:
            await asyncio.sleep(5)
            if not supervisor.child_alive():
                supervisor.exit_code = supervisor.child.returncode or 1
                stop.set()
                return
            if time.monotonic() - supervisor.last_activity > IDLE_TIMEOUT:
                supervisor.exit_code = 0
                stop.set()
                return

    watcher = asyncio.create_task(watchdog())
    await stop.wait()

    watcher.cancel()
    server.close()
    await server.wait_closed()
    supervisor.stop_child()
    return supervisor.exit_code


def main():
    sys.exit(asyncio.run(run()))


if __name__ == "__main__":
    main()
