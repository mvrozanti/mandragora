# `torrent.mvr.ac`

Transmission front-end. One torrent at a time: a thin rail of every
torrent on the left, the selected one in full on the right.

Chosen from the round-one `elicit-ui` deck (direction *Focus*), amended
so each rail item carries a 2px progress bar unless it has finished.

## Where the daemon actually lives

The daemon is **not** on the VPS. `transmission-daemon` runs as a user
service on `mandragora-desktop` and binds its RPC to `127.0.0.1:9091`.
The chain is the same shape as the `socat-tailnet@6684` theme bridge:

```
browser ──► caddy on the VPS (TLS + Authelia forward_auth)
              └─ host.docker.internal:6687   (= 172.18.0.1:6687)
                   └─ socat-tailnet@6687 on the VPS
                        └─ 100.115.80.79:6687  (desktop, tailscale0 only)
                             └─ transmission-rpc bridge (socat)
                                  └─ 127.0.0.1:9091  transmission
```

The desktop half is declared in
[`nix/modules/services/transmission-rpc-bridge.nix`](../../../../modules/services/transmission-rpc-bridge.nix)
as a `mandragora.hub.services` entry, so port 6687 is opened on
`tailscale0` only and never on the public firewall.

## Two things that will bite you

**Transmission answers `421 Misdirected Request` for any `Host` header
that is not an IP address or `localhost`.** `rpc-host-whitelist-enabled`
is `true` with an empty whitelist, which is transmission's DNS-rebinding
defence. A request arriving as `Host: torrent.mvr.ac` is refused before
it reaches the RPC layer, so the caddy label carries
`header_up Host 127.0.0.1:9091`. Verified directly:

```
Host: 127.0.0.1:9091   → 409 + X-Transmission-Session-Id
Host: torrent.mvr.ac   → 421 Misdirected Request
```

**`rpc-whitelist` is `127.0.0.1`.** The socat hop on the desktop is what
makes that work — socat connects to the loopback, so transmission sees a
local client. Nothing has to be written into `settings.json`, which the
daemon rewrites on exit and which is therefore not declarative.

## Free space and missing destinations

`free-space` is called per destination. It returns `-1` / an error for a
directory that no longer exists — which is a real state here: a number of
torrents point at a folder that has since been deleted. The UI shows
`destination missing` rather than swallowing it, because a torrent whose
destination is gone cannot be resumed until it is re-pointed.

## Deploy

```
nix/hosts/mandragora-vps/deploy-stacks.sh torrent
```

The desktop side needs a `mandragora-switch` first, so the bridge unit
exists before caddy tries to reach it.
