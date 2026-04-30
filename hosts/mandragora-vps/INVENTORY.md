# mandragora-vps inventory

Snapshot of oracle (Oracle Cloud aarch64 VM) as it stood on 2026-04-29, prior to the planned NixOS migration. Source of truth for what `hosts/mandragora-vps/` must reproduce or what must be backed up before the migration.

## Cloud / instance

| Field | Value |
|---|---|
| Shape | `VM.Standard.A1.Flex` (Ampere ARM Always-Free) |
| OCPU / RAM / Net | 4 / 24 GiB / 4 Gbps |
| Region / AD | `sa-saopaulo-1` / `kQMu:SA-SAOPAULO-1-AD-1` (Fault Domain 1) |
| Instance OCID | `ocid1.instance.oc1.sa-saopaulo-1.antxeljrnd5mucycublegqy7pqhoxy6bdhkkhslopyi7f7ycxobdec6yzooa` |
| Image OCID | `ocid1.image.oc1.sa-saopaulo-1.aaaaaaaayh5xunxnrwgeg4cbgyfgsst4hcvyjdhjij5kqimyhrlary3xo4oq` (Oracle Linux 8.10 aarch64 UEK) |
| VNIC private IP | `10.0.0.112` in subnet `10.0.0.0/24` (router `10.0.0.1`, MAC `02:00:17:03:91:87`) |
| VNIC OCID | `ocid1.vnic.oc1.sa-saopaulo-1.abtxeljrlatmbicxkwrxrkmukt5ordto4pvijkgsi7em6twvg7hnthvpnkjq` |
| Public DNS | `mvrozanti.duckdns.org` → `146.235.51.189` |
| Created | 2024-07-23 by `mvrozanti@hotmail.com` |

## Boot / disk

- Single block device `sda` 200 GiB, presented as iSCSI (transparent to userspace).
- Partitions: `sda1` 100M `/boot/efi`, `sda2` 1G `/boot`, `sda3` 198.9G LVM PV.
- LVM VG `ocivolume`, LVs `root` (188.9G `/`, ext4) and `oled` (10G `/var/oled`, unused).
- 97G used / 93G free on `/`.

### Kernel cmdline (current)

```
BOOT_IMAGE=(hd0,gpt2)/vmlinuz-5.15.0-208.159.3.el8uek.aarch64 \
  root=/dev/mapper/ocivolume-root ro \
  console=ttyAMA0 console=ttyAMA0,115200 \
  rd.lvm.vg=ocivolume rd.lvm.lv=ocivolume/root \
  netroot=iscsi:169.254.0.2:::1:iqn.2015-02.oracle.boot:uefi \
  rd.iscsi.param=node.session.timeo.replacement_timeout=6000 \
  ip=dhcp,dhcp6 rd.net.timeout.dhcp=10 rd.net.timeout.carrier=5 \
  net.ifnames=1 nvme_core.shutdown_timeout=10
```

**Migration constraint:** initramfs must include iSCSI (`open-iscsi`, `iscsi_tcp` module) and DHCP networking, otherwise the box will fail to come up after `nixos-anywhere`. Oracle target IQN is `iqn.2015-02.oracle.boot:uefi` reached at `169.254.0.2`. Console must stay on `ttyAMA0,115200` so the OCI serial console keeps working as the recovery path.

## Workloads to preserve

### Containers (4 compose stacks + 1 standalone)

| Stack | Path | Containers | Notes |
|---|---|---|---|
| Seafile | `/home/opc/seafile/` | `seafile`, `seafile-mysql` (MariaDB 10.11), `seafile-memcached` | Bind: `./db` → MariaDB datadir; `./shared` → Seafile data. Image `seafileltd/seafile-mc:latest` 11.0.13. `SEAFILE_SERVER_LETSENCRYPT=false` (currently self-signed). |
| Hummingbot | `/home/opc/high-frequency-trading-experiments/` | `hummingbot`, `hummingbot-dashboard` (8501), `hummingbot-jupyter` (8888) | Binds: `conf/ scripts/ data/ logs/ certs/ notebooks/`. `network_mode: host` for hummingbot. |
| crypto-fetcher | `/home/opc/crypto-experiments/crypto-fetcher/` | `binance_fetcher` (built locally), `redis` (6.2-alpine) | `network_mode: host`. **The 15-month-uptime standalone `redis` container is owned by this stack.** |
| crypto-stox | `/home/opc/drive/crypto-stox/` | duplicate of crypto-fetcher compose at time of inventory — confirm before migration whether this is dead/duplicate. |

### Custom systemd

- `collector.service` — runs `python3 collector.py` from `/home/opc/orderbook_collector` as `opc`, logs to `collector.log` in same dir. Auto-restart on failure.
- `iptables-openvpn.service` — oneshot, `ExecStart=/etc/iptables/add-openvpn-rules.sh` and matching `rm-`. Adds NAT for the OpenVPN tun.
- `openvpn@server.service` (legacy) and `openvpn-server@.service` — current OpenVPN server.
- `unified-monitoring-agent.timer` — Oracle Cloud monitoring; **drop after migration**, replace with NixOS metrics if wanted.
- `oswatcher.service`, `oracle-cloud-agent.service`, `oracle-cloud-agent-updater.service` — Oracle agents; **drop**, not needed for our purposes.

### OpenVPN server state to back up

`/etc/openvpn/`:
- `ca.crt`, `ca.key` (CA private key — sops it after backup)
- `server_ADDErF2LVlWVy39M.crt`, `server_ADDErF2LVlWVy39M.key`
- `tls-crypt.key`
- `server.conf`
- `client-template.txt`
- `ipp.txt` (persistent client IP assignments)
- `ccd/` (per-client overrides)
- `client/` (issued client configs)
- `easy-rsa/pki/` (entire PKI tree, including issued `awooga.crt`/`.key`)
- `crl.pem`

NixOS target: `services.openvpn.servers.<name>.config = builtins.readFile ...`, with the keys/certs deployed via `sops-nix` (CA key + server key + tls-crypt key are the secret-bearing ones).

### DDNS

- `/home/opc/duckdns_update.sh` — single-line curl to `https://www.duckdns.org/update?domains=mvrozanti&token=…&ip=`.
- Triggered by **root**'s crontab: `*/5 * * * * /home/opc/duckdns_update.sh >/dev/null 2>&1`.
- NixOS target: `services.ddclient.protocol = "duckdns"` with the token in sops, or a tiny systemd timer.

### iptables / firewall

- `firewalld` (`public` zone active) permits: `dhcpv6-client`, `ssh`, `80/tcp`, `443/tcp`, `2717/tcp`, `2718/tcp`, `1194/udp`, `1194/tcp`, `25565/tcp`, `3306/tcp` (3306 publicly is concerning but separate matter).
- Saved iptables-restore file at `/etc/iptables/rules.v4` includes the **OCI-mandatory `BareMetalInstanceServices` chain** for `169.254.0.0/16` metadata access. This must be replicated under NixOS via `networking.firewall.extraCommands` or `networking.nftables.tables.…`, otherwise iSCSI/metadata/DNS/NTP all break.
- 1194/tcp + 1194/udp are OpenVPN.

### Other state under `/home/opc/`

| Path | Size | Notes |
|---|---|---|
| `seafile/` | 14 G | Seafile data (`shared/seafile` 14G, `db/` 251M). |
| `orderbook_collector/` | 2.7 G | `collector.py`, `ob_collector_parquet.py`, `ob_collector_robust.py`, `setup.sh`, `data/` (parquet), logs. |
| `4chan-international-visualizer/` | ? | Personal project. |
| `aspect.asc` | ? | Single file. |
| `cry/` | ? | Personal project. |
| `crypto-experiments/` | (parent of crypto-fetcher) | |
| `drive/` | (parent of crypto-stox) | |
| `high-frequency-trading-experiments/` | (parent of Hummingbot) | |
| `iptables-rules`, `rules.v4` | tiny | Saved iptables snapshots (the source of `/etc/iptables/rules.v4`). |

`/var/lib/docker` total: **33 G** (image layers + the `redis` standalone container's anonymous volume). Most of this is rebuildable from the compose files, except the redis dump if persistence is enabled — to verify before migration.

## Public exposure today (firewalld + OCI VCN)

| Port | Service | Target after migration |
|---|---|---|
| 22/tcp | sshd | tailnet only |
| 80/tcp | Seafile (cleartext) | drop, or LE HTTP-01 only |
| 443/tcp | Seafile self-signed (blocked at OCI security list) | tailnet only |
| 1194/tcp+udp | OpenVPN | keep public (it's the point) — or migrate users to Tailscale and retire |
| 3306/tcp | MariaDB | **drop publicly**, internal only |
| 8501/tcp | Hummingbot dashboard | tailnet only |
| 8888/tcp | Jupyter | tailnet only |
| 6379/tcp | Redis | drop publicly, internal only |
| 25565/tcp | (Minecraft? unclear) | confirm during migration |
| 2717, 2718/tcp | (unclear) | confirm during migration |

OCI VCN security list currently blocks 443 inbound; only 80/22/UDP-1194 actually reach the box from the internet.

## Migration acceptance criteria

The migration is "done" when, on the NixOS-built `mandragora-vps`:

1. SSH on tailnet works for `m@mandragora-vps`.
2. Seafile container is back up with the same data and DB; web UI reachable on tailnet.
3. OpenVPN server back up with same CA/certs; existing client configs (`awooga.ovpn`) still connect.
4. Hummingbot, dashboard, jupyter, crypto-fetcher, redis all running with their bind-mount data intact.
5. `collector.service` running, `collector.log` continues being appended.
6. DDNS updater still pushing the public IP to DuckDNS.
7. Public firewall closed except for what's actually intended (1194 if OpenVPN stays public; 80/22 only if needed).
8. OCI metadata/DNS/iSCSI still work (the `BareMetalInstanceServices` rules are replicated).
