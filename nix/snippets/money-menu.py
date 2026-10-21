#!/usr/bin/env python3
import argparse
import concurrent.futures
import datetime
from decimal import Decimal
import hashlib
import hmac
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
BECH32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

XPUB_FILES_ENV = "MONEY_XPUB_FILES"
XPUB_LABELS_ENV = "MONEY_XPUB_LABELS"
BINANCE_KEY_ENV = "MONEY_BINANCE_KEY_FILE"
BINANCE_SECRET_ENV = "MONEY_BINANCE_SECRET_FILE"
LENDED_ENV = "MONEY_LENDED_FILE"
EVM_ADDRESS_ENV = "MONEY_EVM_ADDRESS_FILE"
LENDED_CDB_ENV = "MONEY_LENDED_CDB_FILE"

GAP_LIMIT = 20
STALE_AFTER = 20 * 60
DUST_USD = 1.0


def multisig_threshold():
    try:
        return int(os.environ.get("MONEY_MULTISIG_M", "2"))
    except ValueError:
        return 2


ESPLORA_ENDPOINTS = [
    "https://blockstream.info/api",
    "https://mempool.space/api",
]
LOOKUP_TIMEOUT = 10
RETRIES = 2
USER_AGENT = "mandragora-money-menu"
FETCH_ERRORS = (OSError, ValueError, KeyError, TypeError, IndexError, ZeroDivisionError)
COINGECKO = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd,brl"
BINANCE = "https://api.binance.com"
MEMPOOL_PRICES = "https://mempool.space/api/v1/prices"
BLOCKSCOUT = "https://eth.blockscout.com/api/v2"
BLOCKSCOUT_MAX_PAGES = 5
HL_INFO = "https://api.hyperliquid.xyz/info"
BCB_CDI = "https://api.bcb.gov.br/dados/serie/bcdata.sgs.12/dados?formato=json"
HYPEREVM_RPC = "https://rpc.hyperliquid.xyz/evm"
BALANCE_OF = "0x70a08231"
HYPEREVM_TOKENS = [
    ("WHYPE", "0x5555555555555555555555555555555555555555", 18),
    ("kHYPE", "0xfD739d4e423301CE9385c1fb8850539D657C296D", 18),
    ("stHYPE", "0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1", 18),
    ("UBTC", "0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463", 8),
    ("UETH", "0xBe6727B535545C67d5cAa73dEa54865B92CF7907", 18),
    ("USDT0", "0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb", 6),
    ("USDe", "0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34", 18),
    ("feUSD", "0x02c6a2fA58cC01A18B8D9E00eA48d65E4dF26c70", 18),
    ("USDHL", "0xb50A96253aBDF803D85efcDce07Ad8becBc52BD5", 6),
]
BINANCE_WALLETS = [
    ("funding", "/sapi/v1/asset/get-funding-asset", "POST", None, ("free", "locked", "freeze", "withdrawing")),
    ("earn", "/sapi/v1/simple-earn/flexible/position", "GET", "rows", ("totalAmount",)),
    ("earn", "/sapi/v1/simple-earn/locked/position", "GET", "rows", ("amount",)),
]
STABLECOINS = {"USD", "USDT", "USDC", "FDUSD", "BUSD", "TUSD", "USDP", "DAI", "USDE", "USDT0", "FEUSD", "USDHL"}
PRICE_ALIASES = {"WHYPE": "HYPE", "KHYPE": "HYPE", "STHYPE": "HYPE", "UBTC": "BTC", "WBTC": "BTC", "UETH": "ETH", "WETH": "ETH"}
STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
CACHE_DIR = STATE_HOME / "money-menu"
LEGACY_DIR = STATE_HOME / "btc-menu"
CACHE_FILE = CACHE_DIR / "cache.json"
UNIT_FILE = CACHE_DIR / "unit"
HIDDEN_FILE = CACHE_DIR / "hidden"
LAST_FILE = CACHE_DIR / "last.json"
CACHE_VERSION = 2
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


def http_json(url, timeout=25, body=None, headers=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"User-Agent": USER_AGENT, "Content-Type": "application/json", **(headers or {})},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"), strict=False)


def address_stats(address):
    for attempt in range(RETRIES):
        for base in ESPLORA_ENDPOINTS:
            try:
                data = http_json(f"{base}/address/{address}", timeout=LOOKUP_TIMEOUT)
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    return {"confirmed": 0, "unconfirmed": 0, "used": False, "ok": True}
                continue
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
                continue
            chain = data.get("chain_stats", {})
            mempool = data.get("mempool_stats", {})
            return {
                "confirmed": chain.get("funded_txo_sum", 0) - chain.get("spent_txo_sum", 0),
                "unconfirmed": mempool.get("funded_txo_sum", 0) - mempool.get("spent_txo_sum", 0),
                "used": chain.get("tx_count", 0) > 0 or chain.get("funded_txo_count", 0) > 0,
                "ok": True,
            }
        time.sleep(2 ** attempt)
    return {"ok": False}


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


def read_secret(env):
    path = os.environ.get(env, "")
    try:
        return Path(path).read_text().strip() if path else ""
    except OSError:
        return ""


def read_evm_address():
    value = read_secret(EVM_ADDRESS_ENV)
    return value if re.fullmatch(r"0x[0-9a-fA-F]{40}", value) else None


def fetch_coingecko_fx():
    try:
        data = http_json(COINGECKO, timeout=15)
        usd = float(data["bitcoin"]["usd"])
        return usd, float(data["bitcoin"]["brl"]) / usd
    except FETCH_ERRORS:
        return None, None


def fetch_binance_tickers():
    try:
        return {row["symbol"]: float(row["price"]) for row in http_json(f"{BINANCE}/api/v3/ticker/price", timeout=20)}
    except FETCH_ERRORS:
        return {}


def fetch_hl_mids():
    try:
        mids = http_json(HL_INFO, timeout=15, body={"type": "allMids"})
        return {coin: float(mid) for coin, mid in mids.items() if not coin.startswith("@")}
    except FETCH_ERRORS:
        return {}


def fetch_mempool_btc_usd():
    try:
        return float(http_json(MEMPOOL_PRICES, timeout=15)["USD"])
    except FETCH_ERRORS:
        return None


def fetch_prices():
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        fx = pool.submit(fetch_coingecko_fx)
        tickers = pool.submit(fetch_binance_tickers)
        mids = pool.submit(fetch_hl_mids)
        btc_usd, usd_brl = fx.result()
        tickers, mids = tickers.result(), mids.result()
    return {
        "btc_usd": btc_usd or tickers.get("BTCUSDT") or fetch_mempool_btc_usd(),
        "usd_brl": usd_brl or tickers.get("USDTBRL"),
        "tickers": tickers,
        "mids": mids,
    }


def usd_price(prices, asset):
    asset = PRICE_ALIASES.get(asset.upper(), asset.upper())
    if asset in STABLECOINS:
        return 1.0
    if asset == "BTC":
        return prices["btc_usd"]
    if asset == "BRL":
        return 1 / prices["usd_brl"] if prices["usd_brl"] else None
    tickers = prices["tickers"]
    for quote in ("USDT", "USDC", "FDUSD"):
        if asset + quote in tickers:
            return tickers[asset + quote]
    if asset + "BTC" in tickers and prices["btc_usd"]:
        return tickers[asset + "BTC"] * prices["btc_usd"]
    return prices["mids"].get(asset)


def holding(label, asset, amount, usd=None, note=None):
    return {"label": label, "asset": asset, "amount": amount, "usd": usd, "note": note}


def priced(prices, label, asset, amount):
    price = usd_price(prices, asset)
    if price is None:
        return holding(label, asset, amount, note="unpriced")
    return holding(label, asset, amount, amount * price)


def venue(venue_id, label, holdings=None, error=None, note=None):
    return {"id": venue_id, "label": label, "holdings": holdings or [], "error": error, "note": note}


def fetch_bitcoin(prices):
    xpubs = read_xpubs()
    if not xpubs:
        return None
    singles = [(label, xpub) for label, xpub in xpubs if classify_key(xpub) == "zpub"]
    multisig = [(label, xpub) for label, xpub in xpubs if classify_key(xpub) == "multisig"]
    unrecognized = [label for label, xpub in xpubs if classify_key(xpub) not in ("zpub", "multisig")]

    holdings = []
    errors = [f"{label}: unrecognized key" for label in unrecognized]
    for label, xpub in singles:
        entry = fetch_account(xpub)
        if entry["error"]:
            errors.append(f"{label}: {entry['error']}")
        else:
            holdings.append(priced(prices, label, "BTC", entry["balance"] / 1e8))

    cosigners = [parse_xpub(xpub) for _, xpub in multisig]
    cosigners = [cosigner for cosigner in cosigners if cosigner is not None]
    if len(multisig) >= 2 and len(cosigners) >= 2:
        entry = fetch_multisig(cosigners, multisig_threshold())
        if entry["error"]:
            errors.append(f"multisig: {entry['error']}")
        else:
            holdings.append(priced(prices, "multisig", "BTC", entry["balance"] / 1e8))
    else:
        holdings += [holding(label, "BTC", None, note="multisig — needs cosigners") for label, _ in multisig]

    return venue("bitcoin", "Bitcoin", holdings, "; ".join(errors) or None)


def binance_signed(key, secret, path, method="GET", params=""):
    query = "&".join(part for part in (params, f"recvWindow=10000&timestamp={int(time.time() * 1000)}") if part)
    signature = hmac.new(secret.encode(), query.encode(), hashlib.sha256).hexdigest()
    request = urllib.request.Request(
        f"{BINANCE}{path}?{query}&signature={signature}",
        data=b"" if method == "POST" else None,
        method=method,
        headers={"User-Agent": USER_AGENT, "X-MBX-APIKEY": key},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode("utf-8"))


def binance_balances(key, secret, prices):
    balances = {}
    notes = []

    def add(wallet, asset, amount):
        if amount <= 0:
            return
        entry = balances.setdefault(asset, {"amount": Decimal(0), "wallets": []})
        entry["amount"] += amount
        if wallet not in entry["wallets"]:
            entry["wallets"].append(wallet)

    account = binance_signed(key, secret, "/api/v3/account", params="omitZeroBalances=true")
    for row in account.get("balances", []):
        add("spot", row["asset"], Decimal(row["free"]) + Decimal(row["locked"]))

    for wallet, path, method, rows_key, fields in BINANCE_WALLETS:
        try:
            data = binance_signed(key, secret, path, method, params="size=100" if method == "GET" else "")
        except urllib.error.HTTPError as error:
            if 400 <= error.code < 500:
                notes.append(f"{wallet}: HTTP {error.code}")
                continue
            raise
        for row in data.get(rows_key, []) if rows_key else data:
            add(wallet, row["asset"], sum(Decimal(str(row.get(field) or 0)) for field in fields))

    for asset in [a for a in balances if a.startswith("LD") and len(a) > 2]:
        if usd_price(prices, asset) is None and usd_price(prices, asset[2:]) is not None:
            entry = balances.pop(asset)
            add("earn", asset[2:], entry["amount"])
    return balances, notes


def fetch_binance(prices):
    key, secret = read_secret(BINANCE_KEY_ENV), read_secret(BINANCE_SECRET_ENV)
    if not key or not secret:
        return venue("binance", "Binance", note="no API key")
    try:
        balances, notes = binance_balances(key, secret, prices)
    except FETCH_ERRORS as error:
        return venue("binance", "Binance", error=str(error))
    holdings = [
        priced(prices, " · ".join(entry["wallets"]), asset, float(entry["amount"]))
        for asset, entry in balances.items()
    ]
    return venue("binance", "Binance", holdings, note="; ".join(notes) or None)


def blockscout_tokens(address):
    items = []
    params = {"type": "ERC-20"}
    for _ in range(BLOCKSCOUT_MAX_PAGES):
        page = http_json(f"{BLOCKSCOUT}/addresses/{address}/tokens?{urllib.parse.urlencode(params)}", timeout=20)
        items += page.get("items", [])
        if not page.get("next_page_params"):
            break
        params = {"type": "ERC-20", **page["next_page_params"]}
    return items


def fetch_ethereum(prices, address):
    holdings = []
    try:
        info = http_json(f"{BLOCKSCOUT}/addresses/{address}", timeout=20)
        wei = int(info.get("coin_balance") or 0)
        if wei:
            rate = usd_price(prices, "ETH") or float(info.get("exchange_rate") or 0) or None
            amount = wei / 1e18
            holdings.append(holding("native", "ETH", amount, amount * rate if rate else None))
        for item in blockscout_tokens(address):
            token = item.get("token") or {}
            if not token.get("exchange_rate") or token.get("reputation") not in (None, "ok"):
                continue
            amount = int(item["value"]) / 10 ** int(token.get("decimals") or 0)
            if amount > 0:
                holdings.append(holding("erc-20", token.get("symbol") or "?", amount, amount * float(token["exchange_rate"])))
    except FETCH_ERRORS as error:
        return venue("ethereum", "Ethereum", error=str(error))
    return venue("ethereum", "Ethereum", holdings)


def hl_info(body):
    return http_json(HL_INFO, timeout=15, body=body)


def hl_spot_mids():
    meta, contexts = hl_info({"type": "spotMetaAndAssetCtxs"})
    names = {token["index"]: token["name"] for token in meta["tokens"]}
    mids = {}
    for pair, context in zip(meta["universe"], contexts):
        base, quote = pair["tokens"]
        if quote == 0 and context.get("midPx"):
            mids[names[base]] = float(context["midPx"])
    return mids


def fetch_hypercore(prices, address):
    holdings = []
    perps = hl_info({"type": "clearinghouseState", "user": address})
    value = float(perps["marginSummary"]["accountValue"])
    if value:
        count = len(perps.get("assetPositions", []))
        holdings.append(holding("perps", "USDC", value, value, f"{count} open" if count else None))

    spot_mids = None
    for row in hl_info({"type": "spotClearinghouseState", "user": address}).get("balances", []):
        amount = float(row["total"])
        if not amount:
            continue
        price = usd_price(prices, row["coin"])
        if price is None:
            spot_mids = hl_spot_mids() if spot_mids is None else spot_mids
            price = spot_mids.get(row["coin"])
        if price is None:
            holdings.append(holding("spot", row["coin"], amount, note="unpriced"))
        else:
            holdings.append(holding("spot", row["coin"], amount, amount * price))

    equity = sum(float(row["equity"]) for row in hl_info({"type": "userVaultEquities", "user": address}))
    if equity:
        holdings.append(holding("vaults", "USDC", equity, equity))

    staking = hl_info({"type": "delegatorSummary", "user": address})
    staked = sum(float(staking[field]) for field in ("delegated", "undelegated", "totalPendingWithdrawal"))
    if staked:
        holdings.append(priced(prices, "staked", "HYPE", staked))
    return holdings


def evm_rpc(url, calls):
    batch = [{"jsonrpc": "2.0", "id": index, "method": method, "params": params} for index, (method, params) in enumerate(calls)]
    replies = {reply["id"]: reply for reply in http_json(url, timeout=20, body=batch)}
    results = []
    for index in range(len(calls)):
        reply = replies.get(index, {})
        if "result" not in reply:
            raise ValueError(f"rpc: {reply.get('error', 'no reply')}")
        results.append(int(reply["result"], 16) if reply["result"] not in (None, "0x") else 0)
    return results


def fetch_hyperevm(prices, address):
    owner = address[2:].lower().rjust(64, "0")
    calls = [("eth_getBalance", [address, "latest"])]
    calls += [("eth_call", [{"to": contract, "data": BALANCE_OF + owner}, "latest"]) for _, contract, _ in HYPEREVM_TOKENS]
    native, *balances = evm_rpc(HYPEREVM_RPC, calls)
    holdings = [priced(prices, "evm", "HYPE", native / 1e18)] if native else []
    for (symbol, _, decimals), raw in zip(HYPEREVM_TOKENS, balances):
        if raw:
            holdings.append(priced(prices, "evm", symbol, raw / 10**decimals))
    return holdings


def fetch_hyperliquid(prices, address):
    try:
        holdings = fetch_hypercore(prices, address) + fetch_hyperevm(prices, address)
    except FETCH_ERRORS as error:
        return venue("hyperliquid", "Hyperliquid", error=str(error))
    return venue("hyperliquid", "Hyperliquid", holdings)


def read_lended_btc(prices, path):
    try:
        sats = int(Path(path).read_text().strip())
    except (OSError, ValueError):
        return holding("lended", "BTC", None, note="unset")
    return priced(prices, "lended", "BTC", sats / 1e8)


def cdi_factor(since, percent):
    today = datetime.date.today()
    url = f"{BCB_CDI}&dataInicial={since:%d/%m/%Y}&dataFinal={today:%d/%m/%Y}"
    for attempt in range(RETRIES):
        try:
            rows = http_json(url, timeout=20)
            break
        except FETCH_ERRORS:
            if attempt == RETRIES - 1:
                raise
            time.sleep(2)
    factor = Decimal(1)
    for row in rows:
        day = datetime.datetime.strptime(row["data"], "%d/%m/%Y").date()
        if since <= day < today:
            factor *= 1 + Decimal(row["valor"]) / 100 * Decimal(str(percent)) / 100
    return factor


def fetch_cdb(prices, terms):
    since = datetime.date.fromisoformat(terms["since"])
    percent = terms.get("cdi_percent", 100)
    amount = float(Decimal(str(terms["principal_brl"])) * cdi_factor(since, percent))
    label = f"cdb · {percent:g}% CDI since {since:%b %-d}"
    return priced(prices, label, "BRL", amount)


def fetch_lended(prices):
    holdings = []
    path = os.environ.get(LENDED_ENV, "")
    if path:
        holdings.append(read_lended_btc(prices, path))
    cdb = read_secret(LENDED_CDB_ENV)
    if cdb:
        try:
            holdings.append(fetch_cdb(prices, json.loads(cdb)))
        except FETCH_ERRORS as error:
            return venue("lended", "Lended", error=f"cdb: {error}")
    return venue("lended", "Lended", holdings) if holdings else None


def is_dust(entry):
    return entry["usd"] is not None and entry["usd"] < DUST_USD


def fold_dust(holdings):
    holdings = sorted(holdings, key=lambda entry: (entry["usd"] is None, -(entry["usd"] or 0)))
    dust = [entry for entry in holdings if is_dust(entry)]
    if len(dust) < 2:
        return holdings
    kept = [entry for entry in holdings if not is_dust(entry)]
    summary = holding(f"{len(dust)} assets", "dust", None, sum(entry["usd"] for entry in dust), ", ".join(entry["asset"] for entry in dust))
    return kept + [summary]


def held_prices(venues, prices):
    held = {}
    for item in venues:
        for entry in item["holdings"]:
            asset = PRICE_ALIASES.get(entry["asset"].upper(), entry["asset"])
            if entry["amount"] and entry["usd"] and asset not in ("dust", "BRL") and asset.upper() not in STABLECOINS:
                price, value = held.get(asset, (entry["usd"] / entry["amount"], 0))
                held[asset] = (price, value + entry["usd"])
    ranked = sorted(held.items(), key=lambda pair: (pair[0] != "BTC", -pair[1][1]))
    result = {asset: price for asset, (price, _) in ranked}
    if "BTC" not in result and prices["btc_usd"]:
        result = {"BTC": prices["btc_usd"], **result}
    return result


def settle(venues, prices, previous):
    now = time.time()
    earlier = {item["id"]: item for item in (previous or {}).get("venues", [])}
    complete = True
    for item in venues:
        if item["error"]:
            old = earlier.get(item["id"])
            if old and not old.get("missing"):
                item["holdings"] = old["holdings"]
                item["fetched_at"] = old.get("fetched_at")
                item["stale_since"] = old.get("stale_since") or old.get("fetched_at")
            else:
                item["missing"] = True
                complete = False
        else:
            item["holdings"] = fold_dust(item["holdings"])
            item["fetched_at"] = now
        item["usd"] = sum(entry["usd"] for entry in item["holdings"] if entry["usd"] is not None)
    errors = [f"{item['label']}: {item['error']}" for item in venues if item["error"]]
    return {
        "version": CACHE_VERSION,
        "fx": {"btc_usd": prices["btc_usd"], "usd_brl": prices["usd_brl"]},
        "prices": held_prices(venues, prices),
        "venues": venues,
        "total_usd": sum(item["usd"] for item in venues) if complete and prices["btc_usd"] else None,
        "error": "; ".join(errors) or None,
    }


def fetch_all(previous=None):
    prices = fetch_prices()
    address = read_evm_address()
    fetchers = [
        lambda: fetch_bitcoin(prices),
        lambda: fetch_binance(prices),
        lambda: fetch_ethereum(prices, address) if address else None,
        lambda: fetch_hyperliquid(prices, address) if address else None,
        lambda: fetch_lended(prices),
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(fetchers)) as pool:
        venues = [item for item in pool.map(lambda fetch: fetch(), fetchers) if item is not None]
    return settle(venues, prices, previous)


def migrate_state():
    if LEGACY_DIR.is_dir() and not CACHE_DIR.exists():
        LEGACY_DIR.rename(CACHE_DIR)


def write_cache(data):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    data["fetched_at"] = time.time()
    CACHE_FILE.write_text(json.dumps(data))


def read_cache():
    try:
        data = json.loads(CACHE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    return data if data.get("version") == CACHE_VERSION else None


def refresh(previous):
    data = fetch_all(previous)
    write_cache(data)
    return data


def format_btc(btc):
    return f"{btc:.8f}".rstrip("0").rstrip(".")


def format_qty(amount):
    if amount >= 1000:
        return f"{amount:,.2f}"
    if amount >= 1:
        return f"{amount:,.4f}".rstrip("0").rstrip(".")
    return f"{amount:.4g}"


def convert(usd, unit, fx):
    if usd is None:
        return None
    if unit == "usd":
        return usd
    if unit == "brl":
        return usd * fx["usd_brl"] if fx.get("usd_brl") else None
    return usd / fx["btc_usd"] if fx.get("btc_usd") else None


def format_unit(usd, unit, fx):
    value = convert(usd, unit, fx)
    if value is None:
        return "--"
    if unit == "usd":
        return f"$ {value:,.2f}"
    if unit == "brl":
        return f"R$ {value:,.2f}"
    return f"{ICON} {format_btc(value)}"


def read_unit():
    try:
        value = UNIT_FILE.read_text().strip()
        return value if value in UNITS else "btc"
    except (FileNotFoundError, OSError):
        return "btc"


def write_unit(unit):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    UNIT_FILE.write_text(unit)


def read_hidden():
    try:
        return HIDDEN_FILE.read_text().strip() == "1"
    except (FileNotFoundError, OSError):
        return False


def write_hidden(hidden):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    if hidden:
        HIDDEN_FILE.write_text("1")
    else:
        HIDDEN_FILE.unlink(missing_ok=True)


def read_last():
    try:
        return json.loads(LAST_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def write_last(value):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    LAST_FILE.write_text(json.dumps(value))


def totals_lines(total, fx):
    return [f"<b>{name}</b>  {format_unit(total, unit, fx)}" for unit, name in zip(UNITS, ("BTC", "USD", "BRL"))]


def venue_line(item, total, unit, fx):
    label = html.escape(item["label"])
    if item.get("missing"):
        return f"<i>{label}  unavailable</i>"
    if item.get("note") and not item["holdings"]:
        return f"<i>{label}  {html.escape(item['note'])}</i>"
    share = f"  {item['usd'] / total:.0%}" if total else ""
    line = f"<b>{label}</b>  {format_unit(item['usd'], unit, fx)}{share}"
    return f"<i>{line} · stale</i>" if item.get("stale_since") else line


def holding_line(entry, unit, fx):
    label = html.escape(entry["label"])
    asset = html.escape(entry["asset"])
    if entry["amount"] is None and entry["usd"] is None:
        return f"<i>{asset} {label}  {html.escape(entry['note'] or '--')}</i>"
    quantity = f"{format_qty(entry['amount'])} {asset}" if entry["amount"] is not None else asset
    return f"{quantity}  <i>{label}</i>  {format_unit(entry['usd'], unit, fx)}"


def cmd_waybar(_args):
    cache = read_cache()
    if cache is None:
        print(json.dumps({"text": f"{ICON} --", "tooltip": "no cached balance yet", "class": "error"}))
        return 0
    fx = cache["fx"]
    total = cache.get("total_usd")
    unit = read_unit()
    hidden = read_hidden()
    tooltip = totals_lines(total, fx) + [""] + [venue_line(item, total, unit, fx) for item in cache["venues"]]
    stale = [item["label"] for item in cache["venues"] if item.get("stale_since")]
    cls = "fresh"
    if total is None:
        cls = "error"
        tooltip += ["", f"<i>{html.escape(cache.get('error') or 'incomplete')}</i>"]
    elif stale:
        cls = "stale"
        tooltip += ["", f"<i>last known values for {html.escape(', '.join(stale))}</i>"]
    elif time.time() - cache.get("fetched_at", 0) > STALE_AFTER:
        cls = "stale"
        tooltip += ["", "<i>stale — click to refresh</i>"]
    if cls == "fresh":
        value = round(convert(total, unit, fx) or 0, 8 if unit == "btc" else 2)
        last = read_last()
        if isinstance(last, dict) and last.get("unit") == unit and last.get("value") != value:
            cls = "up" if value > last["value"] else "down"
        write_last({"unit": unit, "value": value})
    text = format_unit(total, unit, fx)
    if hidden:
        text = re.sub(r"\d", "•", text)
        tooltip = ["<i>amounts hidden — click to reveal</i>"]
        cls = "hidden"
    print(json.dumps({"text": text, "tooltip": "\n".join(tooltip), "class": cls}))
    return 0


def cmd_json(_args):
    cache = read_cache()
    if cache is None:
        print(json.dumps({"total_usd": None, "venues": [], "fx": {}, "prices": {}, "unit": read_unit(), "hidden": read_hidden(), "error": "no cached balance yet"}))
        return 0
    cache["unit"] = read_unit()
    cache["hidden"] = read_hidden()
    cache["stale"] = time.time() - cache.get("fetched_at", 0) > STALE_AFTER
    print(json.dumps(cache))
    return 0


def cmd_refresh(_args):
    refresh(read_cache())
    return 0


def cmd_cycle_unit(_args):
    unit = read_unit()
    write_unit(UNITS[(UNITS.index(unit) + 1) % len(UNITS)])
    subprocess.run(["pkill", "--signal", WAYBAR_SIGNAL, "waybar"], check=False)
    return 0


def cmd_toggle_hidden(_args):
    write_hidden(not read_hidden())
    subprocess.run(["pkill", "--signal", WAYBAR_SIGNAL, "waybar"], check=False)
    return 0


def spawn_refresh():
    try:
        subprocess.Popen(
            ["money-menu", "refresh"],
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
        data = refresh(None)
    elif time.time() - data.get("fetched_at", 0) > STALE_AFTER:
        spawn_refresh()
    theme = Path.home() / ".config/rofi/themes/menu.rasi"
    while True:
        fx = data["fx"]
        total = data.get("total_usd")
        unit = read_unit()
        rows = [f"  {line}" for line in totals_lines(total, fx)]
        for item in data["venues"]:
            rows.append(f"  {venue_line(item, total, unit, fx)}")
            rows += [f"     {holding_line(entry, unit, fx)}" for entry in item["holdings"]]
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
                "money",
                "-theme",
                str(theme),
                "-theme-str",
                "window { width: 42%; } listview { lines: 14; }",
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
            data = refresh(data)
            continue
        return 0


def main():
    migrate_state()
    parser = argparse.ArgumentParser(prog="money-menu")
    subparsers = parser.add_subparsers(dest="command", required=True)
    waybar_parser = subparsers.add_parser("waybar", help="emit waybar JSON from cache")
    waybar_parser.set_defaults(func=cmd_waybar)
    json_parser = subparsers.add_parser("json", help="emit cached popup data as JSON")
    json_parser.set_defaults(func=cmd_json)
    refresh_parser = subparsers.add_parser("refresh", help="fetch balances and update cache")
    refresh_parser.set_defaults(func=cmd_refresh)
    cycle_parser = subparsers.add_parser("cycle-unit", help="cycle the displayed unit")
    cycle_parser.set_defaults(func=cmd_cycle_unit)
    hidden_parser = subparsers.add_parser("toggle-hidden", help="hide or reveal the waybar money module")
    hidden_parser.set_defaults(func=cmd_toggle_hidden)
    pick_parser = subparsers.add_parser("pick", help="open rofi balance popup")
    pick_parser.set_defaults(func=cmd_pick)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
