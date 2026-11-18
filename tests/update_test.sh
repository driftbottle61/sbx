#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/sbx-update-test.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT

source "$project_dir/lib/common.sh"
source "$project_dir/lib/install.sh"

sbx_curl() {
    printf '[{"name":"v1.2.50"},{"name":"v1.2.51-alpha.1"},{"name":"v1.2.49"}]'
}
test "$(get_latest_sbx_version)" = "v1.2.50"

SBX_VERSION="1.2.49"
DASH_SBX_LATEST=""
unset SBX_LATEST_VERSION 2>/dev/null || true
DASH_CACHE_DIR="$test_root/cache"
mkdir -p "$DASH_CACHE_DIR"
printf 'singbox=v1.14.4\nsbx=v1.2.49\nepoch=0\n' > "$DASH_CACHE_DIR/version-cache"
sbx_curl() { return 22; }

output="$(printf 'n\n' | update_sbx 2>&1)"
grep -q 'SBX 已是最新版本：v1.2.49' <<<"$output"
! grep -q '无法获取 SBX 最新版本' <<<"$output"

echo "update test passed"
