# Python Dependencies on Mandragora

Detail for [`AGENTS.md`](../AGENTS.md) rule #7. The rule: express Python
environments in Nix; fall back to a venv only when an upstream project
owns its own runtime and Nix-ifying would be hostile.

---

## Why declarative

- **Impermanence (rule #5).** Root is wiped every boot. A `.venv` in
  `/home` survives, but one in `/tmp`, `/var`, or a service state dir
  does not. Anything bootstrapped imperatively at first run is a hidden
  setup step that breaks "reproducibility from scratch in < 30 min"
  (rule #1).
- **Dedup.** `/nix/store` is content-addressed. Ten projects sharing
  `numpy==1.26.4` resolve to one on-disk copy. Ten `.venv`s = ten
  copies. Declarative wins on disk too — the "venvs save space" instinct
  inverts on NixOS.
- **Provenance.** A Nix expression names every dep, version, and
  upstream source. `pip freeze` names versions but not patch sources,
  and `pip install` outside a lockfile is non-reproducible by
  construction.

---

## Decision tree

Pick the leftmost branch that fits:

1. **Package is in `nixpkgs` and you just need to run a script** →
   `python3.withPackages (ps: [ ps.foo ps.bar ])`. See examples below.
2. **One-off script with deps, distributed as a binary** →
   `pkgs.writers.writePython3Bin "name" { libraries = [ ps.foo ]; } ''…''`.
3. **Project with `pyproject.toml` you own** →
   - `uv.lock` present → `uv2nix`.
   - `poetry.lock` present → `poetry2nix`.
   - Neither → `pyproject.nix` (or upgrade the project to one of the
     above).
4. **Package missing from `nixpkgs`** → write a `buildPythonPackage`
   derivation in `nix/pkgs/<name>.nix` and register it in
   `nix/pkgs/overlays.nix`. Upstream the package to nixpkgs if it's
   broadly useful.
5. **Interactive shell for hacking on a project** → per-project
   `flake.nix` with a `devShells.default` exposing
   `python3.withPackages`. Enter with `nix develop`.
6. **Upstream project owns its own environment (InvokeAI, ComfyUI,
   anything pinning CUDA-coupled wheels on a faster cadence than
   nixpkgs)** → see "Exemption pattern" below.

---

## Examples already in this repo

| Pattern | File | Notes |
|---|---|---|
| `buildPythonPackage` + `withPackages` closure | `nix/pkgs/bot-python.nix` | Firefox marionette driver + ~11 bot deps as one immutable closure. |
| Single-package daemon env | `nix/modules/services/rgb-control.nix` | `aiohttp` only. |
| Single-package daemon env | `nix/modules/services/ollama-context-proxy.nix` | `aiohttp` only. |
| Six named user envs | `nix/modules/user/home.nix` | `pyDict`, `pySinon`, `hidWrapper`, `light`, `walToRgb`, plus nvim env (`pynvim`/`grip`/`psutil`). |
| Single-package user env | `nix/modules/user/rss-menu.nix` | `feedparser` only. |
| CLI env | `nix/modules/shared/home-cli.nix` | `pynvim`/`grip`/`psutil`. |

Read these before writing anything new — copy the closest shape rather
than inventing a seventh dialect.

---

## Exemption pattern (upstream-owned venv)

When upstream's installer (a) pins CUDA-coupled wheels Nix cannot
easily reproduce, *and* (b) is maintained on a cadence nixpkgs cannot
track, wrapping it in Nix is hostile. Use a systemd launcher instead.
Reference implementation: `nix/modules/services/im-gen-web.nix`.

Required shape:

- **Launcher is a `pkgs.writeShellScript`.** No `.venv` creation inside
  the Nix module — bootstrap is done out-of-band (user runs the
  upstream installer once).
- **`ConditionPathExists` on the venv's Python binary.** The unit
  refuses to start if the venv is missing, surfacing the bootstrap
  step as a clear error instead of silent failure.
- **Idempotent dep guard.** A shell function (e.g. `ensure_pkg`) calls
  `uv pip install` only when `python -c "import X"` fails. No
  unconditional installs on every start.
- **Document the upstream + reason inline.** A short comment-equivalent
  in the module (commit message or systemd `Description=`) naming the
  upstream project and why Nix-ifying is impractical *today*. Revisit
  when the upstream stabilises.

Current carve-outs:
- `nix/modules/services/im-gen-web.nix` — InvokeAI (`invokeai-venv`,
  `.uv-venv` for `uv` itself).
- `.local/share/stt-via-telegram/bot.sh` — Whisper-based STT bot;
  `uv venv` bootstrap.

---

## Anti-patterns

- Project venv inside the repo for code we own.
- `pip install` in a shell script for code we own.
- `requirements.txt` checked in without a corresponding Nix
  expression.
- Adding a new exemption without naming the upstream and the
  Nix-hostility reason.
- Creating a venv inside a state directory that does not survive
  reboot (rule #5).

---

## See also

- [`AGENTS.md`](../AGENTS.md) — rule #7 (this doc's source).
- [`persistence.md`](persistence.md) — what survives reboot; informs
  where (if anywhere) a venv may legitimately live.
- [`gpu.md`](gpu.md) — GPU coordination; CUDA-coupled Python workloads
  are the most common driver of exemption requests.
