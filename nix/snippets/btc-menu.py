#!/usr/bin/env python3
import argparse
import concurrent.futures
import hashlib
import hmac
import html
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
BECH32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

XPUB_FILES_ENV = "BTC_XPUB_FILES"
XPUB_LABELS_ENV = "BTC_XPUB_LABELS"

GAP_LIMIT = 20
STALE_AFTER = 20 * 60


def multisig_threshold():
    try:
        return int(os.environ.get("BTC_MULTISIG_M", "2"))
    except ValueError:
        return 2
ESPLORA = "https://blockstream.info/api"
COINGECKO = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd,brl"
MEMPOOL_PRICES = "https://mempool.space/api/v1/prices"
CACHE_DIR = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "btc-menu"
CACHE_FILE = CACHE_DIR / "cache.json"
UNIT_FILE = CACHE_DIR / "unit"
ICON = "₿"
UNITS = ["btc", "usd", "brl"]
WAYBAR_SIGNAL = "SIGRTMIN+15"


def mod_inv(a, m):
    return pow(a, m - 2, m)


def point_add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    x1, y1 = p1
    x2, y2 = p2
    if x1 == x2 and (y1 + y2) % P == 0:
        return None
    if p1 == p2:
        slope = (3 * x1 * x1) * mod_inv(2 * y1, P) % P
    else:
        slope = (y2 - y1) * mod_inv(x2 - x1, P) % P
    x3 = (slope * slope - x1 - x2) % P
    y3 = (slope * (x1 - x3) - y1) % P
    return (x3, y3)


def point_mul(k, point):
    result = None
    addend = point
    while k:
        if k & 1:
            result = point_add(result, addend)
        addend = point_add(addend, addend)
        k >>= 1
    return result


def base58_decode(text):
    number = 0
    for char in text:
        number = number * 58 + B58.index(char)
    raw = number.to_bytes((number.bit_length() + 7) // 8, "big")
    pad = len(text) - len(text.lstrip("1"))
    return b"\x00" * pad + raw


def ser_pubkey(point):
    x, y = point
    return (b"\x03" if y & 1 else b"\x02") + x.to_bytes(32, "big")


def parse_xpub(key):
    raw = base58_decode(key)
    if len(raw) != 82 or raw[0:4] not in (b"\x04\xb2\x47\x46", b"\x02\xaa\x7e\xd3"):
        return None
    checksum = hashlib.sha256(hashlib.sha256(raw[:-4]).digest()).digest()[:4]
    if checksum != raw[-4:]:
        return None
    chaincode = raw[13:45]
    keydata = raw[45:78]
    x = int.from_bytes(keydata[1:33], "big")
    y = pow((x * x * x + 7) % P, (P + 1) // 4, P)
    if (y & 1) != (keydata[0] & 1):
        y = P - y
    return chaincode, (x, y)


def ckd_pub(chaincode, point, index):
    data = ser_pubkey(point) + index.to_bytes(4, "big")
    digest = hmac.new(chaincode, data, hashlib.sha512).digest()
    il = int.from_bytes(digest[:32], "big")
    child_chaincode = digest[32:]
    child_point = point_add(point_mul(il, (GX, GY)), point)
    return child_chaincode, child_point


def bech32_polymod(values):
    generators = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    checksum = 1
    for value in values:
        top = checksum >> 25
        checksum = (checksum & 0x1FFFFFF) << 5 ^ value
        for i in range(5):
            if (top >> i) & 1:
                checksum ^= generators[i]
    return checksum


def bech32_hrp_expand(hrp):
    return [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]


def convert_bits(data, from_bits, to_bits, pad=True):
    acc = 0
    bits = 0
    out = []
    max_value = (1 << to_bits) - 1
    for value in data:
        acc = (acc << from_bits) | value
        bits += from_bits
        while bits >= to_bits:
            bits -= to_bits
            out.append((acc >> bits) & max_value)
    if pad and bits:
        out.append((acc << (to_bits - bits)) & max_value)
    return out


def segwit_address(version, program):
    data = [version] + convert_bits(program, 8, 5)
    values = bech32_hrp_expand("bc") + data + [0] * 6
    polymod = bech32_polymod(values) ^ 1
    checksum = [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]
    return "bc1" + "".join(BECH32[d] for d in data + checksum)


def address_for_point(point):
    digest = hashlib.new("ripemd160", hashlib.sha256(ser_pubkey(point)).digest()).digest()
    return segwit_address(0, digest)


def multisig_address(child_pubkeys, threshold):
    op_n = 0x50
    script = bytes([op_n + threshold])
    for pubkey in sorted(child_pubkeys):
        script += bytes([len(pubkey)]) + pubkey
    script += bytes([op_n + len(child_pubkeys), 0xAE])
    return segwit_address(0, hashlib.sha256(script).digest())


def derive_branch(chaincode, account_point, branch, limit):
    branch_chaincode, branch_point = ckd_pub(chaincode, account_point, branch)
    addresses = []
    for index in range(limit):
        _, point = ckd_pub(branch_chaincode, branch_point, index)
        addresses.append(address_for_point(point))
    return addresses


def http_json(url, timeout=25):
    request = urllib.request.Request(url, headers={"User-Agent": "mandragora-btc-menu"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def address_stats(address):
    try:
        data = http_json(f"{ESPLORA}/address/{address}")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return {"confirmed": 0, "unconfirmed": 0, "used": False, "ok": True}
        return {"ok": False}
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return {"ok": False}
    chain = data.get("chain_stats", {})
    mempool = data.get("mempool_stats", {})
    return {
        "confirmed": chain.get("funded_txo_sum", 0) - chain.get("spent_txo_sum", 0),
        "unconfirmed": mempool.get("funded_txo_sum", 0) - mempool.get("spent_txo_sum", 0),
        "used": chain.get("tx_count", 0) > 0 or chain.get("funded_txo_count", 0) > 0,
        "ok": True,
    }


def classify_key(xpub):
    try:
        raw = base58_decode(xpub)
    except (ValueError, KeyError):
        return "invalid"
    if len(raw) != 82:
        return "invalid"
    if raw[0:4] == b"\x04\xb2\x47\x46":
        return "zpub"
    if raw[0:4] == b"\x02\xaa\x7e\xd3":
        return "multisig"
    return "other"


def read_xpubs():
    files = [p for p in os.environ.get(XPUB_FILES_ENV, "").split(":") if p]
    labels = os.environ.get(XPUB_LABELS_ENV, "").split(":")
    xpubs = []
    for index, path in enumerate(files):
        try:
            value = Path(path).read_text().strip()
        except (FileNotFoundError, OSError):
            continue
        if not value:
            continue
        label = labels[index] if index < len(labels) and labels[index] else f"wallet {index + 1}"
        xpubs.append((label, value))
    return xpubs


def sum_addresses(addresses):
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        results = list(pool.map(address_stats, addresses))
    if sum(1 for stats in results if not stats.get("ok")):
        return None
    balance = 0
    for branch in (results[:GAP_LIMIT], results[GAP_LIMIT:]):
        empty_run = 0
        for stats in branch:
            if stats["used"]:
                empty_run = 0
                balance += stats["confirmed"] + stats["unconfirmed"]
            else:
                empty_run += 1
            if empty_run >= GAP_LIMIT:
                break
    return balance


def fetch_account(xpub):
    parsed = parse_xpub(xpub)
    if parsed is None:
        return {"balance": None, "error": "invalid xpub"}
    chaincode, account_point = parsed
    external = derive_branch(chaincode, account_point, 0, GAP_LIMIT)
    internal = derive_branch(chaincode, account_point, 1, GAP_LIMIT)
    balance = sum_addresses(external + internal)
    if balance is None:
        return {"balance": None, "error": "address lookups failed"}
    return {"balance": balance, "error": None}


def fetch_multisig(cosigners, threshold):
    addresses = []
    for branch in (0, 1):
        for index in range(GAP_LIMIT):
            child_pubkeys = []
            for chaincode, point in cosigners:
                branch_chaincode, branch_point = ckd_pub(chaincode, point, branch)
                _, child_point = ckd_pub(branch_chaincode, branch_point, index)
                child_pubkeys.append(ser_pubkey(child_point))
            addresses.append(multisig_address(child_pubkeys, threshold))
    balance = sum_addresses(addresses)
    if balance is None:
        return {"balance": None, "error": "address lookups failed"}
    return {"balance": balance, "error": None}


def fetch_prices():
    try:
        data = http_json(COINGECKO, timeout=15)
        usd = data["bitcoin"]["usd"]
        brl = data["bitcoin"]["brl"]
        return {"usd": usd, "brl": brl, "source": "coingecko"}
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, KeyError, json.JSONDecodeError):
        pass
    try:
        data = http_json(MEMPOOL_PRICES, timeout=15)
        return {"usd": data["USD"], "brl": None, "source": "mempool"}
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, KeyError, json.JSONDecodeError):
        return {"usd": None, "brl": None, "source": "none"}


def fetch_all():
    xpubs = read_xpubs()
    singles = [(label, xpub) for label, xpub in xpubs if classify_key(xpub) == "zpub"]
    multisig = [(label, xpub) for label, xpub in xpubs if classify_key(xpub) == "multisig"]
    unrecognized = [(label, xpub) for label, xpub in xpubs if classify_key(xpub) not in ("zpub", "multisig")]

    balances = []
    for label, xpub in singles:
        entry = fetch_account(xpub)
        entry["label"] = label
        balances.append(entry)

    cosigners = [parse_xpub(xpub) for _, xpub in multisig]
    cosigners = [cosigner for cosigner in cosigners if cosigner is not None]
    if len(multisig) >= 2 and len(cosigners) >= 2:
        entry = fetch_multisig(cosigners, multisig_threshold())
        entry["label"] = "multisig"
        balances.append(entry)
    else:
        for label, _ in multisig:
            balances.append({"label": label, "balance": None, "error": None, "note": "multisig — needs cosigners"})

    for label, _ in unrecognized:
        balances.append({"label": label, "balance": None, "error": "unrecognized key", "note": None})

    prices = fetch_prices()
    total = 0
    any_valid = False
    errors = []
    accounts = []
    for entry in balances:
        if entry["error"]:
            errors.append(entry["error"])
        if entry["balance"] is not None:
            total += entry["balance"]
            any_valid = True
        accounts.append({"label": entry["label"], "sats": entry["balance"], "note": entry.get("note")})
    return {
        "sats": total if any_valid else None,
        "usd": prices["usd"],
        "brl": prices["brl"],
        "accounts": accounts,
        "error": "; ".join(errors) if errors else None,
    }


def write_cache(data):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    data["fetched_at"] = time.time()
    CACHE_FILE.write_text(json.dumps(data))


def read_cache():
    try:
        return json.loads(CACHE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def format_btc(sats):
    if sats is None:
        return "--"
    btc = sats / 1e8
    return f"{btc:.8f}".rstrip("0").rstrip(".")


def format_fiat(sats, price, symbol):
    if sats is None or price is None:
        return "--"
    value = sats / 1e8 * price
    return f"{symbol} {value:,.2f}"


def read_unit():
    try:
        value = UNIT_FILE.read_text().strip()
        return value if value in UNITS else "btc"
    except (FileNotFoundError, OSError):
        return "btc"


def write_unit(unit):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    UNIT_FILE.write_text(unit)


def format_unit_value(sats, unit, prices):
    if unit == "usd":
        return format_fiat(sats, prices.get("usd"), "$")
    if unit == "brl":
        return format_fiat(sats, prices.get("brl"), "R$")
    return f"{ICON} {format_btc(sats)}"


def cmd_waybar(_args):
    cache = read_cache()
    if cache is None:
        print(json.dumps({"text": f"{ICON} --", "tooltip": "no cached balance yet", "class": "error"}))
        return 0
    sats = cache.get("sats")
    unit = read_unit()
    text = format_unit_value(sats, unit, cache)
    tooltip = [
        f"<b>BTC</b>  {format_btc(sats)}",
        f"<b>USD</b>  {format_fiat(sats, cache.get('usd'), '$')}",
        f"<b>BRL</b>  {format_fiat(sats, cache.get('brl'), 'R$')}",
    ]
    cls = "fresh"
    if cache.get("error"):
        cls = "error"
        tooltip.append("")
        tooltip.append(f"<i>{html.escape(cache['error'])}</i>")
    elif time.time() - cache.get("fetched_at", 0) > STALE_AFTER:
        cls = "stale"
        tooltip.append("")
        tooltip.append("<i>stale — click to refresh</i>")
    print(json.dumps({"text": text, "tooltip": "\n".join(tooltip), "class": cls}))
    return 0


def cmd_refresh(_args):
    data = fetch_all()
    write_cache(data)
    return 0


def cmd_cycle_unit(_args):
    unit = read_unit()
    write_unit(UNITS[(UNITS.index(unit) + 1) % len(UNITS)])
    subprocess.run(["pkill", "--signal", WAYBAR_SIGNAL, "waybar"], check=False)
    return 0


def spawn_refresh():
    try:
        subprocess.Popen(
            ["btc-menu", "refresh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except FileNotFoundError:
        subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "refresh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )


def cmd_pick(_args):
    data = read_cache()
    if data is None:
        data = fetch_all()
        write_cache(data)
    elif time.time() - data.get("fetched_at", 0) > STALE_AFTER:
        spawn_refresh()
    theme = Path.home() / ".config/rofi/themes/menu.rasi"
    while True:
        sats = data.get("sats")
        rows = [
            f"  <b>BTC</b>  {format_btc(sats)}",
            f"  <b>USD</b>  {format_fiat(sats, data.get('usd'), '$')}",
            f"  <b>BRL</b>  {format_fiat(sats, data.get('brl'), 'R$')}",
        ]
        for account in data.get("accounts", []):
            if account.get("sats") is not None:
                rows.append(f"     <i>{account['label']}</i>  {format_btc(account['sats'])} BTC")
            elif account.get("note"):
                rows.append(f"     <i>{account['label']}</i>  <i>{account['note']}</i>")
        if data.get("error"):
            rows.append("")
            rows.append(f"  <i>{html.escape(data['error'])}</i>")
        mesg = "<b>Enter</b> close · <b>Alt+r</b> refresh"
        proc = subprocess.run(
            [
                "rofi",
                "-dmenu",
                "-i",
                "-p",
                "bitcoin",
                "-theme",
                str(theme),
                "-theme-str",
                "window { width: 42%; } listview { lines: 8; }",
                "-markup-rows",
                "-no-custom",
                "-kb-custom-1",
                "Alt+r",
                "-mesg",
                mesg,
            ],
            input="\n".join(rows),
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode == 10:
            data = fetch_all()
            write_cache(data)
            continue
        return 0


def main():
    parser = argparse.ArgumentParser(prog="btc-menu")
    subparsers = parser.add_subparsers(dest="command", required=True)
    waybar_parser = subparsers.add_parser("waybar", help="emit waybar JSON from cache")
    waybar_parser.set_defaults(func=cmd_waybar)
    refresh_parser = subparsers.add_parser("refresh", help="fetch balances and update cache")
    refresh_parser.set_defaults(func=cmd_refresh)
    cycle_parser = subparsers.add_parser("cycle-unit", help="cycle the displayed unit")
    cycle_parser.set_defaults(func=cmd_cycle_unit)
    pick_parser = subparsers.add_parser("pick", help="open rofi balance popup")
    pick_parser.set_defaults(func=cmd_pick)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
