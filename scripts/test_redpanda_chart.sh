#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart_dir="$repo_root/charts/redpanda"
chart_version=26.2.1-aperiodic.3
package="$repo_root/redpanda-$chart_version.tgz"

grep -qx "version: $chart_version" "$chart_dir/Chart.yaml"
grep -q 'external.gateway.enabled' "$chart_dir/templates/_values.go.tpl"
grep -q 'kind" "TLSRoute' "$chart_dir/templates/_tlsroute.go.tpl"
grep -q 'list `/busybox/sh` `-c`' "$chart_dir/templates/_statefulset.go.tpl"
grep -q '(list "/busybox/sh" "-c"' "$chart_dir/templates/_statefulset.go.tpl"
if grep 'name" "redpanda-configurator"' "$chart_dir/templates/_statefulset.go.tpl" | grep -q '/bin/bash'; then
  echo "Redpanda containers must not require Bash; the configured image provides BusyBox sh" >&2
  exit 1
fi
if grep -q 'ADDRESSES+=\|PIPESTATUS' "$chart_dir/templates/_secrets.go.tpl" "$chart_dir/templates/_statefulset.go.tpl"; then
  echo "BusyBox-shell scripts must not use Bash arrays or PIPESTATUS" >&2
  exit 1
fi

helm lint "$chart_dir"

sha_values=$(mktemp)
trap 'rm -f "$sha_values"' EXIT
printf '%s\n' \
  'image:' \
  '  repository: ghcr.io/dream-faster/redpanda' \
  '  tag: fc46e9474ee11b7589bbb2a6fe0b80a87bbcce72' \
  'console:' \
  '  enabled: false' >"$sha_values"
helm template redpanda "$chart_dir" --namespace redpanda -f "$sha_values" >/dev/null

test -f "$package"
tar -xOf "$package" redpanda/Chart.yaml | cmp - "$chart_dir/Chart.yaml"
tar -xOf "$package" redpanda/templates/_helpers.go.tpl | cmp - "$chart_dir/templates/_helpers.go.tpl"
tar -xOf "$package" redpanda/templates/_statefulset.go.tpl | cmp - "$chart_dir/templates/_statefulset.go.tpl"

package_digest=$(sha256sum "$package" | awk '{print $1}')
grep -q "digest: $package_digest" "$repo_root/index.yaml"
grep -q "redpanda-$chart_version.tgz" "$repo_root/index.yaml"
