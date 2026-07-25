{ pkgs, ... }:
let
  port = 8096;
  workdir = "/var/lib/filebrowser";
  db = "${workdir}/filebrowser.db";
  fb = "${pkgs.filebrowser}/bin/filebrowser";

  seed = pkgs.writeShellScript "filebrowser-seed" ''
    set -eu
    if [ ! -f ${db} ]; then
      ${fb} config init -d ${db}
      ${fb} config set -d ${db} \
        --auth.method=noauth \
        --root / \
        --address 0.0.0.0 \
        --port ${toString port} \
        --branding.name share \
        --branding.disableExternal \
        --signup=false
      ${fb} users add admin "$(head -c 18 /dev/urandom | base64)" -d ${db}
      ${fb} users update 1 -d ${db} \
        --perm.admin=false --perm.create=false --perm.delete=false \
        --perm.modify=false --perm.rename=false --perm.execute=false \
        --perm.download=true --perm.share=true --scope /
    fi
  '';

  share = pkgs.writeShellScriptBin "share" ''
        set -eu
        if [ $# -lt 1 ]; then
          echo "usage: share <path> [expiry: 2d|3h|30m] [password]" >&2
          exit 2
        fi
        target=$(${pkgs.coreutils}/bin/realpath -e "$1")
        rel=$(${pkgs.python3}/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1].lstrip("/")))' "$target")
        tok=$(${pkgs.curl}/bin/curl -sf -X POST http://127.0.0.1:${toString port}/api/login)
        body=$(${pkgs.python3}/bin/python3 -c '
    import sys, json, re
    exp, pw = sys.argv[1], sys.argv[2]
    o = {}
    if exp:
        m = re.match(r"^(\d+)([dhm])$", exp)
        if not m:
            raise SystemExit("expiry must look like 2d / 3h / 30m")
        o["expires"] = m.group(1)
        o["unit"] = {"d": "days", "h": "hours", "m": "minutes"}[m.group(2)]
    if pw:
        o["password"] = pw
    print(json.dumps(o))
    ' "''${2:-}" "''${3:-}")
        hash=$(${pkgs.curl}/bin/curl -sf -X POST -H "X-Auth: $tok" \
          -H 'Content-Type: application/json' -d "$body" \
          "http://127.0.0.1:${toString port}/api/share/$rel" \
          | ${pkgs.python3}/bin/python3 -c 'import sys,json;print(json.load(sys.stdin)["hash"])')
        echo "https://files.mvr.ac/share/$hash"
  '';
in
{
  environment.systemPackages = [
    pkgs.filebrowser
    share
  ];

  systemd.tmpfiles.rules = [
    "d ${workdir} 0750 m users - -"
  ];

  mandragora.hub.services.filebrowser = {
    inherit port;
    systemd = {
      description = "filebrowser — on-demand public file/dir sharing (root=/, noauth, caddy-gated)";
      after = [
        "network.target"
        "tailscaled.service"
      ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "m";
        Group = "users";
        ExecStartPre = seed;
        ExecStart = "${fb} -d ${db}";
        Restart = "on-failure";
        RestartSec = "5s";
        NoNewPrivileges = true;
        ProtectHome = false;
        ProtectSystem = false;
        ReadWritePaths = [ workdir ];
      };
    };
  };
}
