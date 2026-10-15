{
  lib,
  runCommand,
  makeWrapper,
  jq,
  fzf,
  tmux,
  bash,
}:

runCommand "tmux-emoji"
  {
    nativeBuildInputs = [ makeWrapper ];
    script = ./tmux-emoji.sh;
    data = ./emoji.json;
  }
  ''
    mkdir -p $out/bin $out/share/tmux-emoji
    cp $data $out/share/tmux-emoji/emoji.json
    cp $script $out/bin/tmux-emoji
    chmod +x $out/bin/tmux-emoji
    patchShebangs $out/bin/tmux-emoji
    wrapProgram $out/bin/tmux-emoji \
      --set TMUX_EMOJI_DATA $out/share/tmux-emoji/emoji.json \
      --set TMUX_EMOJI_SELF $out/bin/tmux-emoji \
      --prefix PATH : ${
        lib.makeBinPath [
          jq
          fzf
          tmux
          bash
        ]
      }
  ''
