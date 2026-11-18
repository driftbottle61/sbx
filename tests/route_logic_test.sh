#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/sbx-route-test.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin"
cat > "$test_root/bin/iptables" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$IPT_LOG"
exit 0
STUB
cat > "$test_root/bin/nft" <<'STUB'
#!/bin/sh
if [ "$1" = "list" ]; then
    exit 1
fi
if [ "$1" = "-f" ]; then
    cp "$2" "$NFT_LOG"
    printf 'apply\n' >> "$NFT_CALLS"
    exit 0
fi
exit 0
STUB
cat > "$test_root/bin/getent" <<'STUB'
#!/bin/sh
printf 'sbx:x:7891:\n'
STUB
cat > "$test_root/bin/modprobe" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$test_root/bin/"*

export PATH="$test_root/bin:$PATH"
IPT_LOG="$test_root/iptables.log"
NFT_LOG="$test_root/nft.conf"
NFT_CALLS="$test_root/nft.calls"
export IPT_LOG NFT_LOG NFT_CALLS
: > "$IPT_LOG"
: > "$NFT_CALLS"

ROUTE_MODE=tproxy
FIREWALL_BACKEND=nftables
FW_MARK=7893
ROUTING_MARK=7895
TPROXY_PORT=7893
DNS_PORT=1053
DNS_REDIR_PORT=1053
TUN_NAME=utun
COMMON_PORTS=ON
PROXY_PORTS=22,80,443,8080,8443
SBX_GROUP=sbx
SBX_GID=7891
LAN_IPV4="192.168.100.0/24 192.168.88.0/24 192.168.50.0/24"
RESERVED_IPV4="10.0.0.0/8 127.0.0.0/8 192.168.0.0/16"
DNS_RESERVED_IPV4="10.0.0.0/8 127.0.0.0/8 192.168.0.0/16"
LOCAL_IPV4="192.168.100.18"
CN_IP_ROUTE=ON
CN_IP_FILE="$test_root/cn_ip.txt"
printf '1.0.1.0/24\n223.5.5.0/24\n# comment\n' > "$CN_IP_FILE"

# shellcheck disable=SC1091
source "$project_dir/lib/route.sh"
ok(){ :; }
warn(){ :; }
error(){ printf 'ERROR: %s\n' "$*" >&2; }

start_sbx_iptables

grep -Fq -- '-A SBX_MARK -s 192.168.100.0/24 -j SBX_MARK_RULES' "$IPT_LOG"
grep -Fq -- '-A SBX_MARK -s 192.168.88.0/24 -j SBX_MARK_RULES' "$IPT_LOG"
grep -Fq -- '-A SBX_MARK -s 192.168.50.0/24 -j SBX_MARK_RULES' "$IPT_LOG"
grep -Fq -- '-A SBX_MARK -j RETURN' "$IPT_LOG"
if grep -Fq -- '! -s' "$IPT_LOG"; then
    echo 'iptables must not use per-subnet negated source matches' >&2
    exit 1
fi
grep -Fq -- '-A SBX_MARK_RULES -p tcp -j TPROXY' "$IPT_LOG"

start_sbx_nft

grep -Fq 'elements = { 1.0.1.0/24, 223.5.5.0/24 }' "$NFT_LOG"

# Debian 默认 awk 是 mawk，不支持 {n,m} 间隔量词；确保 CN 解析在 mawk 下也正确。
if command -v mawk >/dev/null 2>&1; then
    mkdir -p "$test_root/mawk-bin"
    cat > "$test_root/mawk-bin/awk" <<'STUB'
#!/bin/sh
exec mawk "$@"
STUB
    chmod +x "$test_root/mawk-bin/awk"
    mawk_out="$(PATH="$test_root/mawk-bin:$PATH" cn_elements_from_file "$CN_IP_FILE")"
    test "$mawk_out" = "1.0.1.0/24, 223.5.5.0/24"
fi
grep -Fq 'ip daddr @cn_ip return' "$NFT_LOG"
test "$(wc -l < "$NFT_CALLS")" -eq 1

echo "route logic test passed"
