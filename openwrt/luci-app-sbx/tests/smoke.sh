#!/bin/sh
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
need() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }

switch_modes=false
[ "${1:-}" = "--switch" ] && switch_modes=true

need uci
need jsonfilter
need ip
need nft
[ -x /usr/bin/sbx-luci-health ] || fail "sbx health command missing"
[ -x /usr/bin/sbx-luci-transaction ] || fail "sbx transaction command missing"

health=$(/usr/bin/sbx-luci-health)
printf '%s\n' "$health"
printf '%s\n' "$health" | grep -q '"config_ok":true' || fail "configuration is not valid"
printf '%s\n' "$health" | grep -q '"route_ok":true' || fail "route policy is not healthy"
pass "baseline health"

mode=$(uci -q get sbx.main.mode || echo proxy-only)
config=$(uci -q get sbx.main.config_file || echo /etc/sing-box/config.json)
case "$mode" in
	tun)
	jsonfilter -q -i "$config" -e '@.inbounds[@.type="tun"].interface_name' | grep -q . || fail "TUN mode has no tun inbound"
	ip rule show | grep -q "iif .* lookup $(uci -q get sbx.main.tun_table || echo 101)" || fail "TUN policy rule missing"
	pass "TUN consistency"
	;;
	tproxy)
	port=$(jsonfilter -q -i "$config" -e '@.inbounds[@.type="tproxy"].listen_port' | head -n1)
	[ -n "$port" ] || fail "TProxy mode has no tproxy inbound"
	ip rule show | grep -q "lookup $(uci -q get sbx.main.tproxy_table || echo 100)" || fail "TProxy policy rule missing"
	nft list table inet sbx 2>/dev/null | grep -q "127.0.0.1:$port" || fail "TProxy nft rule missing"
	pass "TProxy consistency"
	;;
	proxy-only) pass "proxy-only consistency" ;;
	*) fail "unknown mode: $mode" ;;
esac

if $switch_modes; then
	tun_url=$(uci -q get sbx.main.tun_config_url || true)
	tproxy_url=$(uci -q get sbx.main.tproxy_config_url || true)
	[ -n "$tun_url" ] && [ -n "$tproxy_url" ] || fail "both mode URLs are required for switch test"
	/usr/bin/sbx-luci-transaction tproxy >/tmp/sbx-smoke-tproxy.out 2>&1 || { cat /tmp/sbx-smoke-tproxy.out >&2; fail "TProxy switch"; }
	sleep 2
	jsonfilter -q -i "$config" -e '@.inbounds[@.type="tproxy"].listen_port' | grep -q . || fail "TProxy config not active"
	pass "TUN/TProxy switch to TProxy"
	/usr/bin/sbx-luci-transaction tun >/tmp/sbx-smoke-tun.out 2>&1 || { cat /tmp/sbx-smoke-tun.out >&2; fail "TUN switch"; }
	sleep 2
	jsonfilter -q -i "$config" -e '@.inbounds[@.type="tun"].interface_name' | grep -q . || fail "TUN config not active"
	pass "TUN/TProxy switch back to TUN"
fi

echo "SBX smoke test complete"
