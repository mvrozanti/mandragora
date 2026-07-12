{ pkgs, ... }:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
  desktopUrl = "http://${tailnet.desktop.ip}:9991";
  vpsHost = "opc@${tailnet.vps.ip}";
  vpsCacheDir = "/home/opc/gource/cache";
  prewarmScript = pkgs.writeShellScript "gource-prewarm.sh" ''
    set -euo pipefail
    headers=$(mktemp)
    payload=$(mktemp --suffix=.mp4)
    cleanup() { rm -f "$headers" "$payload"; }
    trap cleanup EXIT

    echo "→ requesting default-params render from desktop renderer"
    ${pkgs.curl}/bin/curl -fsS \
      --max-time 900 \
      -H 'Content-Type: application/json' \
      -D "$headers" \
      -o "$payload" \
      -X POST "${desktopUrl}/render-sync" \
      -d '{"length_s":60,"width":1024,"height":1024}'

    jid=$(${pkgs.gawk}/bin/awk 'BEGIN{IGNORECASE=1} /^x-job-id:/ {print $2}' "$headers" | tr -d "\r\n ")
    if [ -z "$jid" ]; then
      echo "ERR: no X-Job-Id header in response" >&2
      exit 1
    fi
    bytes=$(${pkgs.coreutils}/bin/stat -c %s "$payload")
    echo "→ got mp4: job=$jid size=$bytes bytes"

    echo "→ rsyncing to ${vpsHost}:${vpsCacheDir}/$jid.mp4"
    ${pkgs.rsync}/bin/rsync \
      -e "${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
      -t \
      "$payload" \
      "${vpsHost}:${vpsCacheDir}/$jid.mp4.part"
    ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
      "${vpsHost}" "mv -f ${vpsCacheDir}/$jid.mp4.part ${vpsCacheDir}/$jid.mp4"
    echo "→ done"
  '';
in
{
  systemd.services.gource-renderer-prewarm = {
    description = "Pre-render the default-params gource video and push it into the VPS cache.";
    after = [
      "gource-renderer.service"
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [
      "gource-renderer.service"
      "network-online.target"
      "tailscaled.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "m";
      Group = "users";
      WorkingDirectory = "/home/m";
      Environment = "HOME=/home/m";
      ExecStart = "${prewarmScript}";
    };
  };

  systemd.timers.gource-renderer-prewarm = {
    description = "Nightly pre-warm of the default-params gource MP4.";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };
}
