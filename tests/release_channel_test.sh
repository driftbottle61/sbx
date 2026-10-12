#!/usr/bin/env bash
set -Eeuo pipefail

releases='[
  {"tag_name":"openwrt-v0.3.0-r12","draft":false,"prerelease":false},
  {"tag_name":"v1.2.35","draft":false,"prerelease":false},
  {"tag_name":"v1.2.36","draft":false,"prerelease":false},
  {"tag_name":"v1.3.0-rc.1","draft":false,"prerelease":true},
  {"tag_name":"v1.2.37","draft":true,"prerelease":false}
]'

linux_latest=$(printf '%s\n' "$releases" \
  | jq -r '.[] | select(.draft == false and .prerelease == false) | .tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))' \
  | sort -V | tail -n1)
openwrt_latest=$(printf '%s\n' "$releases" \
  | jq -r '.[] | select(.draft == false and .prerelease == false) | .tag_name | select(test("^openwrt-v[0-9]+\\.[0-9]+\\.[0-9]+-r[0-9]+$"))' \
  | sed 's/^openwrt-v//' | sort -V | tail -n1)

test "$linux_latest" = "v1.2.36"
test "$openwrt_latest" = "0.3.0-r12"

echo "release channel test passed"
