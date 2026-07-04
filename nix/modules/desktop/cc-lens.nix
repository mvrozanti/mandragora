{ lib, pkgs, ... }:

let
  repo = "/home/m/Projects/cc-lens";
  upstream = "https://github.com/Arindam200/cc-lens";
  rev = "745115fce61872c3e985dc496f357b3893d910da";
  nodejs = pkgs.nodejs_22;
  port = 7683;

  launcher = pkgs.writeShellScript "cc-lens-launch" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ nodejs pkgs.git pkgs.coreutils pkgs.bash ]}:$PATH"

    repo=${repo}
    rev=${rev}

    if [ ! -d "$repo/.git" ]; then
      git clone ${upstream} "$repo"
    fi
    cd "$repo"

    if [ "$(git rev-parse HEAD)" != "$rev" ]; then
      git fetch origin
      git checkout --force "$rev"
      rm -rf .next node_modules
    fi

    if [ ! -f "$repo/.next/standalone/server.js" ]; then
      npm ci --include=dev
      npm run build:dist
    fi

    exec node "$repo/.next/standalone/server.js"
  '';
in
{
  systemd.user.services.cc-lens = {
    description = "cc-lens — lens.mvr.ac · local analytics dashboard for Claude Code (~/.claude)";
    wantedBy = [ "default.target" ];
    path = [ nodejs pkgs.git pkgs.coreutils pkgs.bash ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${launcher}";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "20min";
      Environment = [
        "NODE_ENV=production"
        "CLAUDE_CONFIG_DIR=/home/m/.claude"
        "HOSTNAME=0.0.0.0"
        "PORT=${toString port}"
      ];
    };
    unitConfig.ConditionPathExists = "/home/m/.claude";
  };
}
