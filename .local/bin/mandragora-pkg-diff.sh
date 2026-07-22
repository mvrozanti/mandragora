#!/usr/bin/env bash
set -euo pipefail

# mandragora-pkg-diff — walk packages present in one host but not another
# and prompt one-by-one whether to add to the target's pkg list.
#
# Default direction: mandragora-desktop  ->  mandragora-wsl
#
# Decisions persist in $CACHE (add / skip lists). Re-running resumes.
# Use --refresh to invalidate the nix-eval cache.
# Use --all to drop the built-in "obviously not for WSL" filter.

FROM=${FROM:-mandragora-desktop}
TO=${TO:-mandragora-wsl}
FLAKE=${FLAKE:-/etc/nixos/mandragora}
REFRESH=0
SHOW_ALL=0

usage() {
  cat <<EOF
usage: mandragora-pkg-diff [--from HOST] [--to HOST] [--flake PATH]
                           [--refresh] [--all] [--reset] [-h]

Compare the pname sets of two nixosConfigurations and walk the
"present in FROM but not in TO" candidates interactively.

  --from HOST    source host (default: $FROM)
  --to   HOST    target host (default: $TO)
  --flake PATH   flake repo path (default: $FLAKE)
  --refresh      re-evaluate both hosts (otherwise cached)
  --all          show every candidate (skip the default filter)
  --reset        clear add/skip decisions for this FROM->TO pair
  -h, --help     this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM=$2; shift 2 ;;
    --to)   TO=$2;   shift 2 ;;
    --flake) FLAKE=$2; shift 2 ;;
    --refresh) REFRESH=1; shift ;;
    --all) SHOW_ALL=1; shift ;;
    --reset) RESET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mandragora-pkg-diff"
mkdir -p "$CACHE"
PAIR="${FROM}__to__${TO}"
ADD_LIST="$CACHE/${PAIR}.add"
SKIP_LIST="$CACHE/${PAIR}.skip"
FROM_TSV="$CACHE/${FROM}.tsv"
TO_TSV="$CACHE/${TO}.tsv"

if [ "${RESET:-0}" = 1 ]; then
  rm -f "$ADD_LIST" "$SKIP_LIST"
  echo "cleared decisions for $PAIR"
fi
touch "$ADD_LIST" "$SKIP_LIST"

dump_host() {
  local host=$1 out=$2
  if [ "$REFRESH" != 1 ] && [ -s "$out" ]; then return; fi
  echo "evaluating $host …" >&2
  nix eval --raw --impure --expr "
    let
      flake = builtins.getFlake (toString $FLAKE);
      cfg   = flake.nixosConfigurations.$host.config;
      sys   = cfg.environment.systemPackages;
      hm    = cfg.home-manager.users.m.home.packages or [];
      all   = sys ++ hm;
      line  = p:
        let
          pname = p.pname or (p.name or \"?\");
          desc  = p.meta.description or \"\";
        in pname + \"\t\" + desc;
    in builtins.concatStringsSep \"\n\" (map line all)
  " > "$out"
}

dump_host "$FROM" "$FROM_TSV"
dump_host "$TO"   "$TO_TSV"

cut -f1 "$FROM_TSV" | sort -u > "$CACHE/${FROM}.pnames"
cut -f1 "$TO_TSV"   | sort -u > "$CACHE/${TO}.pnames"

# Default skip patterns — things almost never useful inside WSL.
# Tuned for FROM=mandragora-desktop, TO=mandragora-wsl. Use --all to bypass.
SKIP_PATTERNS='^(
hyprland|hyprlock|hyprpicker|xdg-desktop-portal.*|xwayland|waybar|wlroots.*|
SwayNotificationCenter|swaync.*|mako|rofi.*|wofi|fuzzel|tofi|yad|zenity|
wl-clipboard|wl-copy|wl-paste|cliphist|wf-recorder|grim|slurp|wev|xev|
ydotool|wshowkeys.*|screenkey.*|showmethekey|wtype|
sddm|sddm-.*|kdeconnect.*|breeze-icons|adwaita-qt|qgnomeplatform.*|qtwayland|qt5.*|qt6.*|
gtk.*-immodule.*|hicolor-icon-theme|gtk3-immodule\.cache|nixos-icons|index\.theme|
materia-theme.*|matugen|bibata-cursors|shfthue|
pipewire|pulseaudio|wireplumber|jack-libs|pavucontrol|pamixer|playerctl|speech-dispatcher|
bluez|bluez-tools|blueman|brightnessctl|light|
openrgb.*|wal-to-rgb.*|keyledsd.*|keyleds-.*|keyd|
nvidia.*|cpupower|irqbalance|dmidecode|inxi|
firefox|chromium|ungoogled.*|vesktop|telegram-desktop|spotify|obsidian.*|obs-studio|
calibre|libreoffice|inkscape|gpick|gucharmap|kitty|alacritty|foot|
mpv-?.*|vlc|ffmpegthumbnailer|gifsicle|imagemagick|gpu-screen-recorder|
zathura.*|nemo|nsxiv|sqlitebrowser|baobab|gparted|gnome-chess|gnome-keyring|gnuplot|
remmina|virt-manager|virt-viewer|libvirt|qemu-host-cpu-only|spice-gtk|virtio-win|quickemu|quickgui|
syncthing|tailscale|rtkit|polkit.*|udisks|dconf|dbus.*|at-spi2-core|libnotify|fontconfig|
fcitx5.*|ibus|
mympd|mpd|ncmpcpp|mpc|cava|
ttyd|grafana|local-ai-mcp-server|nb-vault-sync|
seafile.*|seaf-onboard|sqlcipher|
steam|steam-run|retroarch.*|prismlauncher|openjdk|minecraft|ue5-launcher|idea-oss|
zapzap|droidcam|scrcpy|tradingview|impala|
strays|setbg|shfthue|pop|sit|smart-launch|safe-claude|spawn-claude-tmux|
mandragora-(audit|switch|diff|diff-last|winvm|commit-push)|
crush-wrapped|gemini-cli|gh-dash|
isync-xoauth2|msmtp|aerc|notmuch|khal|password-store|gnome-keyring|
nvtop|gpu-lock|recent-files-scrub|restore-theme|resize-window|record-window|
rofi-.*|rss-menu|security-menu|weather-menu|window-to-corner|scratchpad.*|screenshot-window|
opacity-adjust|gap-adjust|blur-adjust|blur-strength|center-window|biggest-pane|desktop-toggle|
clipboard-menu|cycle-audio-output|cycle-kbd-layouts|screencap|screenkey-toggle|capture|compv|
ic|gmp|mkv2gif|mov2gif|mp42gif|roman|lipsum|wiki|after|are-processes-related|
implode_tmux|explode_tmux|superscript|vaporscript|cursivescript|dict|sinon|
ait|axon|bonsai|eit|gemma|clean|filedropper|hid-wrapper|qit|sss|pentr|
keystats-.*|obsidian-.*|circleci-fetch|
texlive.*|texinfo.*|asciidoc|biber|typst|
ld-library-path|hm-session-vars\.sh|nixos-.*|home-configuration-.*|nixos-wsl.*|
)$'
SKIP_RE=$(printf '%s\n' "$SKIP_PATTERNS" | tr -d '\n ')

candidates_raw="$CACHE/${PAIR}.candidates"
comm -23 "$CACHE/${FROM}.pnames" "$CACHE/${TO}.pnames" > "$candidates_raw"

if [ "$SHOW_ALL" = 1 ]; then
  cp "$candidates_raw" "$candidates_raw.filtered"
else
  grep -Ev "$SKIP_RE" "$candidates_raw" > "$candidates_raw.filtered" || true
fi

# strip already-decided
grep -vxFf "$ADD_LIST"  "$candidates_raw.filtered" \
  | grep -vxFf "$SKIP_LIST" > "$candidates_raw.todo" || true

total_raw=$(wc -l < "$candidates_raw")
total_filtered=$(wc -l < "$candidates_raw.filtered")
total_todo=$(wc -l < "$candidates_raw.todo")
already_y=$(wc -l < "$ADD_LIST")
already_n=$(wc -l < "$SKIP_LIST")

cat <<EOF
$FROM -> $TO
  diff (raw):           $total_raw
  after default filter: $total_filtered    (--all to disable)
  already accepted:     $already_y         ($ADD_LIST)
  already skipped:      $already_n         ($SKIP_LIST)
  remaining to review:  $total_todo

keys: [y] add  [n] skip-once  [s] skip-forever  [b] back
      [d] describe more  [q] quit  [?] help

EOF

if [ "$total_todo" = 0 ]; then
  echo "nothing left to review. add list:"
  sed 's/^/  /' "$ADD_LIST" || true
  exit 0
fi

mapfile -t TODO < "$candidates_raw.todo"
i=0
N=${#TODO[@]}
declare -a HISTORY=()

describe() {
  local p=$1
  awk -F'\t' -v p="$p" '$1==p{print $2; found=1; exit} END{if(!found) print ""}' "$FROM_TSV"
}

while [ "$i" -lt "$N" ]; do
  p="${TODO[$i]}"
  desc=$(describe "$p")
  printf '[%d/%d] %-32s %s\n' "$((i+1))" "$N" "$p" "${desc:-(no description)}"
  printf '  add to %s? [y/n/s/b/d/q/?] ' "$TO"
  if ! read -r ans </dev/tty; then
    echo
    break
  fi
  case "$ans" in
    y|Y)
      echo "$p" >> "$ADD_LIST"
      HISTORY+=("$p:add")
      i=$((i+1))
      ;;
    n|N|"")
      HISTORY+=("$p:none")
      i=$((i+1))
      ;;
    s|S)
      echo "$p" >> "$SKIP_LIST"
      HISTORY+=("$p:skip")
      i=$((i+1))
      ;;
    b|B)
      if [ "$i" -gt 0 ]; then
        i=$((i-1))
        prev="${HISTORY[-1]}"
        unset 'HISTORY[-1]'
        case "$prev" in
          *:add)  sed -i "/^${prev%:*}$/d" "$ADD_LIST" ;;
          *:skip) sed -i "/^${prev%:*}$/d" "$SKIP_LIST" ;;
        esac
      else
        echo "  (already at first)"
      fi
      ;;
    d|D)
      nix eval --json --impure --expr "
        let f = builtins.getFlake (toString $FLAKE);
            c = f.nixosConfigurations.$FROM.config;
            ps = c.environment.systemPackages ++ (c.home-manager.users.m.home.packages or []);
            hit = builtins.head (builtins.filter (p: (p.pname or (p.name or \"\")) == \"$p\") ps);
        in {
          pname = hit.pname or hit.name or \"\";
          version = hit.version or \"\";
          description = hit.meta.description or \"\";
          homepage = hit.meta.homepage or \"\";
          platforms = hit.meta.platforms or [];
        }
      " 2>/dev/null | sed 's/^/    /' || echo "    (failed to describe)"
      ;;
    q|Q)
      break
      ;;
    \?)
      cat <<EOF
  y  add pname to $TO's pkg list (saved to $ADD_LIST)
  n  decline this round, ask again next run
  s  decline forever (saved to $SKIP_LIST)
  b  step back, undo previous decision
  d  show full meta (homepage, version, …) for this pname
  q  quit (decisions so far are preserved)
EOF
      ;;
    *)
      echo "  ? — y/n/s/b/d/q"
      ;;
  esac
done

echo
echo "--- summary ---"
echo "accepted ($(wc -l < "$ADD_LIST")):"
sed 's/^/  /' "$ADD_LIST" || true
echo
echo "next step: append these pnames to nix/modules/shared/home-cli.nix"
echo "(or to a host-specific module if they should not be on every host)"
