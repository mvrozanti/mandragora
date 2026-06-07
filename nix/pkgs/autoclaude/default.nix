{ lib, buildGoModule, fetchFromGitHub }:
buildGoModule {
  pname = "autoclaude";
  version = "unstable-2026-06-07";

  src = fetchFromGitHub {
    owner = "mvrozanti";
    repo = "autoclaude";
    rev = "5943760266916f3372f5bf96259999ce3d5579a3";
    hash = "sha256-WsUdHqeT0y7BvkJS2lJI7cSycpkRItbtzxivcoFvaUU=";
  };

  vendorHash = "sha256-bq27PpkygOvE0HQpqWCbDRcNgYRP8pV+Q3RSNovCN58=";

  meta = {
    description = "Headless watcher (or TUI) that monitors tmux panes for Claude Code rate-limit pickers, selects 'Stop and wait', and sends 'continue' when the limit resets";
    homepage = "https://github.com/mvrozanti/autoclaude";
    license = lib.licenses.mit;
    mainProgram = "autoclaude";
    platforms = lib.platforms.unix;
  };
}
