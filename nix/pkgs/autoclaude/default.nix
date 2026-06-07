{ lib, buildGoModule, fetchFromGitHub }:
buildGoModule {
  pname = "autoclaude";
  version = "unstable-2026-06-07";

  src = fetchFromGitHub {
    owner = "mvrozanti";
    repo = "autoclaude";
    rev = "ea9766cc35de2cf845b093d50710d17b8e8ed1d4";
    hash = "sha256-zpLKquxAESNpQuaQ7IiNVVcIGpB2PJbDX/2i06Xij4A=";
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
