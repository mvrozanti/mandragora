{
  writers,
  runCommand,
  symlinkJoin,
  python3,
}:

let
  bin = writers.writePython3Bin "tmux-dirpick" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./tmux-dirpick.py);

  tests = runCommand "tmux-dirpick-tests" {
    src = ./.;
    nativeBuildInputs = [ python3 ];
  } "python3 $src/test_tmux_dirsick.py && touch $out";
in
symlinkJoin {
  name = "tmux-dirpick";
  paths = [ bin ];
  postBuild = "test -e ${tests}";
  passthru = {
    inherit tests;
    unwrapped = bin;
  };
}
