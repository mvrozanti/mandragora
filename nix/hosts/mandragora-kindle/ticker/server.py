import json
import os
import socketserver
import threading
import time
import urllib.parse
import urllib.request

BIND = os.environ.get("TICKER_BIND", "0.0.0.0")
PORT = int(os.environ.get("TICKER_PORT", "6614"))
QUOTE_TTL = int(os.environ.get("TICKER_TTL", "300"))
TIMEOUT = int(os.environ.get("TICKER_HTTP_TIMEOUT", "20"))
UA = os.environ.get("TICKER_USER_AGENT", "Mozilla/5.0 (mandragora-ticker)")
MAX_BARS = int(os.environ.get("TICKER_MAX_BARS", "130"))

INSTRUMENTS = [
    ("BTC", "BTC-USD", "Bitcoin"),
    ("ETH", "ETH-USD", "Ethereum"),
    ("SOL", "SOL-USD", "Solana"),
    ("XRP", "XRP-USD", "XRP"),
    ("HYPE", "HYPE32196-USD", "Hyperliquid"),
    ("LINK", "LINK-USD", "Chainlink"),
    ("PENDLE", "PENDLE-USD", "Pendle"),
    ("XMR", "XMR-USD", "Monero"),
    ("UNI", "UNI7083-USD", "Uniswap"),
    ("GOLD", "GC=F", "Gold spot"),
    ("VIX", "^VIX", "Volatility"),
    ("NASDAQ", "^IXIC", "Nasdaq Composite"),
    ("IVVB11", "IVVB11.SA", "IVVB11 ETF"),
    ("USD", "DX-Y.NYB", "Dollar index"),
    ("BRL", "BRL=X", "USD to BRL"),
    ("CNY", "CNY=X", "USD to CNY"),
]

ORDER = [key for key, _, _ in INSTRUMENTS]
SYMBOL = {key: sym for key, sym, _ in INSTRUMENTS}
LABEL = {key: label for key, _, label in INSTRUMENTS}

_lock = threading.Lock()
_cache = {"at": 0.0, "quotes": {}, "bars": {}, "errors": []}


def _fetch(symbol):
    url = ("https://query1.finance.yahoo.com/v8/finance/chart/"
           + urllib.parse.quote(symbol) + "?interval=1d&range=6mo")
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        payload = json.loads(response.read().decode("utf8"))

    chart = payload.get("chart") or {}
    results = chart.get("result") or []
    if not results:
        raise ValueError("empty result")
    result = results[0]
    meta = result.get("meta") or {}
    stamps = result.get("timestamp") or []
    quote = ((result.get("indicators") or {}).get("quote") or [{}])[0]

    bars = []
    for i in range(len(stamps)):
        row = [quote.get(f, [])[i] if i < len(quote.get(f, [])) else None
               for f in ("open", "high", "low", "close")]
        if None in row:
            continue
        bars.append([stamps[i]] + [round(float(v), 6) for v in row])
    bars = bars[-MAX_BARS:]

    price = meta.get("regularMarketPrice")
    if price is None and bars:
        price = bars[-1][4]
    if price is None:
        raise ValueError("no price")

    change = None
    if len(bars) >= 2 and bars[-2][4]:
        change = (float(price) - bars[-2][4]) / bars[-2][4] * 100.0
    elif meta.get("chartPreviousClose"):
        previous = float(meta["chartPreviousClose"])
        change = (float(price) - previous) / previous * 100.0

    return {"price": float(price), "change": change,
            "currency": meta.get("currency") or ""}, bars


def _refresh():
    quotes, bars, errors = {}, {}, []
    for key, symbol, _ in INSTRUMENTS:
        try:
            quote, series = _fetch(symbol)
            quotes[key] = quote
            bars[key] = series
        except Exception as exc:
            errors.append(key + ": " + str(exc)[:40])
    return quotes, bars, errors


def snapshot(force=False):
    with _lock:
        age = time.time() - _cache["at"]
        fresh_enough = _cache["quotes"] and age < QUOTE_TTL
        if not force and fresh_enough:
            return _cache["quotes"], _cache["bars"], int(age), _cache["errors"]
        quotes, bars, errors = _refresh()
        if quotes:
            _cache.update({"quotes": quotes, "bars": bars,
                           "errors": errors, "at": time.time()})
            return quotes, bars, 0, errors
        _cache["errors"] = errors
        return _cache["quotes"], _cache["bars"], int(age), errors


def money(value):
    if value >= 1000:
        return format(int(round(value)), ",d")
    if value >= 100:
        return "%.1f" % value
    if value >= 1:
        return "%.2f" % value
    return "%.4f" % value


def num(value):
    return ("%.6f" % value).rstrip("0").rstrip(".")


def quote_lines(quotes, age, errors):
    lines = ["AGE %d" % age]
    for key in ORDER:
        entry = quotes.get(key)
        if not entry:
            lines.append("Q %s - - %s" % (key, LABEL[key]))
            continue
        change = entry.get("change")
        lines.append("Q %s %s %s %s" % (
            key, money(entry["price"]),
            "-" if change is None else "%+.2f" % change,
            LABEL[key]))
    for err in errors[:4]:
        lines.append("ERR " + err)
    return lines


def candle_lines(bars, keys, count):
    lines = []
    for key in keys:
        series = (bars.get(key) or [])[-count:]
        lines.append("K %s %d" % (key, len(series)))
        for bar in series:
            lines.append("C %d %s %s %s %s" % (
                bar[0], num(bar[1]), num(bar[2]), num(bar[3]), num(bar[4])))
    return lines


class Handler(socketserver.StreamRequestHandler):
    timeout = 120

    def handle(self):
        while True:
            raw = self.rfile.readline()
            if not raw:
                return
            request = raw.decode("utf8", "replace").strip()
            if not request:
                self.reply("ERR empty request")
                continue
            parts = request.split()
            verb = parts[0].upper()

            if verb == "QUIT":
                return
            if verb == "PING":
                self.reply("PONG")
                continue
            if verb in ("QUOTES", "REFRESH"):
                quotes, _, age, errors = snapshot(force=(verb == "REFRESH"))
                for line in quote_lines(quotes, age, errors):
                    self.reply(line)
                self.reply("END")
                continue
            if verb == "CANDLES":
                target = parts[1].upper() if len(parts) > 1 else "ALL"
                try:
                    count = min(MAX_BARS, max(2, int(parts[2])))
                except (IndexError, ValueError):
                    count = MAX_BARS
                if target != "ALL" and target not in SYMBOL:
                    self.reply("ERR unknown instrument " + target)
                    self.reply("END")
                    continue
                _, bars, _, _ = snapshot()
                keys = ORDER if target == "ALL" else [target]
                for line in candle_lines(bars, keys, count):
                    self.reply(line)
                self.reply("END")
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
