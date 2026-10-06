#!/bin/sh
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

root=${1:-}
if [ "$root" = "--installed" ]; then
	[ -d /etc/config ] || fail "not an OpenWrt installation"
	for f in \
		/etc/init.d/sbx \
		/etc/sbx-version \
		/usr/bin/sbx-luci-action \
		/usr/bin/sbx-luci-dns \
		/usr/bin/sbx-luci-health \
		/usr/bin/sbx-luci-migrate \
		/usr/bin/sbx-luci-transaction \
		/usr/share/luci/menu.d/luci-app-sbx.json \
		/usr/share/rpcd/acl.d/luci-app-sbx.json \
		/www/luci-static/resources/view/sbx.js; do
		[ -e "$f" ] || fail "missing installed file: $f"
	done
	[ -x /etc/init.d/sbx ] || fail "init script is not executable"
	for f in /usr/bin/sbx-luci-* /usr/bin/sbx-zashboard; do
		[ -x "$f" ] || fail "script is not executable: $f"
	done
	[ "$(uci -q get sbx.main.mode || true)" != "" ] || fail "sbx UCI section is missing"
	[ -x /usr/bin/sbx-luci-health ] || fail "health command is missing"
	health=$(/usr/bin/sbx-luci-health) || fail "health command failed"
	printf '%s\n' "$health"
	printf '%s\n' "$health" | grep -q '"overall":"ok"' || fail "installed health is not ok"
	pass "installed file and runtime checks"
	exit 0
fi

[ -n "$root" ] || root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
pkg="$root"
[ -d "$pkg/root" ] || fail "invalid package source: $pkg"

for f in \
	root/etc/config/sbx \
	root/etc/init.d/sbx \
	root/etc/sbx-version \
	root/usr/bin/sbx-luci-action \
	root/usr/bin/sbx-luci-dns \
	root/usr/bin/sbx-luci-health \
	root/usr/bin/sbx-luci-migrate \
	root/usr/bin/sbx-luci-transaction \
	root/usr/share/luci/menu.d/luci-app-sbx.json \
	root/usr/share/rpcd/acl.d/luci-app-sbx.json \
	root/www/luci-static/resources/view/sbx.js; do
	[ -e "$pkg/$f" ] || fail "missing source file: $f"
done

for f in "$pkg"/root/etc/init.d/sbx "$pkg"/root/usr/bin/sbx-*; do
	[ -x "$f" ] || fail "source script is not executable: $f"
	sh -n "$f" || fail "shell syntax: $f"
done

if command -v node >/dev/null 2>&1; then
	node --check "$pkg/root/www/luci-static/resources/view/sbx.js" >/dev/null || fail "JavaScript syntax"
fi

if command -v python3 >/dev/null 2>&1; then
	python3 - "$pkg/root/usr/share/luci/menu.d/luci-app-sbx.json" "$pkg/root/usr/share/rpcd/acl.d/luci-app-sbx.json" <<'PY'
import json, sys
for name in sys.argv[1:]:
    with open(name, encoding='utf-8') as fh:
        json.load(fh)
PY
else
	command -v jsonfilter >/dev/null 2>&1 || fail "need python3 or jsonfilter for JSON validation"
fi

grep -qx '/etc/config/sbx' "$pkg/Makefile" || fail "sbx config is not declared as conffile"
grep -q 'sbx-luci-migrate' "$pkg/Makefile" || fail "post-install migration is not wired"
grep -q 'version=0\.3\.0' "$pkg/root/etc/sbx-version" || fail "version file mismatch"

bad=$(find "$pkg/root" -type f ! -perm -111 -path '*/usr/bin/*' -print)
[ -z "$bad" ] || fail "non-executable command file(s): $bad"
pass "source files and permissions"
pass "shell and JSON syntax"
pass "package metadata and migration hook"
echo "SBX release check complete"
