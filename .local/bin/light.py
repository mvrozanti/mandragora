import requests
import colorsys
import sys
import json
import subprocess
import os
import signal
import time

PID_FILE = "/tmp/light.pid"
LAMP_URL = "http://192.168.0.143/"
running = True

def signal_handler(signum, frame):
    global running
    running = False

def check_and_kill_existing_process():
    if os.path.exists(PID_FILE):
        with open(PID_FILE, "r") as pid_file:
            try:
                existing_pid = int(pid_file.read().strip())
                os.kill(existing_pid, 0)
            except (ProcessLookupError, ValueError):
                pass
            else:
                os.kill(existing_pid, signal.SIGTERM)
                time.sleep(1)
    with open(PID_FILE, "w") as pid_file:
        pid_file.write(str(os.getpid()))

def hex_to_hsvh(hex_color):
    hex_color = hex_color.lstrip('#')
    r = int(hex_color[0:2], 16) / 255.0
    g = int(hex_color[2:4], 16) / 255.0
    b = int(hex_color[4:6], 16) / 255.0
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return int(h * 360)

def yad_color_picker():
    result = subprocess.run(
        ['yad', '--color', '--geometry=300x300+center', '--fixed', '--undecorated'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    if result.returncode != 0:
        return None
    return result.stdout.decode().strip()

def main():
    global running
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    check_and_kill_existing_process()

    with open('/home/m/.cache/matugen/colors.json', 'r') as config_file:
        data = json.load(config_file)

    arg = sys.argv[1].lower() if len(sys.argv) > 1 else None
    params = {}

    if arg == 'toggle':
        params = {'m': 1, 'o': 1}
    elif arg == 'high':
        params = {'m': 1, 't0': 153, 'd0': 100}
    elif arg == 'low':
        params = {'m': 1, 't0': 500, 'd0': 100}
    elif arg == 'color':
        selected_color = yad_color_picker()
        if selected_color:
            h = hex_to_hsvh(selected_color)
            params = {'m': 1, 'h0': h, 'd0': 100}
    elif arg == 'rainbow':
        while running:
            for h in range(360):
                if not running:
                    break
                params = {'m': 1, 'h0': h, 'd0': 100}
                requests.get(LAMP_URL, params=params)
        return

    response = requests.get(LAMP_URL, params=params)
    print(response.text)

    if os.path.exists(PID_FILE):
        os.remove(PID_FILE)

if __name__ == "__main__":
    try:
        main()
    finally:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
