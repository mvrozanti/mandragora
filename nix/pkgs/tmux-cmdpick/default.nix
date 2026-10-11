{
  writers,
  runCommand,
  symlinkJoin,
  python3,
  zsh,
  tmux,
  fzf,
  coreutils,
  bash,
  ncurses,
}:

let
  bin = writers.writePython3Bin "tmux-cmdpick" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./tmux-cmdpick.py);

  tests = runCommand "tmux-cmdpick-tests" {
    src = ./.;
    nativeBuildInputs = [
      python3
      zsh
      tmux
      fzf
      coreutils
      bash
    ];
    TMUX_CMDPICK_BIN = "${bin}/bin/tmux-cmdpick";
    TERMINFO_DIRS = "${ncurses}/share/terminfo";
  } "python3 $src/test_tmux_cmdpick.py && touch $out";
in
symlinkJoin {
  name = "tmux-cmdpick";
  paths = [ bin ];
  postBuild = "test -e ${tests}";
  passthru = {
    inherit tests;
    unwrapped = bin;
  };
}
