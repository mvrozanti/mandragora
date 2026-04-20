#!/usr/bin/env bash
sudo journalctl --vacuum-size=1G
sudo rm -rf /var/lib/systemd/coredump/core.*
trash-empty
docker system prune -a --volumes
pip cache purge
yarn cache clean
go clean -cache
cargo cache -a
conda clean -a -y
nix-collect-garbage -d
npm cache clean --force
rm -rf "$HOME/.gradle/caches"
rm -rf "$HOME/.cache/ueberzugpp"
rm -rf "$HOME/.config/discord/Cache"
