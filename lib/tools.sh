#!/bin/bash

tools_backup_dir="/opt/sbx/backup/network"
interfaces_file="${SBX_INTERFACES_FILE:-/etc/network/interfaces}"
interfaces_dir="${SBX_INTERFACES_DIR:-/etc/network/interfaces.d}"
netplan_dir="${SBX_NETPLAN_DIR:-/etc/netplan}"
resolv_conf_file="${SBX_RESOLV_CONF:-/etc/resolv.conf}"
systemd_network_dir="${SBX_SYSTEMD_NETWORK_DIR:-/etc/systemd/network}"

detect_primary_iface(){
    ip route show default 2>/dev/null | awk '/default/ {for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}'
}

get_iface_ipv4(){
    local iface
    iface="$1"
    ip -o -4 addr show dev "$iface" scope global 2>/dev/null | awk '{print $4; exit}'
}

get_default_gateway(){
    local iface
    iface="$1"
    ip route show default dev "$iface" 2>/dev/null | awk '/default/ {print $3; exit}'
}

get_current_dns(){
    local iface dns
    iface="$1"

    if command -v resolvectl >/dev/null 2>&1; then
        dns="$(resolvectl dns "$iface" 2>/dev/null | awk -F: '{print $2}' | xargs)"
        [ -n "$dns" ] && {
            echo "$dns"
            return
        }
    fi

    awk '/^nameserver[[:space:]]+/ {print $2}' "$resolv_conf_file" 2>/dev/null | xargs
}

detect_network_backend(){
    if command -v netplan >/dev/null 2>&1 && find "$netplan_dir" -maxdepth 1 \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | grep -q .; then
        echo "netplan"
        return
    fi

    # Debian/PVE commonly keeps ifupdown as the authoritative backend even
    # when systemd-networkd happens to be installed or running. Prefer it when
    # an interface stanza exists, otherwise the IP change is written to a file
    # that does not control the link.
    if [ -f "$interfaces_file" ] && grep -Eq '^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+' "$interfaces_file"; then
        echo "ifupdown"
        return
    fi
    if [ -d "$interfaces_dir" ] && find "$interfaces_dir" -type f -maxdepth 1 -print -exec grep -Eq '^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+' {} \; -print -quit | grep -q .; then
        echo "ifupdown"
        return
    fi

    if systemctl is-active --quiet systemd-networkd 2>/dev/null || systemctl is-enabled --quiet systemd-networkd 2>/dev/null; then
        echo "systemd-networkd"
        return
    fi

    echo "resolv.conf"
}

get_netplan_file(){
    find "$netplan_dir" -maxdepth 1 \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort | head -1
}

is_ipv4(){
    local ip a b c d oct
    ip="$1"

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    IFS=. read -r a b c d <<< "$ip"
    for oct in "$a" "$b" "$c" "$d"; do
        [ "$oct" -ge 0 ] 2>/dev/null && [ "$oct" -le 255 ] 2>/dev/null || return 1
    done
}

is_ipv4_cidr(){
    local addr prefix
    addr="${1%/*}"
    prefix="${1#*/}"

    [ "$addr" != "$prefix" ] || return 1
    is_ipv4 "$addr" || return 1
    [ "$prefix" -ge 0 ] 2>/dev/null && [ "$prefix" -le 32 ] 2>/dev/null
}

normalize_dns_list(){
    echo "$1" | tr ',;' '  ' | xargs
}

validate_dns_list(){
    local dns item
    dns="$(normalize_dns_list "$1")"
    [ -n "$dns" ] || return 1

    for item in $dns; do
        is_ipv4 "$item" || return 1
    done
}

cidr_to_netmask(){
    local prefix mask i full remain octets oct
    prefix="$1"
    mask=""
    full=$((prefix / 8))
    remain=$((prefix % 8))

    for i in 0 1 2 3; do
        if [ "$i" -lt "$full" ]; then
            oct=255
        elif [ "$i" -eq "$full" ]; then
            oct=$((256 - 2 ** (8 - remain)))
            [ "$remain" -eq 0 ] && oct=0
        else
            oct=0
        fi

        if [ -z "$mask" ]; then
            mask="$oct"
        else
            mask="$mask.$oct"
        fi
    done

    echo "$mask"
}

show_local_network_summary(){
    local iface ipv4 gateway dns backend

    iface="$(detect_primary_iface)"
    [ -z "$iface" ] && iface="$(ip -o link show 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}')"

    ipv4="$(get_iface_ipv4 "$iface")"
    gateway="$(get_default_gateway "$iface")"
    dns="$(get_current_dns "$iface")"
    backend="$(detect_network_backend)"

    echo
    echo "========== 本机网络 =========="
    echo "网络后端 : ${backend:-未知}"
    echo "网卡     : ${iface:-未检测到}"
    echo "IP地址   : ${ipv4:-未检测到}"
    echo "默认网关 : ${gateway:-未检测到}"
    echo "DNS      : ${dns:-未检测到}"
    echo
}

backup_network_config(){
    local backend file stamp
    backend="$1"
    stamp="$(date +%Y%m%d%H%M%S)"

    mkdir -p "$tools_backup_dir"

    case "$backend" in
        netplan)
            file="$(get_netplan_file)"
            [ -f "$file" ] && cp "$file" "$tools_backup_dir/$(basename "$file").$stamp.bak"
            ;;
        systemd-networkd)
            [ -d "$systemd_network_dir" ] && cp -a "$systemd_network_dir" "$tools_backup_dir/systemd-network.$stamp.bak"
            ;;
        ifupdown)
            [ -f "$interfaces_file" ] && cp "$interfaces_file" "$tools_backup_dir/interfaces.$stamp.bak"
            [ -d "$interfaces_dir" ] && cp -a "$interfaces_dir" "$tools_backup_dir/interfaces.d.$stamp.bak"
            ;;
        resolv.conf)
            [ -e "$resolv_conf_file" ] && cp -P "$resolv_conf_file" "$tools_backup_dir/resolv.conf.$stamp.bak"
            ;;
    esac
}

write_resolv_conf(){
    local dns item target
    dns="$(normalize_dns_list "$1")"

    if [ -L "$resolv_conf_file" ]; then
        target="$(readlink -f "$resolv_conf_file" 2>/dev/null || true)"
        case "$target" in
            /run/*|/etc/resolvconf/*)
                warn "$resolv_conf_file 由系统解析器管理（$target），拒绝直接改写"
                warn "请通过 systemd-resolved/resolvconf 或网络后端修改 DNS"
                return 1
                ;;
            ""|"$resolv_conf_file")
                warn "$resolv_conf_file 是无效或自引用的符号链接，拒绝改写"
                return 1
                ;;
        esac
        # 保留符号链接本身，直接写入其目标文件。
    fi

    mkdir -p "$(dirname "$resolv_conf_file")"
    : > "$resolv_conf_file" || return 1

    for item in $dns; do
        printf 'nameserver %s\n' "$item" >> "$resolv_conf_file"
    done
}

netplan_iface_file(){
    local iface="$1" file
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        awk -v iface="$iface" '
            /^[[:space:]]*ethernets:[[:space:]]*$/ { in_eth = 1; next }
            in_eth && /^[^[:space:]]/ { in_eth = 0 }
            in_eth {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                if (index(line, iface ":") == 1) { found = 1; exit }
            }
            END { exit(found ? 0 : 1) }
        ' "$file" && { echo "$file"; return 0; }
    done < <(find "$netplan_dir" -maxdepth 1 \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort)
    return 1
}

write_netplan_config(){
    local iface ip_cidr gateway dns file item existing
    iface="$1"
    ip_cidr="$2"
    gateway="$3"
    dns="$(normalize_dns_list "$4")"
    file="$netplan_dir/99-sbx-$iface.yaml"
    existing="$(netplan_iface_file "$iface" || true)"

    mkdir -p "$netplan_dir"

    # 不使用 get_netplan_file 覆盖第一个 YAML：那会静默删除其它网卡。
    # 若接口已由其它 netplan 文件定义，明确拒绝，避免产生重复定义。
    if [ -n "$existing" ] && [ "$existing" != "$file" ]; then
        warn "接口 $iface 已在 $existing 中定义"
        warn "为避免覆盖其它网卡，本次未写入；请手动修改该文件后重试"
        return 1
    fi

    cat > "$file" <<EOF
network:
  version: 2
  ethernets:
    $iface:
      dhcp4: no
      addresses:
        - $ip_cidr
EOF

    if [ -n "$gateway" ]; then
        cat >> "$file" <<EOF
      routes:
        - to: default
          via: $gateway
EOF
    fi

    if [ -n "$dns" ]; then
        cat >> "$file" <<EOF
      nameservers:
        addresses:
EOF
        for item in $dns; do
            printf '          - %s\n' "$item" >> "$file"
        done
    fi

    chmod 600 "$file" 2>/dev/null || true
}

write_systemd_network_config(){
    local iface ip_cidr gateway dns file item
    iface="$1"
    ip_cidr="$2"
    gateway="$3"
    dns="$(normalize_dns_list "$4")"
    file="$systemd_network_dir/10-sbx-$iface.network"

    mkdir -p "$systemd_network_dir"

    # 只重写当前接口，保留其它 SBX/系统 networkd 配置。
    cat > "$file" <<EOF
[Match]
Name=$iface

[Network]
Address=$ip_cidr
EOF

    [ -n "$gateway" ] && printf 'Gateway=%s\n' "$gateway" >> "$file"

    for item in $dns; do
        printf 'DNS=%s\n' "$item" >> "$file"
    done
}

ifupdown_file_has_iface(){
    local file="$1" iface="$2"
    [ -f "$file" ] || return 1
    awk -v target="$iface" '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (line ~ /^iface[[:space:]]+/) {
                n = split(line, a, /[[:space:]]+/)
                if (a[2] == target) found = 1
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$file"
}

strip_ifupdown_iface(){
    local file="$1" iface="$2"
    awk -v target="$iface" '
        {
            line = $0
            trimmed = line
            sub(/^[[:space:]]*/, "", trimmed)

            if (trimmed ~ /^(auto|allow-hotplug)[[:space:]]+/) {
                n = split(trimmed, a, /[[:space:]]+/)
                out = a[1]
                kept = 0
                for (i = 2; i <= n; i++) {
                    if (a[i] != target) { out = out " " a[i]; kept++ }
                }
                if (kept > 0) print out
                next
            }

            if (trimmed ~ /^iface[[:space:]]+/) {
                n = split(trimmed, a, /[[:space:]]+/)
                if (a[2] == target) { drop = 1; next }
                drop = 0
            } else if (trimmed ~ /^(source|mapping)[[:space:]]+/) {
                drop = 0
            }

            if (!drop) print
        }
    ' "$file"
}

write_ifupdown_config(){
    local iface ip_cidr gateway dns addr prefix netmask file tmp candidate
    iface="$1"
    ip_cidr="$2"
    gateway="$3"
    dns="$(normalize_dns_list "$4")"
    addr="${ip_cidr%/*}"
    prefix="${ip_cidr#*/}"
    netmask="$(cidr_to_netmask "$prefix")"
    file=""

    mkdir -p "$interfaces_dir"

    # 优先原地更新已有的 iface stanza，保留文件中的 lo、vmbr、source
    # 和其它网卡。只有完全找不到该接口时才新建 SBX 独立文件。
    if ifupdown_file_has_iface "$interfaces_file" "$iface"; then
        file="$interfaces_file"
    else
        for candidate in "$interfaces_dir"/*; do
            [ -f "$candidate" ] || continue
            if ifupdown_file_has_iface "$candidate" "$iface"; then
                file="$candidate"
                break
            fi
        done
    fi
    [ -n "$file" ] || file="$interfaces_dir/sbx-$iface"

    tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
    if [ -f "$file" ]; then
        strip_ifupdown_iface "$file" "$iface" > "$tmp"
        [ -s "$tmp" ] && printf '\n' >> "$tmp"
    fi

    cat >> "$tmp" <<EOF
# Managed by SBX
auto $iface
iface $iface inet static
    address $addr
    netmask $netmask
EOF

    [ -n "$gateway" ] && printf '    gateway %s\n' "$gateway" >> "$tmp"
    [ -n "$dns" ] && printf '    dns-nameservers %s\n' "$dns" >> "$tmp"

    chmod 644 "$tmp" 2>/dev/null || true
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

apply_network_config(){
    local backend iface
    backend="$1"
    iface="$2"

    case "$backend" in
        netplan)
            netplan generate && netplan apply
            ;;
        systemd-networkd)
            # Flush runtime addresses before networkd reconfigures the link;
            # otherwise the old static address can survive the restart.
            [ -n "$iface" ] && ip -4 addr flush dev "$iface" scope global 2>/dev/null || true
            networkctl reload 2>/dev/null || true
            systemctl restart systemd-networkd
            [ -n "$iface" ] && networkctl reconfigure "$iface" 2>/dev/null || true
            ;;
        ifupdown)
            if command -v ifreload >/dev/null 2>&1; then
                ifreload -a
            elif systemctl is-active --quiet networking 2>/dev/null; then
                systemctl restart networking
            else
                ip addr flush dev "$iface" scope global 2>/dev/null || true
                ip addr add "$ip_cidr" dev "$iface"
                [ -n "$gateway" ] && ip route replace default via "$gateway" dev "$iface"
            fi
            # ifupdown may leave the previous address as a secondary address;
            # enforce the requested single IPv4 address after reconfiguration.
            ip -4 addr flush dev "$iface" scope global 2>/dev/null || true
            ip -4 addr add "$ip_cidr" dev "$iface" 2>/dev/null || true
            if [ -n "$gateway" ]; then
                ip route del default dev "$iface" 2>/dev/null || true
                ip route replace default via "$gateway" dev "$iface" 2>/dev/null || true
            fi
            ;;
        resolv.conf)
            if command -v resolvectl >/dev/null 2>&1; then
                resolvectl flush-caches 2>/dev/null || true
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

save_network_config(){
    local backend iface ip_cidr gateway dns
    backend="$1"
    iface="$2"
    ip_cidr="$3"
    gateway="$4"
    dns="$5"

    backup_network_config "$backend"

    # Debian 13 may run dhcpcd independently of ifupdown. When switching to a
    # static address it will otherwise immediately restore the old DHCP lease.
    if [ -n "$ip_cidr" ]; then
        if command -v dhcpcd >/dev/null 2>&1; then
            dhcpcd -k "$iface" >/dev/null 2>&1 || true
        fi
        # 只停止该接口的 dhcpcd 实例；不要全局 disable dhcpcd.service，
        # 否则多网卡机器上其它接口会一起丢失 DHCP。
        if systemctl list-unit-files "dhcpcd@$iface.service" >/dev/null 2>&1; then
            systemctl disable --now "dhcpcd@$iface.service" >/dev/null 2>&1 || true
        fi
        pkill -f "dhcpcd: $iface" >/dev/null 2>&1 || true
    fi

    case "$backend" in
        netplan)
            write_netplan_config "$iface" "$ip_cidr" "$gateway" "$dns"
            ;;
        systemd-networkd)
            write_systemd_network_config "$iface" "$ip_cidr" "$gateway" "$dns"
            ;;
        ifupdown)
            write_ifupdown_config "$iface" "$ip_cidr" "$gateway" "$dns"
            ;;
        resolv.conf)
            write_resolv_conf "$dns"
            ;;
        *)
            error "不支持的网络后端：$backend"
            return 1
            ;;
    esac

    apply_network_config "$backend" "$iface"
    local apply_status=$?

    # Debian 13 may have no resolver manager after dhcpcd is disabled. In that
    # case ifupdown's dns-nameservers directive has no consumer, so explicitly
    # maintain resolv.conf from the DNS values entered by the user.
    if [ -n "$dns" ] && \
       ! command -v resolvconf >/dev/null 2>&1 && \
       ! command -v openresolv >/dev/null 2>&1 && \
       ! systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        write_resolv_conf "$dns"
    fi

    return "$apply_status"
}

confirm_apply_network(){
    echo
    warn "保存后将立即应用网络配置，错误的 IP、网关或 DNS 可能导致当前连接中断"
    read -p "确认保存并立即应用？输入 yes 继续：" CONFIRM
    [ "$CONFIRM" = "yes" ]
}

change_local_ip(){
    local iface current_ip current_gateway current_dns backend new_iface new_ip new_gateway new_dns

    iface="$(detect_primary_iface)"
    [ -z "$iface" ] && iface="$(ip -o link show 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}')"
    current_ip="$(get_iface_ipv4 "$iface")"
    current_gateway="$(get_default_gateway "$iface")"
    current_dns="$(get_current_dns "$iface")"
    backend="$(detect_network_backend)"

    clear
    show_local_network_summary

    read -p "请输入网卡名称 [${iface}]：" new_iface
    [ -n "$new_iface" ] && iface="$new_iface"

    read -p "请输入新的 IPv4/CIDR [${current_ip}]：" new_ip
    [ -z "$new_ip" ] && new_ip="$current_ip"

    if ! is_ipv4_cidr "$new_ip"; then
        error "IP 格式错误，请使用 192.168.100.6/24 这种格式"
        pause
        return
    fi

    read -p "请输入默认网关 [${current_gateway}]：" new_gateway
    [ -z "$new_gateway" ] && new_gateway="$current_gateway"

    if [ -n "$new_gateway" ] && ! is_ipv4 "$new_gateway"; then
        error "网关格式错误"
        pause
        return
    fi

    read -p "请输入 DNS，多个用空格或逗号分隔 [${current_dns}]：" new_dns
    [ -z "$new_dns" ] && new_dns="$current_dns"

    if ! validate_dns_list "$new_dns"; then
        error "DNS 格式错误"
        pause
        return
    fi

    confirm_apply_network || {
        warn "已取消"
        pause
        return
    }

    if save_network_config "$backend" "$iface" "$new_ip" "$new_gateway" "$new_dns"; then
        ok "本机 IP 配置已保存并应用"
    else
        error "本机 IP 配置应用失败，请检查备份目录：$tools_backup_dir"
    fi

    pause
}

change_local_dns(){
    local iface current_ip current_gateway current_dns backend new_dns

    iface="$(detect_primary_iface)"
    [ -z "$iface" ] && iface="$(ip -o link show 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}')"
    current_ip="$(get_iface_ipv4 "$iface")"
    current_gateway="$(get_default_gateway "$iface")"
    current_dns="$(get_current_dns "$iface")"
    backend="$(detect_network_backend)"

    clear
    show_local_network_summary

    read -p "请输入新的 DNS，多个用空格或逗号分隔 [${current_dns}]：" new_dns
    [ -z "$new_dns" ] && new_dns="$current_dns"

    if ! validate_dns_list "$new_dns"; then
        error "DNS 格式错误"
        pause
        return
    fi

    if [ "$backend" != "resolv.conf" ] && ! is_ipv4_cidr "$current_ip"; then
        error "未检测到当前 IPv4/CIDR，无法安全写入 $backend 配置"
        pause
        return
    fi

    confirm_apply_network || {
        warn "已取消"
        pause
        return
    }

    if [ "$backend" = "resolv.conf" ]; then
        if save_network_config "$backend" "$iface" "" "" "$new_dns"; then
            ok "本机 DNS 已保存并应用"
        else
            error "本机 DNS 应用失败，请检查备份目录：$tools_backup_dir"
        fi
    else
        if save_network_config "$backend" "$iface" "$current_ip" "$current_gateway" "$new_dns"; then
            ok "本机 DNS 已保存并应用"
        else
            error "本机 DNS 应用失败，请检查备份目录：$tools_backup_dir"
        fi
    fi

    pause
}

tools_menu(){
while true
do

clear

cat <<EOF

================================
            工具箱
================================

1. 修改本机 IP 地址

2. 修改本机 DNS

3. 查看本机网络状态

4. 查看 DNS 状态

5. 查看路由状态

6. 查看 TUN 状态

7. 开启 IP Forward

0. 返回

================================

EOF

read -p "请选择：" NUM

case "$NUM" in
1)
change_local_ip
;;
2)
change_local_dns
;;
3)
show_local_network_summary
pause
;;
4)
show_dns
pause
;;
5)
show_route
pause
;;
6)
show_tun
pause
;;
7)
enable_forward
pause
;;
0)
return
;;
*)
warn "输入错误"
pause
;;
esac

done
}
