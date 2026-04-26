import fcntl
import json
import signal
import sys
from pathlib import Path

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

if turn_on or (is_on and not turn_off):
    set_colors(mouse, pywal_colors)
    is_on = True
elif turn_off:
    turn_mouse_off(mouse)
    is_on = False

state_file.write_text(str(is_on))
