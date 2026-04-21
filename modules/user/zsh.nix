{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    defaultKeymap = "emacs";
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    history = {
      size = 50000;
      save = 50000;
      path = "${config.home.homeDirectory}/.local/state/zsh/history";
      ignoreDups = true;
      share = true;
    };

    shellAliases = {
      zh = "~";
      zD = "~/Downloads";
      zc = "~/.config";
      zl = "~/.config/lf";
      zt = "~/.local/share/Trash";
      zp = "~/projects";
      zu = "~/util";
      zG = "~/gdrive";
      z4 = "~/gdrive/Levv/4chan";
      zw = "~/gdrive/Levv/wllpps";
      zL = "~/gdrive/library";
      zM = "~/Music";
      zf = "~/sandisk/Filmes";
      zm = "~/macrovip";
      zs = "~/sandisk/sss";
      za = "~/adata";
      zd = "~/disk";
      zS = "~/sandisk";

      switch = "mandragora-switch";
      rebuild = "mandragora-switch";
      rebuild-boot = "sudo nixos-rebuild boot --flake /etc/nixos/mandragora#mandragora-desktop";
      nix-shell = "nix shell nixpkgs#";

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

    initExtra = builtins.readFile ../../.config/zsh/zshrc.zsh + "\n" + builtins.readFile ../../snippets/aliases.zsh;

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
