{ config, lib, pkgs, ... }:

{
  home.file.".XCompose".source = ../../../.XCompose;
  home.file.".config/nvim" = {
    source = ../../../.config/nvim;
    recursive = true;
  };
  home.file.".config/ncmpcpp" = {
    source = ../../../.config/ncmpcpp;
    recursive = true;
  };
  home.file.".config/zathura" = {
    source = ../../../.config/zathura;
    recursive = true;
  };
  home.file.".config/mpv" = {
    source = ../../../.config/mpv;
    recursive = true;
  };
  home.file.".config/rofi" = {
    source = ../../../.config/rofi;
    recursive = true;
  };
  home.file.".config/tridactyl" = {
    source = ../../../.config/tridactyl;
    recursive = true;
  };
  home.file.".config/matugen" = {
    source = ../../../.config/matugen;
    recursive = true;
  };
  home.file.".local/share/TelegramDesktop/matugen.tdesktop-palette".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.cache/matugen/telegram.tdesktop-palette";

  home.activation.seedKeyledsd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.config/keyledsd.conf" ]; then
      install -Dm644 ${../../../.config/keyledsd/keyledsd.conf} "$HOME/.config/keyledsd.conf"
    fi
  '';

  home.activation.seedMonitorsConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    MON_CONF="$HOME/.config/hypr/monitors.conf"
    if [ ! -e "$MON_CONF" ]; then
      mkdir -p "$(dirname "$MON_CONF")"
      : > "$MON_CONF"
    fi
  '';

  home.activation.seedObsStudio = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    OBS_PROFILE_DIR="$HOME/.config/obs-studio/basic/profiles/Untitled"
    if [ ! -e "$OBS_PROFILE_DIR/basic.ini" ]; then
      mkdir -p "$OBS_PROFILE_DIR"
      cat <<EOF > "$OBS_PROFILE_DIR/basic.ini"
[General]
Name=Untitled

[SimpleOutput]
FilePath=$HOME/Videos

[AdvOut]
RecFilePath=$HOME/Videos
EOF
    fi
  '';

  home.file.".config/nsxiv" = {
    source = ../../../.config/nsxiv;
    recursive = true;
  };
  home.file.".config/cava/config".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.cache/matugen/cava";
  home.file.".config/khal" = {
    source = ../../../.config/khal;
    recursive = true;
  };
  home.file.".config/aerc" = {
    source = ../../../.config/aerc;
    recursive = true;
  };
  home.file.".mbsyncrc".source = ../../../.mbsyncrc;
  home.file.".config/notmuch/default/config".source = ../../../.config/notmuch/default/config;
  home.activation.notmuchInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.local/share/mail/.notmuch" ]; then
      ${pkgs.notmuch}/bin/notmuch new || true
    fi
  '';
  home.file.".config/crush/crush.json".source = ../../../.config/crush/crush.json;
  home.file.".config/flameshot" = {
    source = ../../../.config/flameshot;
    recursive = true;
  };
  home.file.".config/waybar/scripts/mpd-status.sh" = {
    source = ../../snippets/waybar-mpd.sh;
    executable = true;
  };
  home.file.".config/waybar/scripts/mpd-controls.sh" = {
    source = ../../snippets/waybar-mpd-controls.sh;
    executable = true;
  };
  home.file.".config/waybar/scripts/volume-ramp.sh" = {
    source = ../../snippets/waybar-volume-ramp.sh;
    executable = true;
  };
  home.file.".config/waybar/scripts/weather.sh" = {
    source = ../../snippets/waybar-weather.sh;
    executable = true;
  };
  home.file.".config/waybar/scripts/bluetooth.sh" = {
    source = ../../snippets/waybar-bluetooth.sh;
    executable = true;
  };
  home.file.".config/waybar/scripts/brightness.sh" = {
    source = ../../snippets/waybar-brightness.sh;
    executable = true;
  };
  home.file.".local/share/applications/chess-com.desktop".source = pkgs.replaceVars ../../../.local/share/applications/chess-com.desktop {
    icon = "${pkgs.gnome-chess}/share/icons/hicolor/scalable/apps/org.gnome.Chess.svg";
  };
  home.file.".local/share/applications/whatsapp-web.desktop".source = pkgs.replaceVars ../../../.local/share/applications/whatsapp-web.desktop {
    icon = "${pkgs.zapzap}/share/icons/hicolor/scalable/apps/com.rtosta.zapzap.svg";
  };
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/settings.json";
  home.file.".claude/settings.local.json".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/settings.local.json";

  home.file.".gemini/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.gemini/settings.json";
  home.file.".gemini/GEMINI.md".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/GEMINI.md";
  home.file.".gemini/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/AGENTS.md";
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "/home/m/.ai-shared/AGENTS.md";
  home.file.".qwen/QWEN.md".source =
    config.lib.file.mkOutOfStoreSymlink "/home/m/.ai-shared/AGENTS.md";

  home.activation.aiSharedDocs = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    repo=/etc/nixos/mandragora
    $DRY_RUN_CMD install $VERBOSE_ARG -Dm644 "$repo/AGENTS.md"         "$HOME/.ai-shared/AGENTS.md"
    $DRY_RUN_CMD install $VERBOSE_ARG -Dm644 "$repo/CLAUDE.md"         "$HOME/.ai-shared/CLAUDE.md"
    $DRY_RUN_CMD install $VERBOSE_ARG -Dm644 "$repo/GEMINI.md"         "$HOME/.ai-shared/GEMINI.md"
    $DRY_RUN_CMD install $VERBOSE_ARG -Dm644 "$repo/docs/local-llm.md" "$HOME/.ai-shared/local-llm.md"
    $DRY_RUN_CMD install $VERBOSE_ARG -Dm644 "$repo/RTK.md"            "$HOME/.ai-shared/RTK.md"
    $DRY_RUN_CMD rm -rf "$HOME/.ai-shared/rules"
    $DRY_RUN_CMD cp -r "$repo/.ai-shared/rules" "$HOME/.ai-shared/rules"
    $DRY_RUN_CMD chmod -R u+w "$HOME/.ai-shared/rules"
    $DRY_RUN_CMD mkdir -p "$HOME/.ai-shared/templates"
    $DRY_RUN_CMD rm -f "$HOME/.claude/CLAUDE.md" "$HOME/.qwen/QWEN.md" "$HOME/.claude/RTK.md"
  '';
  home.file.".claude/hooks/rtk-rewrite.sh".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/hooks/rtk-rewrite.sh";
  home.file.".gemini/hooks/rtk-hook-gemini.sh".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.gemini/hooks/rtk-hook-gemini.sh";
  home.file.".gemini/hooks/.rtk-hook.sha256".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.gemini/hooks/.rtk-hook.sha256";
  home.file.".local/share/applications/ragnarok.desktop".source = ../../../.local/share/applications/ragnarok.desktop;
}
