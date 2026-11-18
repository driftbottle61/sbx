#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
project_version="$(sed -n 's/^SBX_VERSION="\([^"]*\)"/\1/p' "$project_dir/data/sbx.conf")"
test_root="$(mktemp -d /tmp/sbx-dashboard-test.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/cache"

cat > "$test_root/bin/hostname" <<'STUB'
#!/bin/sh
case "$1" in
    -I) echo "192.168.100.18" ;;
    *)  echo "sbx18" ;;
esac
STUB

cat > "$test_root/bin/uname" <<'STUB'
#!/bin/sh
case "$1" in
    -r) echo "7.0.14-test" ;;
    -s) echo "Linux" ;;
    *)  echo "Linux" ;;
esac
STUB

cat > "$test_root/bin/lscpu" <<'STUB'
#!/bin/sh
echo "Model name:          Intel(R) Core(TM) i5-1235U"
STUB

cat > "$test_root/bin/nproc" <<'STUB'
#!/bin/sh
echo 2
STUB

cat > "$test_root/bin/free" <<'STUB'
#!/bin/sh
printf '              total        used        free\n'
printf 'Mem:           1.0Gi        80Mi       900Mi\n'
printf 'Swap:          0B          0B          0B\n'
STUB

cat > "$test_root/bin/uptime" <<'STUB'
#!/bin/sh
case "$1" in
    -p) echo "up 1 week, 2 days, 3 hours" ;;
    *)  echo " 01:00:00 up 9 days, 3:00, 1 user, load average: 0.00, 0.00, 0.00" ;;
esac
STUB

cat > "$test_root/bin/systemd-detect-virt" <<'STUB'
#!/bin/sh
echo lxc
STUB

cat > "$test_root/bin/systemctl" <<'STUB'
#!/bin/sh
case "$1" in
    is-active|is-enabled) exit 0 ;;
    *) exit 0 ;;
esac
STUB

cat > "$test_root/bin/ping" <<'STUB'
#!/bin/sh
exit 0
STUB

cat > "$test_root/bin/ss" <<'STUB'
#!/bin/sh
echo "LISTEN 0 4096 127.0.0.1:9095 0.0.0.0:*"
STUB

cat > "$test_root/bin/pgrep" <<'STUB'
#!/bin/sh
echo 4242
STUB

cat > "$test_root/bin/ps" <<'STUB'
#!/bin/sh
case "$*" in
    *"-o rss="*) echo 63488 ;;
    *"-o pid="*) echo 4242 ;;
    *) exit 0 ;;
esac
STUB

cat > "$test_root/bin/sysctl" <<'STUB'
#!/bin/sh
echo 1
STUB

cat > "$test_root/bin/getconf" <<'STUB'
#!/bin/sh
echo 100
STUB

cat > "$test_root/bin/curl" <<'STUB'
#!/bin/sh
echo 000
exit 1
STUB

cat > "$test_root/bin/sing-box" <<'STUB'
#!/bin/sh
echo "sing-box version 1.14.4"
STUB

chmod +x "$test_root/bin/"*

export PATH="$test_root/bin:$PATH"
export COLUMNS=100
export SBX_DASHBOARD_COLOR=never
export SBX_DASHBOARD_NO_BG=1
export SBX_DASHBOARD_CACHE_DIR="$test_root/cache"
export SINGBOX_BIN="$test_root/bin/sing-box"
export SERVICE_NAME="sing-box"
export ROUTE_MODE="tproxy"
export SBX_VERSION="$project_version"
export CONFIG_FILE="$test_root/config.json"
export CONFIG_URL="https://example.invalid/sub"
export SBX_ZASHBOARD_INDEX="$test_root/zashboard.html"

printf '{}\n' > "$CONFIG_FILE"
printf '<!doctype html>\n' > "$SBX_ZASHBOARD_INDEX"
printf 'singbox=v1.14.4\nsbx=v%s\nepoch=%s\n' "$project_version" "$(date +%s)" > "$test_root/cache/version-cache"
printf 'direct=ok\nproxy=ok\nepoch=%s\n' "$(date +%s)" > "$test_root/cache/net-cache"

# shellcheck disable=SC1091
source "$project_dir/lib/dashboard.sh"

test "$(dash_uptime)" = "1w 2d 3h"

DASHBOARD_DRAWN=0
output="$(dashboard)"

grep -q 'SBX · sbx18 · 192.168.100.18' <<<"$output"
grep -q '运行中' <<<"$output"
grep -q 'TProxy' <<<"$output"
grep -q '直连 ✓' <<<"$output"
grep -q '代理 ✓' <<<"$output"
grep -q '自启 ✓' <<<"$output"
grep -q '运行 1w 2d 3h' <<<"$output"
grep -q 'Sing-box v1.14.4.*已是最新' <<<"$output"
grep -q "SBX v${project_version}.*已是最新" <<<"$output"
grep -q 'CPU 0.0%' <<<"$output"
grep -q 'RSS 62 MB' <<<"$output"
grep -q '系统内存 80Mi/1.0Gi' <<<"$output"
grep -q '内核 7.0.14-test' <<<"$output"
grep -q 'i5-1235U' <<<"$output"
grep -q 'TUN ✓' <<<"$output"
grep -q 'Clash :9095 ✓' <<<"$output"
grep -q 'Zashboard ✓' <<<"$output"
grep -q '\[1\] 安装/升级 Sing-box' <<<"$output"
grep -q '\[6\] Web 面板' <<<"$output"

for word in Running Enabled Online Installed; do
    if grep -q "$word" <<<"$output"; then
        echo "dashboard still contains mixed-language status: $word" >&2
        exit 1
    fi
done

if grep -q 'CPU        ' <<<"$output"; then
    echo "dashboard still contains padded CPU output" >&2
    exit 1
fi

if printf '%s' "$output" | grep -q $'\033'; then
    echo "non-TTY dashboard output must not contain ANSI escapes" >&2
    exit 1
fi

printf 'singbox=v1.15.0\nsbx=v9.9.9\nepoch=%s\n' "$(date +%s)" > "$test_root/cache/version-cache"
DASHBOARD_DRAWN=0
output="$(dashboard)"
grep -q 'Sing-box v1.14.4.*↑ v1.15.0' <<<"$output"
grep -q "SBX v${project_version}.*↑ v9.9.9" <<<"$output"

COLUMNS=70
DASHBOARD_DRAWN=0
output="$(dashboard)"
grep -q '\[3\] 运行管理.*\[4\] 路由设置' <<<"$output"

COLUMNS=60
DASHBOARD_DRAWN=0
output="$(dashboard)"
grep -q '· LXC' <<<"$output"
grep -q '^内核 7.0.14-test' <<<"$output"

echo "dashboard test passed"
