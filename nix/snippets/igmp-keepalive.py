import argparse
import socket
import struct
import sys
import time

IGMPV3_REPORT = 0x22
MODE_IS_EXCLUDE = 2
ALL_IGMPV3_ROUTERS = "224.0.0.22"
ROUTER_ALERT = b"\x94\x04\x00\x00"


def checksum(data):
    if len(data) % 2:
        data += b"\x00"
    total = sum(struct.unpack(f"!{len(data) // 2}H", data))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return ~total & 0xFFFF


def report(groups):
    records = b"".join(
        struct.pack("!BBH4s", MODE_IS_EXCLUDE, 0, 0, socket.inet_aton(group))
        for group in groups
    )
    header = struct.pack("!BBHHH", IGMPV3_REPORT, 0, 0, 0, len(groups))
    body = header + records
    return body[:2] + struct.pack("!H", checksum(body)) + body[4:]


def open_socket(interface):
    sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_IGMP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interface.encode())
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_OPTIONS, ROUTER_ALERT)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 0)
    mreqn = struct.pack("4s4si", b"\x00" * 4, b"\x00" * 4, socket.if_nametoindex(interface))
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, mreqn)
    return sock


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--interface", required=True)
    parser.add_argument("--interval", type=float, default=60)
    parser.add_argument("groups", nargs="+")
    args = parser.parse_args()

    packet = report(args.groups)
    sock = None
    failing = False
    while True:
        try:
            sock = sock or open_socket(args.interface)
            sock.sendto(packet, (ALL_IGMPV3_ROUTERS, 0))
            if failing:
                print(f"reporting {' '.join(args.groups)} on {args.interface} again", flush=True)
            failing = False
        except OSError as error:
            if not failing:
                print(f"report on {args.interface} failed: {error}", file=sys.stderr, flush=True)
            failing = True
            if sock:
                sock.close()
            sock = None
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
