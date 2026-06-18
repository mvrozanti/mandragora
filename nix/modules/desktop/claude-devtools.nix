{ config, lib, pkgs, ... }:

let
  repo = "/home/m/Projects/claude-devtools";
  upstream = "https://github.com/matt1398/claude-devtools";
  rev = "16cc3c87c1e4d0e08ee101fb52dad1b85dbbe48a";
  nodejs = pkgs.nodejs_20;
  pnpm = pkgs.pnpm_10;

  launcher = pkgs.writeShellScript "claude-devtools-launch" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ nodejs pnpm pkgs.git pkgs.coreutils ]}:$PATH"

    repo=${repo}
    rev=${rev}

    if [ ! -d "$repo/.git" ]; then
      git clone ${upstream} "$repo"
    fi
    cd "$repo"

    if [ "$(git rev-parse HEAD)" != "$rev" ]; then
      git fetch origin
      git checkout --force "$rev"
      rm -rf dist-standalone out node_modules
    fi

    if [ ! -f "$repo/dist-standalone/index.cjs" ]; then
      pnpm install --frozen-lockfile
      pnpm standalone:build
    fi

    exec node "$repo/dist-standalone/index.cjs"
  '';
in
{
  systemd.user.services.claude-devtools = {
    description = "claude-devtools — local web viewer for Claude Code sessions (127.0.0.1:3456)";
    wantedBy = [ "default.target" ];
    path = [ nodejs pnpm pkgs.git pkgs.coreutils ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${launcher}";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "20min";
      Environment = [
        "NODE_ENV=production"
        "CLAUDE_ROOT=/home/m/.claude"
        "HOST=127.0.0.1"
        "PORT=3456"
      ];
    };
    unitConfig.ConditionPathExists = "/home/m/.claude";
  };
}
