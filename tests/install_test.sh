#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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
grep -q 'SBX_VERSION="1.2.7"' "$SBX_INSTALL_DIR/data/sbx.conf"

"$SBX_INSTALL_DIR/uninstall.sh"
test ! -e "$SBX_INSTALL_DIR"
test ! -e "$SBX_BIN_DIR/sbx"

echo "install test passed"
