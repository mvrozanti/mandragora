{ config, pkgs, lib, ... }:

let
  # zX directory shortcuts: edit ./zx-dirs.nix — it's the single source
  # of truth shared with modules/user/lf.nix. Do not add z<letter> aliases here.
  zxDirs = import ./zx-dirs.nix;
  normalize = v: if builtins.isString v then { path = v; zshPrefix = "z"; } else { zshPrefix = "z"; } // v;
  zxAliases = lib.mapAttrs' (k: v:
    let e = normalize v; in lib.nameValuePair "${e.zshPrefix}${k}" e.path
  ) zxDirs;
in
{
  programs.zsh = {
    enable = true;
    defaultKeymap = "emacs";
    completionInit = "autoload -U compinit && compinit -u";
    autosuggestion = {
      enable = true;
      highlight = "fg=12";
    };
    syntaxHighlighting.enable = true;

    history = {
      size = 1000000;
      save = 1000000;
      path = "${config.home.homeDirectory}/.local/state/zsh/history";
      ignoreDups = true;
      share = true;
      extended = true;
    };

    shellAliases = zxAliases // {
      nrd = "mandragora-diff";
      nrdd = "mandragora-diff-last";
      nrs = "mandragora-switch !";
      nrc = "mandragora-switch";
      nrp = "mandragora-commit-push";
      nrb = "sudo nixos-rebuild boot --flake /etc/nixos/mandragora#mandragora-desktop";
      nrt = "sudo nixos-rebuild test --flake /etc/nixos/mandragora#mandragora-desktop";
      cava = "cava -p ~/.cache/matugen/cava";
      nix-shell = "nix shell nixpkgs#";
      droidcam-mic = "pacmd load-module module-alsa-source device=hw:Loopback,1,0";
      droidcam-cam = "mpv av://v4l2:/dev/video10";

      vim = "nvim";
      cat = "bat";
      ls = "eza --git --icons";
      l = "eza -t1";
      ll = "eza -la --git --icons";
      la = "eza -a";
      tree = "eza --tree";
      grep = "grep --color=auto";
      df = "df -h";
      du = "du -h";

      h = "cd ..";
      hh = "cd ../..";
      "cd.." = "cd ..";

      s = "sudo";
      smv = "sudo mv";
      srm = "sudo rm";
      schmod = "sudo chmod";
      sf = "sudo find / -iname";

      u = "unp -U";
      mkdir = "mkdir -p";
      serve = "python3 -m http.server 2717";
      watch = "watch --color -n1 --no-title";
      ka = "killall -I";
      e = "echo";
      g = "grep -i";
      T = "date +%s";
      t = "trans -b";
      cot = "co | translate";
      rsync = "rsync -a --info=progress2";
      lisp = "clisp --silent";
      ta = "task add";
      asciimap = "telnet mapscii.me";
      weather = "curl -s wttr.in | head -n -1";
      W = "curl -s v2.wttr.in | head -n -1";
      py = "python3";

      gs = "git status";
      ga = "git add";
      gc = "git clone";
      gcm = "git commit";
      gp = "git push";
      gd = "git diff";
      gl = "git log --oneline";
      gco = "git checkout";
      gb = "git branch";
      gfd = "git fetch origin && git diff master";
      gmc = "git merge --continue";
    };

    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      BROWSER = "firefox";
      SYSTEMD_EDITOR = "nvim";
      MANPAGER = "nvim +Man!";
      PYTHONSTARTUP = "$HOME/.pythonrc";
      SSH_KEY_PATH = "$HOME/.ssh/rsa_id";
    };

    initContent = builtins.readFile ../../.config/zsh/zshrc.zsh + "\n" + builtins.readFile ../../snippets/aliases.zsh;

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };
  
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  home.file.".p10k.zsh".source = ../../.config/zsh/p10k.zsh;
}
