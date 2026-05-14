#!/usr/bin/env python3
"""Switch Logitech G Pro keyboard to Host (software) mode via HID++ 2.0.

Runs before keyledsd. On restart/shutdown, the keyboard can end up in
Onboard mode where it ignores LED frame writes; this forces it back to
Host mode so keyledsd's writes take effect.

Exits 0 on success (or if the keyboard isn't plugged in) so that a
missing keyboard never blocks keyledsd from starting.
"""
import glob
import os
import sys

VENDOR = "046D"
PRODUCT = "C339"
FEATURE_ONBOARD_PROFILES = 0x8100
HOST_MODE = 0x02


def find_led_hidraw():
    for sysdir in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(f"{sysdir}/device/uevent") as f:
                uevent = f.read()
        except OSError:
            continue
        if f"HID_ID=0003:0000{VENDOR}:0000{PRODUCT}" not in uevent:
            continue
        for line in uevent.splitlines():
            if line.startswith("HID_PHYS=") and line.rstrip().endswith("input1"):
                return f"/dev/{os.path.basename(sysdir)}"
    return None


def build_short(dev_idx, feat_idx, func_id, sw_id, params=b""):
    assert len(params) <= 3
    return bytes([0x10, dev_idx, feat_idx, (func_id << 4) | sw_id]) + params.ljust(3, b"\x00")


def build_long(dev_idx, feat_idx, func_id, sw_id, params=b""):
    assert len(params) <= 16
    return bytes([0x11, dev_idx, feat_idx, (func_id << 4) | sw_id]) + params.ljust(16, b"\x00")


def transact(fd, req, max_tries=10):
    os.write(fd, req)
    for _ in range(max_tries):
        resp = os.read(fd, 64)
        if len(resp) >= 4 and resp[0] in (0x10, 0x11) and resp[3] == req[3]:
            return resp
    raise RuntimeError("no matching HID++ response")


def main():
    dev = find_led_hidraw()
    if not dev:
        return 0
    try:
        fd = os.open(dev, os.O_RDWR)
    except PermissionError as e:
        print(f"cannot open {dev}: {e}", file=sys.stderr)
        return 1

    try:
        sw_id = 0x9
        req = build_short(
            0xFF, 0x00, 0x0, sw_id,
            bytes([FEATURE_ONBOARD_PROFILES >> 8, FEATURE_ONBOARD_PROFILES & 0xFF]),
        )
        resp = transact(fd, req)
        feat_idx = resp[4]
        if feat_idx == 0:
            return 0

        req = build_long(0xFF, feat_idx, 0x1, sw_id, bytes([HOST_MODE]))
        transact(fd, req)
    except Exception as e:
        print(f"host-mode set failed: {e}", file=sys.stderr)
        return 0
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
