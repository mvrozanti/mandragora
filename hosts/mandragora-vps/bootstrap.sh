#!/usr/bin/env bash
# Provisions mandragora-vps on top of an existing Oracle Linux 8.10 host.
# Idempotent — safe to re-run.
#
# Run from mandragora-desktop:
#   ssh opc@oracle 'sudo bash -s' < hosts/mandragora-vps/bootstrap.sh
#
# Required env (passed via SSH or set on the host before running):
#   MANDRAGORA_TS_AUTHKEY  one-time Tailscale auth key (tskey-auth-…)
#   MANDRAGORA_REPO_URL    flake URL (default: github:mvrozanti/mandragora)
#   MANDRAGORA_HM_TARGET   home-manager attr (default: m@mandragora-vps)

set -euo pipefail

REPO_URL="${MANDRAGORA_REPO_URL:-github:mvrozanti/mandragora}"
HM_TARGET="${MANDRAGORA_HM_TARGET:-m@mandragora-vps}"

log() { printf '\n==> %s\n' "$*"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "must run as root (use sudo)" >&2
    exit 1
  fi
}

ensure_user_m() {
  log "ensuring user 'm' exists with sudo + opc-equivalent ssh access"
  if ! id -u m &>/dev/null; then
    useradd -m -s /bin/bash -G wheel m
    passwd -l m
  fi
  install -d -m 0700 -o m -g m /home/m/.ssh
  if [[ -f /home/opc/.ssh/authorized_keys ]]; then
    install -m 0600 -o m -g m /home/opc/.ssh/authorized_keys /home/m/.ssh/authorized_keys
  fi
  if ! grep -q '^%wheel ALL=(ALL) NOPASSWD: ALL$' /etc/sudoers.d/wheel-nopasswd 2>/dev/null; then
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel-nopasswd
    chmod 0440 /etc/sudoers.d/wheel-nopasswd
  fi
}

ensure_tailscale() {
  log "ensuring Tailscale repo + daemon"
  if ! command -v tailscale &>/dev/null; then
    dnf config-manager --add-repo https://pkgs.tailscale.com/stable/oracle/8/tailscale.repo
    dnf install -y tailscale
  fi
  systemctl enable --now tailscaled

  if ! tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
    if [[ -z "${MANDRAGORA_TS_AUTHKEY:-}" ]]; then
      echo "tailscaled is up but not authenticated, and MANDRAGORA_TS_AUTHKEY is not set." >&2
      echo "Re-run with: MANDRAGORA_TS_AUTHKEY=tskey-auth-… sudo -E bash bootstrap.sh" >&2
      exit 2
    fi
    tailscale up \
      --authkey="$MANDRAGORA_TS_AUTHKEY" \
      --hostname=mandragora-vps \
      --ssh \
      --accept-routes=false
  fi
}

ensure_nix() {
  log "ensuring Nix is installed (multi-user)"
  if ! command -v nix &>/dev/null && ! [[ -e /nix/var/nix/profiles/default/bin/nix ]]; then
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
      | sh -s -- install linux --no-confirm --init systemd
  fi

  if ! grep -q 'experimental-features' /etc/nix/nix.conf 2>/dev/null; then
    mkdir -p /etc/nix
    {
      echo 'experimental-features = nix-command flakes'
      echo 'trusted-users = root m'
    } >> /etc/nix/nix.conf
    systemctl restart nix-daemon
  fi
}

run_home_manager() {
  log "applying home-manager flake ${REPO_URL}#${HM_TARGET}"
  runuser -l m -c "
    set -euo pipefail
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    nix run --extra-experimental-features 'nix-command flakes' \
      home-manager/master -- switch \
      --flake '${REPO_URL}#${HM_TARGET}' -b backup
  "
}

main() {
  require_root
  ensure_user_m
  ensure_tailscale
  ensure_nix
  run_home_manager
  log "bootstrap complete — \`tailscale ip -4\` reports the new tailnet IP"
}

main "$@"
