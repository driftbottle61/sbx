#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_DIR="${SBX_INSTALL_DIR:-/opt/sbx}"
readonly BIN_DIR="${SBX_BIN_DIR:-/usr/local/bin}"
readonly SERVICE_FILE="${SBX_SERVICE_FILE:-/etc/systemd/system/sing-box.service}"
readonly WEB_SERVICE_FILE="/etc/systemd/system/sbx-web.service"

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "Please run as root." >&2; exit 1; }

keep_data=0
[ "${1:-}" = "--keep-data" ] && keep_data=1

if [ -f "$SERVICE_FILE" ] && grep -q '/opt/sbx/sbx-route' "$SERVICE_FILE"; then
    systemctl disable --now sing-box.service >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload >/dev/null 2>&1 || true
fi

if [ -f "$WEB_SERVICE_FILE" ] && grep -q '/opt/sbx/web/sbx_web.py' "$WEB_SERVICE_FILE"; then
    systemctl disable --now sbx-web.service >/dev/null 2>&1 || true
    rm -f "$WEB_SERVICE_FILE"
    systemctl daemon-reload >/dev/null 2>&1 || true
fi

[ ! -x "$INSTALL_DIR/sbx-route" ] || "$INSTALL_DIR/sbx-route" stop >/dev/null 2>&1 || true
rm -f "$BIN_DIR/sbx" "$BIN_DIR/sbx-route"

if [ "$keep_data" -eq 1 ]; then
    saved_dir="/var/lib/sbx-uninstall-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$saved_dir"
    [ ! -f "$INSTALL_DIR/data/sbx.conf" ] || cp -p "$INSTALL_DIR/data/sbx.conf" "$saved_dir/"
    [ ! -f /etc/sbx-web/config.json ] || cp -p /etc/sbx-web/config.json "$saved_dir/sbx-web.json"
    [ ! -d /etc/sing-box ] || cp -a /etc/sing-box "$saved_dir/"
    echo "Configuration saved to $saved_dir"
fi

rm -rf "$INSTALL_DIR"
echo "SBX has been removed. The Sing-box configuration and binary were left in place."
