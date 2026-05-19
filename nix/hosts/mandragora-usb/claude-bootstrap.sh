set -eu
mkdir -p /persist/npm-global
marker=/persist/npm-global/.bootstrap-done
if [ -f "$marker" ]; then
  echo "[claude-bootstrap] marker present, all packages already installed"
  exit 0
fi
failed=
for pkg in @anthropic-ai/claude-code @google/gemini-cli @qwen-code/qwen-code; do
  if npm install -g "$pkg"; then
    echo "[claude-bootstrap] installed $pkg"
  else
    echo "[claude-bootstrap] $pkg install failed; will retry next boot"
    failed=1
  fi
done
if [ -z "$failed" ]; then
  touch "$marker"
fi
