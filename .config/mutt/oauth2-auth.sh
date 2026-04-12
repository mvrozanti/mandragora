#!/bin/bash
# Complete OAuth2 auth for Microsoft/Hotmail
# Run this in a terminal where you can open a browser
set -e

CLIENT_ID="9e5f94bc-e8a4-4e73-b8be-63364c29d753"
EMAIL="mvrozanti@hotmail.com"
TOKEN_FILE="$HOME/.cache/mutt/mvrozanti@hotmail.com.tokens"
REDIRECT_URI="https://login.microsoftonline.com/common/oauth2/nativeclient"
SCOPE="offline_access https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/POP.AccessAsUser.All https://outlook.office.com/SMTP.Send"

rm -f "$TOKEN_FILE"

echo "============================================"
echo " Microsoft OAuth2 Auth for NeoMutt"
echo "============================================"
echo ""

python3 - "$CLIENT_ID" "$EMAIL" "$REDIRECT_URI" "$SCOPE" "$TOKEN_FILE" << 'PYEOF'
import sys, urllib.parse, secrets, base64, hashlib, json, urllib.request, subprocess
from datetime import datetime, timedelta

client_id, email, redirect_uri, scope, token_file = sys.argv[1:6]

# PKCE
verifier = secrets.token_urlsafe(90)
challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())[:-1].decode()

params = {
    'client_id': client_id,
    'scope': scope,
    'login_hint': email,
    'response_type': 'code',
    'redirect_uri': redirect_uri,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
}

url = f"https://login.microsoftonline.com/common/oauth2/v2.0/authorize?{urllib.parse.urlencode(params, quote_via=urllib.parse.quote)}"

print("STEP 1: Open this URL in your browser:\n")
print(url)
print()
print("STEP 2: Log in with your Microsoft account and accept permissions.")
print("STEP 3: After login, you'll see an error/warning page.")
print("STEP 4: Copy the FULL URL from your browser's address bar.")
print("   It starts with: https://login.microsoftonline.com/common/oauth2/nativeclient?code=...")
print()
redirect_url = input("Paste the full redirect URL: ").strip()

# Extract code
qs = urllib.parse.urlparse(redirect_url).query
code = urllib.parse.parse_qs(qs).get('code', [None])[0]
if not code:
    print("ERROR: No code found in URL!")
    sys.exit(1)

print(f"\nGot authorization code! Exchanging for tokens...")

token_params = {
    'client_id': client_id,
    'grant_type': 'authorization_code',
    'code': code,
    'code_verifier': verifier,
    'redirect_uri': redirect_uri,
    'scope': scope,
}

try:
    resp = urllib.request.urlopen(
        "https://login.microsoftonline.com/common/oauth2/v2.0/token",
        urllib.parse.urlencode(token_params).encode()
    )
    token_data = json.loads(resp.read())
except urllib.error.HTTPError as e:
    print(f"HTTP Error: {e.code} {e.reason}")
    print(e.read().decode())
    sys.exit(1)

if 'error' in token_data:
    print(f"ERROR: {token_data.get('error')}")
    print(token_data.get('error_description', ''))
    sys.exit(1)

token_json = {
    'registration': 'microsoft',
    'authflow': 'authcode',
    'email': email,
    'access_token': token_data['access_token'],
    'access_token_expiration': (datetime.now() + timedelta(seconds=int(token_data['expires_in']))).isoformat(),
    'refresh_token': token_data.get('refresh_token', ''),
    'client_id': client_id,
    'client_secret': '',
}

with open(token_file, 'w') as f:
    f.write(json.dumps(token_json))

print(f"\nToken saved to {token_file}")
print(f"Expires: {token_json['access_token_expiration']}")
PYEOF

echo ""
echo "============================================"
echo " Testing the connection..."
echo "============================================"
python3 ~/.config/mutt/mutt_oauth2.py \
  --encryption-pipe '' \
  --decryption-pipe '' \
  --provider microsoft \
  --client-id "$CLIENT_ID" \
  --client-secret "" \
  --verbose \
  --test \
  "$TOKEN_FILE"
