{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
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
      # Basic
      zh = "~";
      zD = "~/Downloads";
      zc = "~/.config";
      zl = "~/.config/lf";
      zt = "~/.local/share/Trash";
      zp = "~/projects";
      zu = "~/util";
      
      # System
      switch = "mandragora-switch";
      rebuild = "mandragora-switch";
      ll = "ls -lah";
      la = "ls -A";
      nix-shell = "nix shell nixpkgs#";
      
      # Python
      py = "python3";
      
      # Git (from old gac/gacp scripts maybe, but basic aliases for now)
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
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

    initExtra = builtins.readFile ../../.config/zsh/zshrc.zsh;

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };
  
  home.file.".p10k.zsh".source = ../../.config/zsh/p10k.zsh;
}
