#!/usr/bin/env bash
set -euo pipefail

STATIC_DIR="${VULN_STATIC_DIR:-/home/opc/vuln/static}"
HOST="mandragora-vps"
IMAGE="${TRIVY_IMAGE:-aquasec/trivy:latest}"
CACHE_VOL="${TRIVY_CACHE_VOL:-trivy-cache}"

trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${CACHE_VOL}:/root/.cache" \
    "$IMAGE" "$@"
}

PER_IMAGE='
[ .Results[]? as $r | $r.Vulnerabilities[]? | . + {Ecosystem: ($r.Type // "")} ]
| group_by(.PkgName + " " + (.InstalledVersion // "") + " " + .Ecosystem)
| map({
    pname: .[0].PkgName,
    version: (.[0].InstalledVersion // ""),
    ecosystem: .[0].Ecosystem,
    images: [ $img ],
    cves: ( [ .[] | {
      id: .VulnerabilityID,
      score: ((.CVSS.nvd.V3Score // .CVSS.redhat.V3Score) // 0),
      severity: ((.Severity // "UNKNOWN") | ascii_downcase),
      desc: (.Title // .Description // ""),
      fixed: ((.FixedVersion // "") != ""),
      fixed_version: (.FixedVersion // "")
    } ] | unique_by(.id) ),
    max: ( [ .[] | ((.CVSS.nvd.V3Score // .CVSS.redhat.V3Score) // 0) ] | max // 0 )
  })
'

MERGE='
add
| group_by(.pname + " " + .version + " " + .ecosystem)
| map({
    pname: .[0].pname,
    version: .[0].version,
    ecosystem: .[0].ecosystem,
    images: ( map(.images[]) | unique ),
    cves: ( map(.cves[]) | unique_by(.id) ),
    max: ( map(.max) | max // 0 )
  })
'

EXPOSURE='
map(
  . as $c
  | ( [ ($c.ports // {}) | to_entries[] | select(.value != null) | .value[]
        | select(.HostIp == "0.0.0.0" or .HostIp == "::" or .HostIp == "")
        | {port: (.HostPort | tonumber), scope: "public"} ] )
    + ( [ $c.labels | to_entries[] | select(.key | test("^caddy(_[0-9]+)?$")) | .value ]
        | if length == 0 then []
          else [ {port: 443, vhost: join(" "),
                  scope: (if ($c.labels | keys | any(test("forward_auth"))) then "authed" else "public" end)} ]
          end )
  | map(. + {proto: "tcp", process: $c.name, image: $c.image})
)
| add // [] | unique
'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ refreshing trivy vulnerability DB"
trivy image --download-db-only --quiet 2>/dev/null || true

mapfile -t IMAGES < <(docker ps --format '{{.Image}}' | sort -u)
echo "→ scanning ${#IMAGES[@]} running image(s)"

idx=0
failed=0
for img in "${IMAGES[@]}"; do
  out="${TMP}/img-${idx}.json"
  idx=$((idx + 1))
  if trivy image --quiet --format json --scanners vuln --skip-db-update "$img" 2>/dev/null > "${TMP}/raw.json"; then
    jq --arg img "$img" "$PER_IMAGE" "${TMP}/raw.json" > "$out" 2>/dev/null || echo '[]' > "$out"
  else
    echo "  ! scan failed: $img" >&2
    failed=$((failed + 1))
    echo '[]' > "$out"
  fi
done

ERROR=""
if [[ ${#IMAGES[@]} -gt 0 && $failed -eq ${#IMAGES[@]} ]]; then
  ERROR="trivy failed on all ${failed} image(s)"
fi

GENERATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$STATIC_DIR"
REPORT="${STATIC_DIR}/report-${HOST}.json"

if [[ -n "$ERROR" && -s "$REPORT" ]]; then
  jq --arg err "$ERROR" '. + {error: $err}' "$REPORT" > "${TMP}/stale.json"
  cp "${TMP}/stale.json" "$REPORT"
  echo "  ! ${ERROR}; kept previous entries, flagged report" >&2
else
  jq -s "$MERGE" "${TMP}"/img-*.json \
    | jq --arg gen "$GENERATED" --arg host "$HOST" \
        '{schema: 2, scanner: "trivy", generated: $gen, host: $host, entries: .}' \
    > "${TMP}/report.json"
  cp "${TMP}/report.json" "$REPORT"
fi

COUNT="$(jq '.entries | length' "$REPORT")"
echo "→ wrote ${COUNT} package entries to ${REPORT}"

docker ps --format '{{.Names}}' | while read -r name; do
  docker inspect "$name" | jq -c --arg name "$name" \
    '.[0] | {name: $name, image: .Config.Image, labels: (.Config.Labels // {}), ports: .NetworkSettings.Ports}'
done | jq -s "$EXPOSURE" \
  | jq --arg gen "$GENERATED" --arg host "$HOST" '{schema: 1, host: $host, generated: $gen, listeners: .}' \
  > "${TMP}/exposure.json"
cp "${TMP}/exposure.json" "${STATIC_DIR}/exposure-${HOST}.json"
echo "→ exposure: $(jq '.listeners | length' "${STATIC_DIR}/exposure-${HOST}.json") listener(s)"

cd "$STATIC_DIR"
printf '[%s]\n' "$(find . -maxdepth 1 -name 'report-*.json' -printf '%f\n' | sort | sed -E 's/^report-(.*)\.json$/"\1"/' | paste -sd, -)" > hosts.json
echo "→ manifest: $(cat hosts.json)"
