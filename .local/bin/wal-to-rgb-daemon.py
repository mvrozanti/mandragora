import colorsys
import contextlib
import fcntl
import json
import os
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

FPS = 40
STOPS_PER_SECOND = 1.0
COLORS_PATH = Path.home() / ".cache/matugen/colors.json"
STATE_PATH = Path.home() / ".cache/hid-config/state"
PAUSE_SENTINEL = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")) / "rgb-control-paused"
WRITE_LOCK = "/tmp/openrgb-write.lock"
RAM_PALETTE_INDICES = [2, 6, 5, 1]
RAM_LEDS_PER_STOP = 2
CONNECT_BACKOFF_SECONDS = 3
RECONNECT_AFTER_SECONDS = 10.0
STALE_FRAME_SECONDS = 1.0
AIO_ZONE_PREFIX = "D_LED1"
AIO_RING_LEDS = 8
AIO_RESTORE_TIMEOUT_SECONDS = 15
TELEMETRY_ADDRESS = ("127.0.0.1", 5300)
TELEMETRY_TIMEOUT_SECONDS = 1.0
HORIZON_PACKET_BYTES = 324
HORIZON_SPEED_OFFSET = 256
GAUGE_FULL_SCALE_MPS = 400 / 3.6
GAUGE_TRACK_BRIGHTNESS = 0.08


def log(msg):
    sys.stderr.write(f"wal-to-rgb-daemon: {msg}\n")
    sys.stderr.flush()


@contextlib.contextmanager
def write_lock(timeout=0.5):
    fd = os.open(WRITE_LOCK, os.O_CREAT | os.O_WRONLY, 0o666)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"openrgb write lock held >{timeout}s")
                time.sleep(0.005)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def from_hex(h):
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    h_val, s_val, v_val = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    s_val = 1.0
    v_val = 1.0
    r, g, b = colorsys.hsv_to_rgb(h_val, s_val, v_val)
    return RGBColor(int(r * 255), int(g * 255), int(b * 255))


def load_palette():
    if not COLORS_PATH.exists():
        return None
    try:
        data = json.loads(COLORS_PATH.read_text())
        palette = [data["colors"][f"color{i}"].lstrip("#") for i in range(16)]
        return [from_hex(palette[i]) for i in RAM_PALETTE_INDICES]
    except Exception:
        return None


def lerp_color(a, b, t):
    return RGBColor(
        int(a.red + (b.red - a.red) * t),
        int(a.green + (b.green - a.green) * t),
        int(a.blue + (b.blue - a.blue) * t),
    )


def animated_colors(stops, led_count, phase):
    n = len(stops)
    out = []
    for i in range(led_count):
        pos = (i / RAM_LEDS_PER_STOP + phase) % n
        idx_a = int(pos) % n
        idx_b = (idx_a + 1) % n
        frac = pos - int(pos)
        out.append(lerp_color(stops[idx_a], stops[idx_b], frac))
    return out


def scale_color(c, k):
    return RGBColor(int(c.red * k), int(c.green * k), int(c.blue * k))


def gradient_at(stops, t):
    pos = t * (len(stops) - 1)
    idx = min(int(pos), len(stops) - 2)
    return lerp_color(stops[idx], stops[idx + 1], pos - idx)


def gauge_colors(stops, led_count, level):
    lit = level * led_count
    out = []
    for i in range(led_count):
        brightness = min(max(lit - i, GAUGE_TRACK_BRIGHTNESS), 1.0)
        out.append(scale_color(gradient_at(stops, i / max(led_count - 1, 1)), brightness))
    return out


def open_telemetry_socket():
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(TELEMETRY_ADDRESS)
        sock.setblocking(False)
        log(f"listening for Forza Horizon Data Out on udp {TELEMETRY_ADDRESS[0]}:{TELEMETRY_ADDRESS[1]}")
        return sock
    except OSError as e:
        log(f"telemetry disabled: {e}")
        return None


def drain_race_speed(sock):
    speed = None
    while sock is not None:
        try:
            packet = sock.recv(1024)
        except BlockingIOError:
            break
        if len(packet) != HORIZON_PACKET_BYTES:
            continue
        is_race_on, = struct.unpack_from("<i", packet, 0)
        if is_race_on:
            speed, = struct.unpack_from("<f", packet, HORIZON_SPEED_OFFSET)
    return speed


def restore_aio():
    try:
        subprocess.run(["wal-to-rgb"], timeout=AIO_RESTORE_TIMEOUT_SECONDS, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        log(f"aio restore failed: {e}")


def connect():
    while True:
        try:
            return OpenRGBClient(name="wal-to-rgb-daemon", protocol_version=3)
        except Exception as e:
            log(f"connect failed: {e}; retry in {CONNECT_BACKOFF_SECONDS}s")
            time.sleep(CONNECT_BACKOFF_SECONDS)


def ensure_direct(d):
    if d.modes[d.active_mode].name.lower() == "direct":
        return
    for mode in ("Direct", "direct"):
        try:
            d.set_mode(mode)
            return
        except Exception:
            continue


def find_ram_devices(client):
    out = []
    for d in client.devices:
        name = (d.name or "").lower()
        if not any(x in name for x in ["dram", "ene", "xpg"]):
            continue
        ensure_direct(d)
        out.append(d)
    log(f"found {len(out)} RAM device(s): {[d.name for d in out]}")
    return out


def find_aio(client):
    for d in client.devices:
        zones = [z for z in d.zones if (z.name or "").startswith(AIO_ZONE_PREFIX)]
        if zones:
            log(f"found AIO chain on {d.name!r}: {[z.name for z in zones]}")
            return d, zones
    log("no AIO chain found")
    return None


def mtime_or_zero():
    try:
        return COLORS_PATH.stat().st_mtime
    except Exception:
        return 0


def is_rgb_on():
    try:
        if STATE_PATH.exists():
            return STATE_PATH.read_text().strip() == 'True'
    except Exception:
        pass
    return True


def is_paused():
    return PAUSE_SENTINEL.exists()


def frame_targets(ram_devices, aio, palette, phase, speed, racing):
    if not racing:
        return [(d, d.zones, lambda n: animated_colors(palette, n, phase)) for d in ram_devices]
    level = min(max(speed / GAUGE_FULL_SCALE_MPS, 0.0), 1.0)
    targets = [(d, d.zones, lambda n: gauge_colors(palette, n, level)) for d in ram_devices]
    if aio:
        ring = gauge_colors(palette, AIO_RING_LEDS, level)
        targets.append((aio[0], aio[1], lambda n: [ring[i % AIO_RING_LEDS] for i in range(n)]))
    return targets


def write_target(d, zones, colors_for, in_flight, now):
    if device_busy(d, zones, in_flight, now):
        return
    frame = [colors_for(len(zone.leds)) for zone in zones]
    pending = in_flight.get(d.id)
    if pending is not None and pending[0] == frame:
        return
    send_frame(d, zones, frame)
    in_flight[d.id] = (frame, now)


def send_frame(d, zones, frame):
    if len(zones) == 1 and len(zones[0].leds) == len(d.leds):
        d.set_colors(frame[0], fast=True)
        return
    for zone, colors in zip(zones, frame):
        zone.set_colors(colors, fast=True)


def frame_applied(d, zones, sent):
    d.update()
    return [zone.colors for zone in zones] == sent


def device_busy(d, zones, in_flight, now):
    pending = in_flight.get(d.id)
    if pending is None:
        return False
    sent, sent_at = pending
    return now - sent_at < STALE_FRAME_SECONDS and not frame_applied(d, zones, sent)


def main():
    log("starting up")
    client = connect()
    ram_devices = find_ram_devices(client)
    aio = find_aio(client)
    telemetry = open_telemetry_socket()
    palette = load_palette()
    last_mtime = mtime_or_zero()
    phase = 0.0
    frame_dt = 1.0 / FPS
    phase_step = STOPS_PER_SECOND / FPS
    last_success = time.monotonic()
    device_failures = 0
    in_flight = {}
    speed = 0.0
    speed_at = float("-inf")
    racing = False
    aio_painted = False

    while True:
        frame_start = time.monotonic()

        latest_speed = drain_race_speed(telemetry)
        if latest_speed is not None:
            speed, speed_at = latest_speed, frame_start
        was_racing, racing = racing, frame_start - speed_at < TELEMETRY_TIMEOUT_SECONDS
        if racing != was_racing:
            log("telemetry: race on" if racing else "telemetry: race off")

        if aio_painted and not racing:
            if not is_paused():
                restore_aio()
            in_flight.clear()
            aio_painted = False

        if not is_rgb_on() or is_paused():
            time.sleep(0.5)
            last_success = time.monotonic()
            continue

        new_mtime = mtime_or_zero()
        if new_mtime != last_mtime:
            new_palette = load_palette()
            if new_palette:
                palette = new_palette
                last_mtime = new_mtime

        if palette and ram_devices:
            had_any_success = False
            try:
                with write_lock(timeout=0.4):
                    for d, zones, colors_for in frame_targets(ram_devices, aio, palette, phase, speed, racing):
                        try:
                            write_target(d, zones, colors_for, in_flight, frame_start)
                            aio_painted = aio_painted or (aio is not None and d is aio[0])
                            had_any_success = True
                        except Exception as e:
                            device_failures += 1
                            if device_failures % 200 == 1:
                                log(f"device write failed for {d.name!r}: {e} (count={device_failures})")
            except TimeoutError:
                pass
            except Exception as e:
                log(f"frame failed: {e}")

            if had_any_success:
                last_success = frame_start
            elif frame_start - last_success >= RECONNECT_AFTER_SECONDS:
                log("no successful writes for 10s — reconnecting")
                try:
                    client.disconnect()
                except Exception:
                    pass
                client = connect()
                ram_devices = find_ram_devices(client)
                aio = find_aio(client)
                in_flight = {}
                last_success = time.monotonic()

        phase = (phase + phase_step) % len(palette) if palette else 0.0

        elapsed = time.monotonic() - frame_start
        sleep_for = frame_dt - elapsed
        if sleep_for > 0:
            time.sleep(sleep_for)


if __name__ == "__main__":
    main()
