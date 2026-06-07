{ lib, buildGoModule, fetchFromGitHub }:
buildGoModule {
  pname = "autoclaude";
  version = "unstable-2026-06-07";

  src = fetchFromGitHub {
    owner = "mvrozanti";
    repo = "autoclaude";
    rev = "1be2312900c77f15ee4788574828615d614e0d89";
    hash = "sha256-snyY1ZiPpG5sAR7cikhGdljAt9tVC9tzNUVmrtC1bJE=";
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
