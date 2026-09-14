import json
import os
import socketserver
import threading
import time
import urllib.parse
import urllib.request

BIND = os.environ.get("TICKER_BIND", "0.0.0.0")
PORT = int(os.environ.get("TICKER_PORT", "6614"))
TTL = int(os.environ.get("TICKER_TTL", "300"))
TIMEOUT = int(os.environ.get("TICKER_HTTP_TIMEOUT", "20"))
UA = os.environ.get("TICKER_USER_AGENT", "Mozilla/5.0 (mandragora-ticker)")

COINS = [
    ("BTC", "bitcoin", "Bitcoin"),
    ("ETH", "ethereum", "Ethereum"),
    ("SOL", "solana", "Solana"),
    ("XRP", "ripple", "XRP"),
    ("HYPE", "hyperliquid", "Hyperliquid"),
    ("LINK", "chainlink", "Chainlink"),
    ("PENDLE", "pendle", "Pendle"),
    ("XMR", "monero", "Monero"),
    ("UNI", "uniswap", "Uniswap"),
]

YAHOO = [
    ("GOLD", "GC=F", "Gold spot"),
    ("VIX", "^VIX", "Volatility"),
    ("NASDAQ", "^IXIC", "Nasdaq Composite"),
    ("IVVB11", "IVVB11.SA", "IVVB11 ETF"),
    ("USD", "DX-Y.NYB", "Dollar index"),
    ("BRL", "BRL=X", "USD to BRL"),
    ("CNY", "CNY=X", "USD to CNY"),
]

ORDER = [key for key, _, _ in COINS] + [key for key, _, _ in YAHOO]
LABELS = {key: label for key, _, label in COINS}
LABELS.update({key: label for key, _, label in YAHOO})

_lock = threading.Lock()
_cache = {"at": 0.0, "quotes": {}, "errors": []}


def _get(url):
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf8"))


def fetch_coins():
    ids = ",".join(cg for _, cg, _ in COINS)
    query = urllib.parse.urlencode({
        "ids": ids,
        "vs_currencies": "usd",
        "include_24hr_change": "true",
    })
    payload = _get("https://api.coingecko.com/api/v3/simple/price?" + query)
    out = {}
    for key, cg, _ in COINS:
        entry = payload.get(cg)
        if not entry or entry.get("usd") is None:
            continue
        out[key] = {
            "price": float(entry["usd"]),
            "change": entry.get("usd_24h_change"),
            "currency": "USD",
        }
    return out


def fetch_yahoo(symbol):
    url = ("https://query1.finance.yahoo.com/v8/finance/chart/"
           + urllib.parse.quote(symbol) + "?interval=1d&range=5d")
    payload = _get(url)
    chart = payload.get("chart") or {}
    results = chart.get("result") or []
    if not results:
        raise ValueError(chart.get("error") or "empty result")
    meta = results[0].get("meta") or {}
    price = meta.get("regularMarketPrice")
    if price is None:
        raise ValueError("no price")
    previous = meta.get("chartPreviousClose") or meta.get("previousClose")
    change = None
    if previous:
        change = (float(price) - float(previous)) / float(previous) * 100.0
    return {
        "price": float(price),
        "change": change,
        "currency": meta.get("currency") or "",
    }


def refresh():
    quotes = {}
    errors = []
    try:
        quotes.update(fetch_coins())
    except Exception as exc:
        errors.append("coingecko: " + str(exc)[:60])
    for key, symbol, _ in YAHOO:
        try:
            quotes[key] = fetch_yahoo(symbol)
        except Exception as exc:
            errors.append(key + ": " + str(exc)[:40])
    return quotes, errors


def snapshot(force=False):
    with _lock:
        age = time.time() - _cache["at"]
        if not force and _cache["quotes"] and age < TTL:
            return _cache["quotes"], int(age), _cache["errors"]
        quotes, errors = refresh()
        if quotes:
            _cache["quotes"] = quotes
            _cache["errors"] = errors
            _cache["at"] = time.time()
            return quotes, 0, errors
        _cache["errors"] = errors
        return _cache["quotes"], int(age), errors


def render(quotes, age, errors):
    lines = ["AGE %d" % age]
    for key in ORDER:
        entry = quotes.get(key)
        label = LABELS.get(key, key)
        if not entry:
            lines.append("Q %s - - %s" % (key, label))
            continue
        change = entry.get("change")
        change_text = "-" if change is None else "%+.2f" % change
        lines.append("Q %s %s %s %s" % (
            key, _money(entry["price"]), change_text, label))
    for err in errors[:4]:
        lines.append("ERR " + err)
    lines.append("END")
    return lines


def _money(value):
    if value >= 1000:
        return format(int(round(value)), ",d")
    if value >= 100:
        return "%.1f" % value
    if value >= 1:
        return "%.2f" % value
    return "%.4f" % value


class Handler(socketserver.StreamRequestHandler):
    timeout = 60

    def handle(self):
        while True:
            raw = self.rfile.readline()
            if not raw:
                return
            request = raw.decode("utf8", "replace").strip()
            if not request:
                self.reply("ERR empty request")
                continue
            verb = request.split()[0].upper()
            if verb == "QUIT":
                return
            if verb == "PING":
                self.reply("PONG")
                continue
            if verb in ("QUOTES", "REFRESH"):
                quotes, age, errors = snapshot(force=(verb == "REFRESH"))
                for line in render(quotes, age, errors):
                    self.reply(line)
                continue
            self.reply("ERR unknown verb " + verb)

    def reply(self, line):
        self.wfile.write((line + "\n").encode("utf8"))
        self.wfile.flush()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    Server((BIND, PORT), Handler).serve_forever()
