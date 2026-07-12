if [ -z "${UE_TARGET:-}" ]; then
  base="$(basename "$UPROJECT" .uproject)"
  UE_TARGET="${base}Editor"
fi
