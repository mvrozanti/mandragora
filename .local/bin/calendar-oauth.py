import base64
import hashlib
import http.server
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

AUTHORITY = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
CLIENT_ID = "9e5f94bc-e8a4-4e73-b8be-63364c29d753"
SCOPE = "openid profile offline_access Mail.ReadWrite Calendars.ReadWrite MailboxSettings.Read Tasks.ReadWrite"
WAIT_SECONDS = 900

DONE_PAGE = "<!doctype html><meta charset=utf-8><title>calendar</title><p>{}</p><p>This tab can be closed.</p>"


class Outcome:
    query = None
    link = None


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if "code" not in query and "error" not in query:
            if urllib.parse.urlparse(self.path).path == "/":
                self.send_response(302)
                self.send_header("Location", Outcome.link)
            else:
                self.send_response(404)
            self.end_headers()
            return
        Outcome.query = query
        message = "Signed in." if "code" in query else "Microsoft refused the sign-in."
        body = DONE_PAGE.format(message).encode("utf8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        return


def redeem(code, redirect, verifier):
    form = urllib.parse.urlencode({
        "client_id": CLIENT_ID,
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect,
        "code_verifier": verifier,
        "scope": SCOPE,
    }).encode("utf8")
    try:
        with urllib.request.urlopen(AUTHORITY + "/token", form, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        return json.load(error)


def store(path, account, token):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf8") as handle:
        handle.write("{}={}\n".format(account.lower().replace("=", "\\="), token))


def main():
    if len(sys.argv) != 3:
        print("usage: calendar-oauth <account> <token file>", file=sys.stderr)
        return 2
    account, token_path = sys.argv[1], sys.argv[2]

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    redirect = "http://localhost:{}".format(server.server_port)
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode("ascii")).digest()).rstrip(b"=").decode("ascii")
    state = secrets.token_urlsafe(16)
    link = AUTHORITY + "/authorize?" + urllib.parse.urlencode({
        "client_id": CLIENT_ID,
        "response_type": "code",
        "redirect_uri": redirect,
        "scope": SCOPE,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
        "state": state,
        "login_hint": account,
    })
    Outcome.link = link
    print("Open this in the browser on this machine and sign in:", flush=True)
    print(redirect + "/", flush=True)

    deadline = time.monotonic() + WAIT_SECONDS
    while Outcome.query is None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            print("calendar-oauth: nobody signed in within {} minutes".format(WAIT_SECONDS // 60), file=sys.stderr)
            return 1
        server.timeout = remaining
        server.handle_request()
    server.server_close()

    query = Outcome.query
    if "error" in query:
        print("calendar-oauth: refused: {}: {}".format(
            query["error"][0], query.get("error_description", [""])[0]), file=sys.stderr)
        return 1
    if query.get("state", [""])[0] != state:
        print("calendar-oauth: the answer did not come from this sign-in", file=sys.stderr)
        return 1

    answer = redeem(query["code"][0], redirect, verifier)
    if "refresh_token" not in answer:
        print("calendar-oauth: no sign-in issued: {}: {}".format(
            answer.get("error", "?"), answer.get("error_description", "")), file=sys.stderr)
        return 1
    store(token_path, account, answer["refresh_token"])
    print("calendar-oauth: signed in, granted: {}".format(answer.get("scope", "?")), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
