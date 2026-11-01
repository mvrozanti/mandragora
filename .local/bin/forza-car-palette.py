import json
import os
import subprocess
import sys
import time
from pathlib import Path

GAME_CLASS = "steam_app_2483190"
GAME_PROCESS = "forzahorizon6.e"
PALETTE_PATH = Path.home() / ".cache/forza-car/palette.json"
SAMPLE_SECONDS = 5.0
MIN_SATURATION = 0.22
CAR_CROP = "30%x35%+0+15%"
MATUGEN_STOPS = ("primary", "tertiary", "secondary", "primary_container")


def log(msg):
    sys.stderr.write(f"forza-car-palette: {msg}\n")
    sys.stderr.flush()


def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, timeout=20, **kw)


def game_running():
    return run(["pgrep", "-x", GAME_PROCESS]).returncode == 0


def active_game_monitor():
    out = run(["hyprctl", "activewindow", "-j"]).stdout
    try:
        window = json.loads(out)
    except ValueError:
        return None
    if window.get("class") != GAME_CLASS:
        return None
    monitors = json.loads(run(["hyprctl", "monitors", "-j"]).stdout)
    for m in monitors:
        if m["id"] == window.get("monitor"):
            return m["name"]
    return None


def capture_car(monitor, workdir):
    frame = workdir / "frame.png"
    car = workdir / "car.png"
    if run(["grim", "-o", monitor, str(frame)]).returncode != 0:
        return None
    if run(["magick", str(frame), "-gravity", "center", "-crop", CAR_CROP, "+repage", str(car)]).returncode != 0:
        return None
    return car


def saturation(image):
    out = run(["magick", str(image), "-colorspace", "HSL", "-format", "%[fx:mean.g]", "info:"]).stdout.strip()
    try:
        return float(out)
    except ValueError:
        return 0.0


def hex_of(value):
    if isinstance(value, str):
        return value.lstrip("#")
    if isinstance(value, dict):
        for key in ("dark", "color", "default", "light"):
            if key in value:
                return hex_of(value[key])
    return None


def scheme_from(image):
    out = run(["matugen", "image", str(image), "--dry-run", "--source-color-index", "0", "-j", "hex"]).stdout
    colors = json.loads(out)["colors"]
    stops = [hex_of(colors[name]) for name in MATUGEN_STOPS]
    if any(s is None for s in stops):
        raise ValueError("matugen scheme is missing a colour")
    return {"accent": stops[0], "stops": stops}


def write_palette(palette):
    PALETTE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = PALETTE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(palette))
    os.replace(tmp, PALETTE_PATH)


def clear_palette():
    if PALETTE_PATH.exists():
        PALETTE_PATH.unlink()
        log("game gone, wallpaper palette is back")


def main():
    workdir = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "forza-car-palette"
    workdir.mkdir(parents=True, exist_ok=True)
    last = None
    log(f"watching for {GAME_CLASS}, palettes go to {PALETTE_PATH}")
    while True:
        try:
            if not game_running():
                clear_palette()
                last = None
            else:
                monitor = active_game_monitor()
                if monitor:
                    car = capture_car(monitor, workdir)
                    if car is not None:
                        sat = saturation(car)
                        if sat >= MIN_SATURATION:
                            palette = scheme_from(car)
                            if palette != last:
                                write_palette(palette)
                                last = palette
                                log(f"car palette {palette['stops']} (crop saturation {sat:.2f})")
        except Exception as e:
            log(f"sample failed: {e}")
        time.sleep(SAMPLE_SECONDS)


if __name__ == "__main__":
    main()
