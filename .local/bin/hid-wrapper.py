import contextlib
import fcntl
import json
import os
import re
import signal
import sys
import subprocess
import time
from pathlib import Path

OPENRGB_WRITE_LOCK = "/tmp/openrgb-write.lock"
PERIPHERAL_NAMES = ("keyboard", "logitech", "mouse", "steelseries", "rival")
DRAM_NAMES = ("dram", "ene", "xpg")
ENE_DIRECT_COLORS_REG = 0x8100
ENE_LOCATION = re.compile(r"\((/dev/i2c-\d+)\), address (0x[0-9a-fA-F]+)")
BLACKOUT_ATTEMPTS = 5
WRITE_SETTLE_SECONDS = 0.1
BLACKOUT_TIMEOUT_SECONDS = 12
AIO_CHAIN_LENGTH = 60


def log(msg):
    sys.stderr.write(f"hid-wrapper: {msg}\n")
    sys.stderr.flush()

turn_on = sys.argv[1] == '--on' if len(sys.argv) > 1 else False
turn_off = sys.argv[1] == '--off' if len(sys.argv) > 1 else False

colors_path = Path('/home/m/.cache/matugen/colors.json')
if not colors_path.exists():
    raise SystemExit(0)

Path('/home/m/.cache/hid-config').mkdir(exist_ok=True)
lock_path = Path('/home/m/.cache/hid-config/lock')
lock_fd = open(lock_path, 'w')
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    raise SystemExit(0)

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError('hid-wrapper hung talking to mouse')))
signal.alarm(5)

from colour import Color
import rivalcfg

state_file = Path('/home/m/.cache/hid-config/state')
if not state_file.exists():
    state_file.write_text('False')
    is_on = False
else:
    is_on = state_file.read_text() == 'True'

def get_pywal_colors():
    color_json = json.loads(colors_path.read_text())
    return list(color_json['colors'].values())

def sort_hex_colors_by_saturation(color_strings):
    colors = list(map(Color, color_strings))
    colors = {sum(c.rgb): c for c in colors}.values()
    colors = sorted(colors, key=lambda c: c.hsl[0], reverse=True)
    for color in colors:
        if color.saturation < .7:
            color.saturation = color.saturation ** .1
            color.luminance = .1
    return [c.hex_l for c in colors]

color_strings = get_pywal_colors()
pywal_colors = sort_hex_colors_by_saturation(color_strings)

mouse = rivalcfg.get_first_mouse()

def turn_mouse_off(mouse):
    mouse.set_z1_color('#000')
    mouse.set_z2_color('#000')
    mouse.set_z3_color('#000')
    mouse.set_logo_color('#000')

def set_colors(mouse, pywal_colors):
    mouse.set_z1_color(pywal_colors[0])
    mouse.set_z2_color(pywal_colors[1])
    mouse.set_z3_color(pywal_colors[2])
    mouse.set_logo_color(pywal_colors[3])

@contextlib.contextmanager
def openrgb_write_lock(timeout=1.0):
    fd = os.open(OPENRGB_WRITE_LOCK, os.O_CREAT | os.O_WRONLY, 0o666)
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    log("openrgb write lock still busy; blacking out anyway")
                    break
                time.sleep(0.01)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def has_name(device, names):
    name = (device.name or "").lower()
    return any(x in name for x in names)


def ensure_direct(device):
    if device.modes[device.active_mode].name.lower() == "direct":
        return
    for mode_name in ("Direct", "Static"):
        try:
            device.set_mode(mode_name)
            return
        except Exception:
            continue


def blackout_device(device, black):
    if has_name(device, ("aorus", "gigabyte")):
        d_led_zones = [z for z in device.zones if "D_LED" in z.name]
        for z in d_led_zones:
            z.resize(AIO_CHAIN_LENGTH)
        for z in device.zones:
            if z.leds:
                z.set_colors([black] * len(z.leds), fast=True)
        return
    device.set_colors([black] * len(device.leds), fast=True)


def ene_hardware_colors(device):
    from smbus2 import SMBus
    match = ENE_LOCATION.search(device.metadata.location or "")
    if not match:
        return None
    bus_path, address = match.group(1), int(match.group(2), 16)
    out = []
    with SMBus(bus_path) as bus:
        for i in range(3 * len(device.leds)):
            reg = ENE_DIRECT_COLORS_REG + i
            bus.write_word_data(address, 0x00, ((reg << 8) & 0xFF00) | ((reg >> 8) & 0xFF))
            out.append(bus.read_byte_data(address, 0x81))
    return out


def server_applied_black(device, timeout=1.0):
    deadline = time.monotonic() + timeout
    while True:
        device.update()
        if all((c.red, c.green, c.blue) == (0, 0, 0) for c in device.colors):
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.02)


def converge_ene_black(device, black):
    label = f"{device.name} #{device.id}"
    for attempt in range(1, BLACKOUT_ATTEMPTS + 1):
        if not server_applied_black(device):
            log(f"{label}: openrgb has not applied black after 1s (attempt {attempt})")
        time.sleep(WRITE_SETTLE_SECONDS)
        try:
            hardware = ene_hardware_colors(device)
        except OSError as e:
            log(f"{label}: hardware readback failed: {e}")
            return
        if hardware is None or not any(hardware):
            return
        lit = sum(1 for i in range(0, len(hardware), 3) if any(hardware[i:i + 3]))
        log(f"{label}: {lit} led(s) still lit after attempt {attempt}; resending black")
        device.set_colors([black] * len(device.leds), fast=True)
    log(f"{label}: still lit after {BLACKOUT_ATTEMPTS} attempts")


def blackout_openrgb():
    from openrgb import OpenRGBClient
    from openrgb.utils import RGBColor
    try:
        client = OpenRGBClient(name="hid-wrapper", protocol_version=3)
    except Exception as e:
        log(f"openrgb unreachable: {e}")
        return
    black = RGBColor(0, 0, 0)
    with openrgb_write_lock():
        targets = [d for d in client.devices if not has_name(d, PERIPHERAL_NAMES)]
        for d in targets:
            try:
                ensure_direct(d)
                blackout_device(d, black)
            except Exception as e:
                log(f"{d.name} #{d.id}: blackout failed: {e}")
        for d in targets:
            if has_name(d, DRAM_NAMES):
                converge_ene_black(d, black)
    try:
        client.disconnect()
    except Exception:
        pass

def restore_openrgb():
    subprocess.run(["wal-to-rgb"], capture_output=True)

if turn_on or (is_on and not turn_off):
    state_file.write_text('True')
    set_colors(mouse, pywal_colors)
    signal.alarm(0)
    restore_openrgb()
    is_on = True
elif turn_off:
    state_file.write_text('False')
    time.sleep(0.1)
    turn_mouse_off(mouse)
    signal.alarm(BLACKOUT_TIMEOUT_SECONDS)
    try:
        blackout_openrgb()
    except TimeoutError:
        log(f"blackout did not finish within {BLACKOUT_TIMEOUT_SECONDS}s")
    signal.alarm(0)
    is_on = False
else:
    state_file.write_text(str(is_on))
