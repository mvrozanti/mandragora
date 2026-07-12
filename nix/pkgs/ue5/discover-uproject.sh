if [ -z "${UPROJECT:-}" ]; then
  shopt -s nullglob
  candidates=("${PROJECT_ROOT:?PROJECT_ROOT not set}"/*.uproject)
  shopt -u nullglob
  if [ ${#candidates[@]} -eq 0 ]; then
    echo "error: no *.uproject in $PROJECT_ROOT (set UPROJECT to override)" >&2
    exit 1
  fi
  UPROJECT="${candidates[0]}"
fi
