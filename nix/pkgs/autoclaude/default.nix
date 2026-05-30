{ lib, buildGoModule, fetchFromGitHub }:
buildGoModule {
  pname = "autoclaude";
  version = "unstable-2026-05-30";

  src = fetchFromGitHub {
    owner = "mvrozanti";
    repo = "autoclaude";
    rev = "39ad5ef1818a9c71241bea463da3af33f1dccf69";
    hash = "sha256-+EEeijp1FfHK/ScpegdTaIYfaM9JM89NizvpGh2ezFM=";
  };

  vendorHash = "sha256-bq27PpkygOvE0HQpqWCbDRcNgYRP8pV+Q3RSNovCN58=";

  meta = {
    description = "TUI that monitors tmux panes running Claude Code and sends 'continue' when rate limits reset";
    homepage = "https://github.com/mvrozanti/autoclaude";
    license = lib.licenses.mit;
    mainProgram = "autoclaude";
    platforms = lib.platforms.unix;
  };
}
