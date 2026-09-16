#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
project_version="$(sed -n 's/^SBX_VERSION="\([^"]*\)"/\1/p' "$project_dir/data/sbx.conf")"
test_root="$(mktemp -d /tmp/sbx-test.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin"
export SBX_INSTALL_DIR="$test_root/opt/sbx"
export SBX_BIN_DIR="$test_root/bin"
export SBX_SERVICE_FILE="$test_root/sing-box.service"

"$project_dir/install.sh" --skip-deps
test -x "$SBX_INSTALL_DIR/sbx"
test -x "$SBX_BIN_DIR/sbx"
test "$(stat -c '%a' "$SBX_INSTALL_DIR/data/sbx.conf")" = "600"

printf 'CONFIG_URL="https://example.invalid/config"\n' > "$SBX_INSTALL_DIR/data/sbx.conf"
"$project_dir/install.sh" --skip-deps
grep -q 'example.invalid' "$SBX_INSTALL_DIR/data/sbx.conf"
grep -q "SBX_VERSION=\"$project_version\"" "$SBX_INSTALL_DIR/data/sbx.conf"

test_root_config="$test_root/config.sh"
sed "s#config_file=\"/opt/sbx/data/sbx.conf\"#config_file=\"$test_root/sbx.conf\"#" \
    "$project_dir/lib/config.sh" > "$test_root_config"
cat > "$test_root/sbx.conf" <<EOF
SBX_VERSION="$project_version"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="/etc/sing-box/config.json"
CONFIG_BACKUP="/etc/sing-box/config.json.bak"
CONFIG_URL="old-tun"
CONFIG_URL_TPROXY="old-proxy"
CONFIG_URL_TUN="old-tun"
SINGBOX_BIN="/bin/true"
SERVICE_NAME="sing-box"
SERVICE_FILE="$test_root/sing-box.service"
ROUTE_MODE="tun"
EOF
bash -c 'source "$1"; ok(){ :; }; clear(){ :; }; set_config_urls "new-proxy" "new-tun"' _ "$test_root_config"
. "$test_root/sbx.conf"
test "$CONFIG_URL" = "new-tun"
test "$CONFIG_URL_TPROXY" = "new-proxy"
test "$CONFIG_URL_TUN" = "new-tun"

"$SBX_INSTALL_DIR/uninstall.sh"
test ! -e "$SBX_INSTALL_DIR"
test ! -e "$SBX_BIN_DIR/sbx"

echo "install test passed"
