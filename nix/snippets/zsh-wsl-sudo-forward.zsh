sudo() {
  if [[ $# -eq 2 && $1 == nixos-rebuild && $2 == switch ]]; then
    mandragora-wsl-switch
  else
    command sudo "$@"
  fi
}
