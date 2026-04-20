state=$(hyprctl activewindow -j | jq -r .floating)
if [ "$state" = "false" ]; then
  hyprctl dispatch togglefloating
  hyprctl dispatch resizeactive exact 1400 800
  hyprctl dispatch centerwindow
else
  hyprctl dispatch togglefloating
fi
