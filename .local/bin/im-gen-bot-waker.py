import json
import logging
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    level=logging.INFO,
    stream=sys.stderr,
)
log = logging.getLogger("im-gen-bot-waker")

TOKEN_FILE = Path(
    os.environ.get("IM_GEN_TOKEN_FILE", "/run/secrets/image_generator/telegram_bot_key")
)
API_BASE = os.environ.get("IM_GEN_WAKER_API_BASE", "https://api.telegram.org")
UNIT = os.environ.get("IM_GEN_BOT_UNIT", "im-gen-bot.service")
POLL_TIMEOUT = int(os.environ.get("IM_GEN_WAKER_POLL_TIMEOUT", "50"))
BACKOFF_S = float(os.environ.get("IM_GEN_WAKER_BACKOFF_S", "5"))
SETTLE_S = float(os.environ.get("IM_GEN_WAKER_SETTLE_S", "10"))
START_WAIT_S = float(os.environ.get("IM_GEN_WAKER_START_WAIT_S", "120"))


def read_token() -> str:
    env = os.environ.get("TELEGRAM_BOT_TOKEN")
    if env:
        return env.strip()
    if TOKEN_FILE.is_file():
        return TOKEN_FILE.read_text().strip()
    raise SystemExit(f"TELEGRAM_BOT_TOKEN or {TOKEN_FILE} required")


def unit_active() -> bool:
    return (
        subprocess.run(
            ["systemctl", "--user", "is-active", "--quiet", UNIT],
            check=False,
        ).returncode
        == 0
    )


def start_unit() -> None:
    subprocess.run(["systemctl", "--user", "start", UNIT], check=False)


def pending_update(token: str) -> bool:
    query = urllib.parse.urlencode({"timeout": POLL_TIMEOUT, "limit": 1})
    url = f"{API_BASE}/bot{token}/getUpdates?{query}"
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=POLL_TIMEOUT + 15) as response:
        payload = json.load(response)
    if not payload.get("ok"):
        raise RuntimeError("getUpdates returned ok=false")
    return bool(payload.get("result"))


def wait_for_start() -> None:
    deadline = time.monotonic() + START_WAIT_S
    while time.monotonic() < deadline:
        if unit_active():
            return
        time.sleep(1.0)
    log.warning("%s did not become active within %.0fs", UNIT, START_WAIT_S)


def main() -> None:
    token = read_token()
    log.info(
        "waker armed for %s (peek timeout=%ds, no offset so nothing is confirmed)",
        UNIT,
        POLL_TIMEOUT,
    )
    while True:
        if unit_active():
            time.sleep(SETTLE_S)
            continue
        try:
            pending = pending_update(token)
        except urllib.error.HTTPError as err:
            if err.code == 409:
                log.info("409 conflict - another poller holds the queue, backing off")
            else:
                log.warning("getUpdates HTTP %s", err.code)
            time.sleep(BACKOFF_S)
            continue
        except (urllib.error.URLError, TimeoutError, OSError, ValueError, RuntimeError) as err:
            log.warning("getUpdates failed: %s", type(err).__name__)
            time.sleep(BACKOFF_S)
            continue
        if not pending:
            continue
        log.info("pending update - starting %s", UNIT)
        start_unit()
        wait_for_start()
        time.sleep(SETTLE_S)


if __name__ == "__main__":
    main()
