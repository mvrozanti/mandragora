# Hotmail OAuth2 Setup for NeoMutt

## Current Setup
- **Token file**: `~/mvrozanti@hotmail.com.tokens`
- **Client ID**: `9e5f94bc-e8a4-4e73-b8be-63364c29d753` (Thunderbird's public client ID)
- **GPG recipient**: `mvrozanti@hotmail.com`

## When Authentication Fails (tokens expired)

Run this script:
```bash
~/.config/mutt/oauth2-auth.sh
```

It will:
1. Print a URL - open it in your browser
2. Log in and accept permissions
3. You'll land on an error page - **copy the full URL from the address bar**
4. Paste the URL back in the terminal

The script automatically saves tokens and tests the connection.

## Re-authorize manually

```bash
rm -f ~/mvrozanti@hotmail.com.tokens
~/.config/mutt/oauth2-auth.sh
```

## Test the connection

```bash
export GPG_TTY=$(tty)
python3 ~/.config/mutt/mutt_oauth2.py \
  --encryption-pipe "gpg -qe -r mvrozanti@hotmail.com" \
  --provider microsoft \
  --client-id "9e5f94bc-e8a4-4e73-b8be-63364c29d753" \
  --client-secret "" \
  --verbose \
  --test \
  ~/mvrozanti@hotmail.com.tokens
```

## Token Lifespan
- **Access token**: ~1 hour (auto-refreshed by the script)
- **Refresh token**: ~90 days (requires re-auth after expiration)
