# shellcheck shell=bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-demo-deployed}"

DEMO_STATIC="$MANDRAGORA_REPO/nix/hosts/mandragora-vps/compose/demo/static"
VPS="${MANDRAGORA_VPS_SSH:-opc@100.84.78.83}"
REMOTE_DIR=/home/opc/demo/static

if [ ! -d "$DEMO_STATIC" ]; then
  audit_pass "$CHECK" "demo static dir missing; skipped"
  exit 0
fi

page_files() {
  find . -type f ! -path './vault/*' ! -path './vault-graph/*' ! -name graph.json ! -name .gitkeep \
    -exec md5sum {} + | sort -k2
}

repo=$(cd "$DEMO_STATIC" && page_files)
live=$(timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=8 "$VPS" \
  "cd $REMOTE_DIR && $(declare -f page_files) && page_files" 2>/dev/null)

if [ -z "$live" ]; then
  audit_yellow "    demo.mvr.ac unreachable ($VPS); deployed page not compared" >&2
  echo >&2
  audit_pass "$CHECK" "skipped (VPS unreachable)"
  exit 0
fi

drift=$(diff <(printf '%s\n' "$repo") <(printf '%s\n' "$live") | grep -E '^[<>]' | awk '{print $1, $3}' | sort -u -k2)

if [ -z "$drift" ]; then
  audit_pass "$CHECK" "demo.mvr.ac serves exactly compose/demo/static"
  exit 0
fi

audit_fail "$CHECK" "demo.mvr.ac page files differ from compose/demo/static (< repo, > live):"
printf '%s\n' "$drift" | sed 's/^/    /' >&2
echo "    compose/demo/deploy.sh is the only writer of these paths; publish-vault.sh writes vault/ and graph.json only." >&2
echo "    Deploy the repo copy: $DEMO_STATIC/../deploy.sh" >&2
exit 1
