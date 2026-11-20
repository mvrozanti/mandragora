#!/usr/bin/env bash
exec vicinae-pick "Light temperature" <<'ROWS'
sun	High	light High
moon	Low	light Low
swatch	Color	light Color
stars	Rainbow	light Rainbow
ROWS
