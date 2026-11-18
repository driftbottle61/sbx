#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/sbx-preserve.XXXXXX)"
run_resolv_dir=""

cleanup(){
    rm -rf "$test_root"
    [ -z "$run_resolv_dir" ] || rm -rf "$run_resolv_dir"
}
trap cleanup EXIT

fail(){
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq(){
    [ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

# shellcheck disable=SC1091
source "$project_dir/lib/common.sh"
info(){ :; }
ok(){ :; }
warn(){ :; }
error(){ :; }

mkdir -p "$test_root/ifupdown.d" "$test_root/netplan" "$test_root/networkd" \
    "$test_root/units" "$test_root/config"
export SBX_INTERFACES_FILE="$test_root/interfaces"
export SBX_INTERFACES_DIR="$test_root/ifupdown.d"
export SBX_NETPLAN_DIR="$test_root/netplan"
export SBX_SYSTEMD_NETWORK_DIR="$test_root/networkd"
export SBX_RESOLV_CONF="$test_root/resolv.conf"
export SBX_UNIT_BACKUP_DIR="$test_root/units-backup"
export SBX_CONFIG_BACKUP_DIR="$test_root/config-backup"

# shellcheck disable=SC1091
source "$project_dir/lib/system.sh"
# shellcheck disable=SC1091
source "$project_dir/lib/tools.sh"
# shellcheck disable=SC1091
source "$project_dir/lib/service.sh"
# shellcheck disable=SC1091
source "$project_dir/lib/route.sh"

# 1. sysctl：只更新 SBX 键，保留其它自定义配置。
cat > "$test_root/sysctl.conf" <<'EOF'
vm.swappiness = 10
net.ipv4.ip_forward = 0
net.core.somaxconn = 4096
EOF
SYSCTL_FILE="$test_root/sysctl.conf"
sysctl(){ :; }
enable_forward
grep -q '^vm.swappiness = 10$' "$SYSCTL_FILE" || fail "sysctl custom key lost"
grep -q '^net.core.somaxconn = 4096$' "$SYSCTL_FILE" || fail "sysctl custom key lost"
[ "$(grep -c '^net.ipv4.ip_forward=' "$SYSCTL_FILE")" = "1" ] || fail "ip_forward duplicated"
grep -q '^net.ipv4.ip_forward=1$' "$SYSCTL_FILE" || fail "ip_forward not enabled"
grep -q '^net.ipv4.conf.all.accept_local=1$' "$SYSCTL_FILE" || fail "accept_local missing"

# 2. ifupdown：替换 eth0 时保留 lo、vmbr0、source 和其它 auto 接口。
cat > "$SBX_INTERFACES_FILE" <<'EOF'
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto eth0 vmbr0
iface eth0 inet dhcp

iface vmbr0 inet static
    address 192.168.100.3/24
    gateway 192.168.100.1
EOF
write_ifupdown_config eth0 192.168.100.18/24 192.168.100.1 "1.1.1.1 8.8.8.8"
grep -q '^auto lo$' "$SBX_INTERFACES_FILE" || fail "lo stanza lost"
grep -q '^iface lo inet loopback$' "$SBX_INTERFACES_FILE" || fail "lo iface lost"
grep -q '^source /etc/network/interfaces.d/\*$' "$SBX_INTERFACES_FILE" || fail "source directive lost"
grep -q '^iface vmbr0 inet static$' "$SBX_INTERFACES_FILE" || fail "vmbr0 lost"
grep -q '^auto vmbr0$' "$SBX_INTERFACES_FILE" || fail "auto vmbr0 lost"
[ "$(grep -c '^iface eth0 inet ' "$SBX_INTERFACES_FILE")" = "1" ] || fail "eth0 duplicated"
grep -q '^    address 192.168.100.18$' "$SBX_INTERFACES_FILE" || fail "new eth0 address missing"
grep -q '^    dns-nameservers 1.1.1.1 8.8.8.8$' "$SBX_INTERFACES_FILE" || fail "dns missing"

# 3. netplan：不得覆盖已定义该接口的其它 YAML；新接口写独立文件。
cat > "$test_root/netplan/50-cloud-init.yaml" <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF
if write_netplan_config eth0 192.168.100.18/24 192.168.100.1 1.1.1.1; then
    fail "netplan should refuse to overwrite existing interface definition"
fi
grep -q 'dhcp4: true' "$test_root/netplan/50-cloud-init.yaml" || fail "existing netplan file changed"
[ ! -e "$test_root/netplan/99-sbx-eth0.yaml" ] || fail "conflicting netplan file created"

mkdir -p "$test_root/netplan2"
netplan_dir="$test_root/netplan2"
cat > "$netplan_dir/50-eth1.yaml" <<'EOF'
network:
  version: 2
  ethernets:
    eth1:
      dhcp4: true
EOF
write_netplan_config eth0 192.168.100.18/24 192.168.100.1 1.1.1.1
grep -q 'dhcp4: true' "$netplan_dir/50-eth1.yaml" || fail "unrelated netplan file changed"
grep -q 'addresses:' "$netplan_dir/99-sbx-eth0.yaml" || fail "dedicated netplan file missing"

# 4. systemd-networkd：只重写当前接口，不删除其它接口配置。
cat > "$systemd_network_dir/10-sbx-eth0.network" <<'EOF'
[Match]
Name=eth0
EOF
cat > "$systemd_network_dir/10-sbx-eth1.network" <<'EOF'
[Match]
Name=eth1
EOF
write_systemd_network_config eth0 192.168.100.18/24 192.168.100.1 1.1.1.1
[ -f "$systemd_network_dir/10-sbx-eth1.network" ] || fail "other networkd profile deleted"
grep -q 'Address=192.168.100.18/24' "$systemd_network_dir/10-sbx-eth0.network" || fail "networkd address missing"

# 5. resolv.conf：普通符号链接保留链接；系统管理的链接拒绝改写。
printf 'nameserver 9.9.9.9\n' > "$test_root/resolv.target"
ln -s "$test_root/resolv.target" "$SBX_RESOLV_CONF"
write_resolv_conf "1.1.1.1 8.8.8.8"
[ -L "$SBX_RESOLV_CONF" ] || fail "resolv.conf symlink replaced"
grep -q '^nameserver 1.1.1.1$' "$test_root/resolv.target" || fail "resolv target not updated"

if mkdir -p /run/sbx-preserve-test.$$ 2>/dev/null; then
    run_resolv_dir="/run/sbx-preserve-test.$$"
    : > "$run_resolv_dir/stub-resolv.conf"
    ln -s "$run_resolv_dir/stub-resolv.conf" "$test_root/system-resolv.conf"
    SBX_RESOLV_CONF="$test_root/system-resolv.conf"
    resolv_conf_file="$SBX_RESOLV_CONF"
    if write_resolv_conf "1.1.1.1"; then
        fail "system-managed resolv.conf should be refused"
    fi
    [ -L "$SBX_RESOLV_CONF" ] || fail "system resolv symlink removed"
    SBX_RESOLV_CONF="$test_root/resolv.conf"
    resolv_conf_file="$SBX_RESOLV_CONF"
fi

# 6. systemd unit：内容不变不重写；被修改后先备份再覆盖。
systemctl(){ :; }
SERVICE_FILE="$test_root/sing-box.service"
SINGBOX_BIN="/bin/true"
CONFIG_FILE="$test_root/config.json"
SBX_GROUP="root"
create_service
first_mtime="$(stat -c %Y "$SERVICE_FILE")"
sleep 1
create_service
[ "$(stat -c %Y "$SERVICE_FILE")" = "$first_mtime" ] || fail "unchanged unit was rewritten"
printf '# local customization\n' >> "$SERVICE_FILE"
create_service
backup_file="$(find "$SBX_UNIT_BACKUP_DIR" -type f -name 'sing-box.service.*.bak' | head -1)"
[ -n "$backup_file" ] || fail "unit backup not created"
grep -q '# local customization' "$backup_file" || fail "unit backup content wrong"
grep -q '^# Managed by SBX$' "$SERVICE_FILE" || fail "managed marker missing"

# 7. sing-box 防回环配置：LAN 列表完整写入 DNS 直连规则。
command -v jq >/dev/null 2>&1 || fail "jq is required for route config test"
route_config_file="$test_root/route.conf"
cat > "$route_config_file" <<EOF
ROUTE_MODE="tproxy"
LAN_IPV4_ALLOW="192.168.100.0/24 192.168.88.0/24 192.168.50.0/24 192.168.10.0/24"
SINGBOX_BIN="/bin/true"
CONFIG_BACKUP="$test_root/config.json.bak"
EOF
CONFIG_FILE="$test_root/config.json"
cat > "$CONFIG_FILE" <<'EOF'
{"outbounds":[],"route":{"rules":[{"outbound":"custom-rule","protocol":"dns"}]},"dns":{"servers":[]},"inbounds":[]}
EOF
prepare_singbox_route_config
[ "${SBX_ROUTE_CONFIG_APPLIED:-0}" = "1" ] || fail "route config was not applied"
for cidr in 192.168.100.0/24 192.168.88.0/24 192.168.50.0/24 192.168.10.0/24; do
    jq -e --arg cidr "$cidr" '[.route.rules[] | select(.outbound == "sbx-lan-dns-direct") | .ip_cidr[]] | index($cidr)' "$CONFIG_FILE" >/dev/null \
        || fail "missing DNS direct CIDR $cidr"
done
jq -e '[.route.rules[] | select(.outbound == "custom-rule")] | length == 1' "$CONFIG_FILE" >/dev/null \
    || fail "custom route rule lost"

# 8. 允许网段应用：必须先写配置，再重启 sing-box。
(
    prepare_singbox_route_config(){ PREPARE_CALLED=1; SBX_ROUTE_CONFIG_APPLIED=1; return 0; }
    reload_singbox_config(){ RELOAD_CALLED=1; return 0; }
    ROUTE_MODE="tproxy"
    apply_lan_allowlist
    [ "${PREPARE_CALLED:-0}" = "1" ] || fail "apply_lan_allowlist did not update config.json"
    [ "${RELOAD_CALLED:-0}" = "1" ] || fail "apply_lan_allowlist did not restart sing-box"
)

(
    prepare_singbox_route_config(){ SBX_ROUTE_CONFIG_APPLIED=0; return 0; }
    reload_singbox_config(){ RELOAD_CALLED=1; return 0; }
    ROUTE_MODE="tproxy"
    if apply_lan_allowlist; then
        fail "apply_lan_allowlist must fail when config was not written"
    fi
    [ -z "${RELOAD_CALLED:-}" ] || fail "sing-box restarted without a config update"
)

echo "config preservation test passed"
