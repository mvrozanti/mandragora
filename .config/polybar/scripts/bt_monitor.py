#!/usr/bin/env python3
"""Listen to BlueZ D-Bus events and write BT status to a plain-text cache file."""
import os
import dbus
import dbus.mainloop.glib
from gi.repository import GLib

DEVICE = "04_57_91_D1_38_20"
DEVICE_PATH = f"/org/bluez/hci0/dev_{DEVICE}"
CACHE_FILE = "/tmp/polybar_bt_status"

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()

def write_cache(connected, battery):
    with open(CACHE_FILE, "w") as f:
        f.write(f"{int(connected)}\n{battery if battery else ''}\n")

def properties_changed(interface, changed, invalidated, path):
    if str(path) != DEVICE_PATH:
        return
    # Read current state
    connected = 0
    battery = ""
    if os.path.exists(CACHE_FILE):
        try:
            lines = open(CACHE_FILE).read().strip().split("\n")
            connected = int(lines[0])
            battery = lines[1] if len(lines) > 1 else ""
        except:
            pass
    if "Connected" in changed:
        connected = 1 if changed["Connected"] else 0
        print(f"[BT] Connected: {bool(connected)}")
    if "BatteryPercentage" in changed:
        battery = int(changed["BatteryPercentage"])
        print(f"[BT] Battery: {battery}%")
    write_cache(connected, battery)

bus.add_signal_receiver(
    properties_changed,
    dbus_interface="org.freedesktop.DBus.Properties",
    signal_name="PropertiesChanged",
    path_keyword="path",
)

# Initial state
try:
    dev = bus.get_object("org.bluez", DEVICE_PATH)
    props = dev.GetAll("org.bluez.Device1", dbus_interface="org.freedesktop.DBus.Properties")
    connected = bool(props.get("Connected", False))

    bat_path = f"/sys/class/power_supply/{DEVICE}/capacity"
    battery = None
    if os.path.exists(bat_path):
        with open(bat_path) as f:
            battery = int(f.read().strip())

    write_cache(connected, battery)
    print(f"[BT] Initial: connected={connected}, battery={battery}")
except Exception as e:
    print(f"[BT] Init error: {e}")
    write_cache(0, "")

print(f"[BT] Monitoring {DEVICE.replace('_', ':')}")
GLib.MainLoop().run()
