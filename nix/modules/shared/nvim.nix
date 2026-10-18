{ pkgs, ... }:

let
  sopsEditor = pkgs.writeShellScriptBin "sops-editor" ''
    exec nvim -u NONE -c "source $HOME/.config/nvim/map.vim" "$@"
  '';
in
{
  environment.systemPackages = with pkgs; [
    neovim
    sopsEditor
  ];
  environment.variables.EDITOR = "nvim";
  environment.variables.SOPS_EDITOR = "sops-editor";
}
