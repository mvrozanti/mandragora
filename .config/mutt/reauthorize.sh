#!/bin/bash
# OAuth2 Re-authorization Script for Microsoft/Hotmail
# This will open a browser-based auth flow

set -e

TOKEN_FILE="/home/m/.cache/mutt/mvrozanti@hotmail.com.tokens"
# Thunderbird's public client ID - officially registered with Microsoft, no secret needed
CLIENT_ID="9e5f94bc-e8a4-4e73-b8be-63364c29d753"
EMAIL="mvrozanti@hotmail.com"

echo "================================================"
echo " NeoMutt OAuth2 Re-authorization for Hotmail"
echo "================================================"
echo ""
echo "This will authorize your Microsoft/Hotmail account"
echo "Email: $EMAIL"
echo ""
echo "Steps:"
echo "1. A URL will appear - paste it in your browser"
echo "2. Log in with your Microsoft account and accept permissions"
echo "3. After login, you'll get redirected to a page - copy the 'code=...' from the URL"
echo "4. Paste that code back here"
echo ""
read -p "Press ENTER to start authorization..."

echo ""
echo "Starting authorization..."
echo ""

# Use authcode flow with native redirect URI that Thunderbird is registered with
python3 /home/m/.config/mutt/mutt_oauth2.py \
    --encryption-pipe '' \
    --decryption-pipe '' \
    --provider microsoft \
    --client-id "$CLIENT_ID" \
    --client-secret "" \
    --authflow authcode \
    --verbose \
    --authorize \
    "$TOKEN_FILE"

echo ""
echo "================================================"
echo " Authorization Complete!"
echo "================================================"
echo ""
echo "Testing the connection..."
python3 /home/m/.config/mutt/mutt_oauth2.py \
    --encryption-pipe '' \
    --decryption-pipe '' \
    --provider microsoft \
    --client-id "$CLIENT_ID" \
    --client-secret "" \
    --authflow devicecode \
    --verbose \
    --test \
    "$TOKEN_FILE"

echo ""
echo "If tests passed above, you're all set!"
echo "You can now use NeoMutt with your Hotmail account."
