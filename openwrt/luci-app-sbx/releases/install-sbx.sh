#!/bin/sh
set -u

usage() {
	echo "Usage: $0 PACKAGE [SHA256]" >&2
	exit 2
}

fail() {
	echo "ERROR: $*" >&2
	exit 1
}

[ $# -ge 1 ] || usage
package=$1
expected=${2:-}
[ -f "$package" ] || fail "package not found: $package"

if [ -n "$expected" ]; then
	command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required when a checksum is supplied"
	actual=$(sha256sum "$package" | awk '{print $1}')
	[ "$actual" = "$expected" ] || fail "SHA256 mismatch: expected $expected, got $actual"
fi

config=/etc/config/sbx
singbox_config=$(uci -q get sbx.main.config_file 2>/dev/null || echo /etc/sing-box/config.json)
stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)
backup=/etc/sbx/upgrade-backups/$stamp
mkdir -p "$backup" || fail "cannot create backup directory"
[ -f "$config" ] && cp -p "$config" "$backup/sbx.config"
[ -f "$singbox_config" ] && cp -p "$singbox_config" "$backup/sing-box.json"

if command -v apk >/dev/null 2>&1 && printf '%s' "$package" | grep -q '\.apk$'; then
	apk add --allow-untrusted --no-network "$package" || fail "apk installation failed; backup: $backup"
elif command -v opkg >/dev/null 2>&1 && printf '%s' "$package" | grep -q '\.ipk$'; then
	opkg install "$package" || fail "opkg installation failed; backup: $backup"
else
	fail "package manager/format mismatch; expected apk or opkg package"
fi

/etc/init.d/rpcd restart >/dev/null 2>&1 || true
health=''
if [ -x /usr/bin/sbx-luci-health ]; then
	health=$(/usr/bin/sbx-luci-health 2>/dev/null || true)
fi
if printf '%s\n' "$health" | grep -q '"overall":"ok"'; then
	echo "SBX upgrade successful"
	echo "backup=$backup"
	echo "$health"
	exit 0
fi

echo "SBX health check failed after installation; restoring configuration" >&2
[ -f "$backup/sbx.config" ] && cp -p "$backup/sbx.config" "$config"
[ -f "$backup/sing-box.json" ] && cp -p "$backup/sing-box.json" "$singbox_config"
uci commit sbx >/dev/null 2>&1 || true
/etc/init.d/sing-box restart >/dev/null 2>&1 || true
/usr/bin/sbx-luci-route apply >/dev/null 2>&1 || true
echo "restored backup=$backup" >&2
echo "$health" >&2
exit 1
