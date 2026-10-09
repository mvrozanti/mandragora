# `pinserver` — self-hosted Jade blind PIN oracle

Blockstream's [`blind_pin_server`](https://github.com/Blockstream/blind_pin_server),
vendored unmodified at commit `62f97a1326800eb7161922272493ab9da6c4be5e`
(all files except `docker-compose.yml`, `.gitignore` and this README).

A Jade's seed is encrypted on the device under
`HMAC(server_key, PIN)`; `server_key` lives here, released only for the
correct blinded PIN, with three-strike wipe. The oracle never sees the PIN
or the seed: requests are ECDH-encrypted to this server's static key
(BIP-341-tweaked per request by a monotonic replay counter) and carry an
HMAC-blinded PIN secret.

No vhost of its own: it is reachable only as `jade.mvr.ac/api/pin/*`
(see [`jade`](../jade/)), and the Jade must be configured with this
server's public key, or its requests are encrypted to Blockstream's key
instead.

## Remote-only state (never in the repo)

Both paths are `.gitignore`d, which also shields them from
`deploy-stacks.sh --delete`.

| path on VPS | what | notes |
|---|---|---|
| `/home/opc/pinserver/server_private_key.key` | 32-byte secp256k1 static key | owned by uid 33 (`www-data` in the container), mode `0600`, mounted `:ro`; the server refuses to start if it is group/world readable |
| `/home/opc/pinserver/pins/` | one `<sha256(unit pubkey)>.pin` record per device | owned by uid 33 |

**The Jade cannot be unlocked without both.** Losing the key or the
`pins/` record means restoring the wallet from its recovery phrase. The
key is not under sops; backing it up is a deliberate, separate decision.

## Bring-up

```sh
../../deploy-stacks.sh --no-up pinserver
# place the key (generated offline) and the pins dir:
ssh opc@mandragora-vps 'sudo chown 33:33 /home/opc/pinserver/server_private_key.key \
  && sudo chmod 600 /home/opc/pinserver/server_private_key.key \
  && sudo mkdir -p /home/opc/pinserver/pins && sudo chown 33:33 /home/opc/pinserver/pins'
ssh opc@mandragora-vps 'cd /home/opc/pinserver && docker compose up -d --build'
```

The image has no `wget`/`curl`, so the healthcheck uses `python3` against
`/healthz` on `:8096`.
