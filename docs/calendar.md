# Calendar

One calendar everywhere: the calendars the operator's email accounts own,
shown on the phone by its stock app, on the desktop by khal, on the kindle
by a read-only tile. Why the accounts and not the self-hosted server: vault
note *Calendar truth lives in the email accounts*.

```
account ──▶ phone      stock calendar app, signed in to the account
        ──▶ desktop    calendar-sync.timer (5 min) ─▶ vdirsyncer ─▶ ~/.local/share/calendars/<account>/
                         khal (Alt+K)                 reads and writes those folders
                         mandragora-agenda :6616      khal list, for the kindle
        ──▶ kindle     Agenda tile ─▶ mandragora-agenda on the LAN
```

## Pieces

| Piece | Where |
|---|---|
| pairs and storages | `.config/vdirsyncer/config` |
| what khal shows | `.config/khal/config` (one `discover` entry per account) |
| the timer's job | `.local/bin/calendar-sync.sh`: syncs every signed-in account, stamps `last-sync` |
| sign-in | `.local/bin/calendar-login.sh` |
| units and packages | `nix/modules/user/calendar.nix` |
| kindle side | `nix/hosts/mandragora-kindle/README.md`, section Agenda |

## State outside the repo

All of it under `~/.local/state/vdirsyncer/`, mode 700, none of it in sops:

| File | What |
|---|---|
| `google-client-id`, `google-client-secret` | the operator's own sign-in key from Google's console |
| `google.token` | the Google sign-in; its presence is what makes `calendar-sync` include the account |
| `status/` | vdirsyncer's memory of what it synced |
| `last-sync` | epoch of the last run in which every signed-in account synced |

Losing the directory loses no event: the accounts hold the data. Sign in
again and the folders refill.

## Signing in

`calendar-login google`. The first time there is no key and it prints the five
console steps; they end with a downloaded `client_secret_*.json` in
`~/Downloads`, which the next run splits into the two key files and deletes.
The project must be published, not left in testing: a testing project's
sign-in is ended by Google every seven days. Then a browser tab opens for the
account's consent, the calendars are discovered and the first sync runs.

## Behaviour worth knowing

- Conflicts: the server's copy wins (`conflict_resolution = "b wins"`).
- Calendar names in khal are the accounts' display names, copied by
  `vdirsyncer metasync` into each folder's `displayname` file.
- There is no default calendar until the first sign-in shows what the
  account calls its calendars, so `khal new` needs `-a <calendar>`.
- A calendar the account marks read-only (holidays, birthdays) refuses edits
  on the server; the sync run then fails for that account until the local
  edit is undone.
- `systemctl --user status calendar-sync` shows the last run; the kindle
  tile's header shows the age of the last good one.
