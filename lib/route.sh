#!/bin/bash

route_config_file="/opt/sbx/data/sbx.conf"

load_route_config(){
    [ -f "$route_config_file" ] && source "$route_config_file"

    [ -z "$ROUTE_MODE" ] && ROUTE_MODE="tproxy"
    [ -z "$FIREWALL_BACKEND" ] && FIREWALL_BACKEND="nftables"
    [ -z "$ROUTE_SCOPE" ] && ROUTE_SCOPE="lan"
    [ -z "$FW_MARK" ] && FW_MARK="7893"
    [ -z "$ROUTE_TABLE" ] && ROUTE_TABLE="100"
    [ -z "$ROUTING_MARK" ] && ROUTING_MARK="$((FW_MARK + 2))"
    [ -z "$MIX_PORT" ] && MIX_PORT="7890"
    [ -z "$REDIR_PORT" ] && REDIR_PORT="7892"
    [ -z "$TPROXY_PORT" ] && TPROXY_PORT="7893"
    [ -z "$DNS_PORT" ] && DNS_PORT="1053"
    [ -z "$DNS_REDIR_PORT" ] && DNS_REDIR_PORT="$DNS_PORT"
    [ -z "$COMMON_PORTS" ] && COMMON_PORTS="ON"
    [ -z "$PROXY_PORTS" ] && PROXY_PORTS="22,80,443,8080,8443"
    [ -z "$TUN_NAME" ] && TUN_NAME="utun"
    [ -z "$CN_IP_ROUTE" ] && CN_IP_ROUTE="ON"
    [ -z "$CN_IP_FILE" ] && CN_IP_FILE="/opt/sbx/data/cn_ip.txt"
    [ -z "$SBX_GROUP" ] && SBX_GROUP="sbx"
    [ -z "$SBX_GID" ] && SBX_GID="7891"

    detect_config_ports
}

detect_config_ports(){
    command -v jq >/dev/null 2>&1 || return
    [ -f "$CONFIG_FILE" ] || return

    local tproxy_port dns_port
    tproxy_port="$(jq -r '[.inbounds[]? | select(.type == "tproxy") | (.listen_port // .port)] | map(select(. != null)) | first // empty' "$CONFIG_FILE" 2>/dev/null)"
    dns_port="$(jq -r '[.inbounds[]? | select(.tag == "dns-in" or .type == "direct") | (.listen_port // .port)] | map(select(. != null)) | first // empty' "$CONFIG_FILE" 2>/dev/null)"

    [ -n "$tproxy_port" ] && TPROXY_PORT="$tproxy_port"
    [ -n "$dns_port" ] && DNS_PORT="$dns_port"
    [ -z "$DNS_REDIR_PORT" ] && DNS_REDIR_PORT="$DNS_PORT"
}

ensure_sbx_group(){
    if getent group "$SBX_GROUP" >/dev/null 2>&1; then
        return
    fi

    if command -v groupadd >/dev/null 2>&1; then
        groupadd -g "$SBX_GID" "$SBX_GROUP" 2>/dev/null || groupadd "$SBX_GROUP"
    else
        echo "$SBX_GROUP:x:$SBX_GID:" >> /etc/group
    fi
}

get_lan_ipv4(){
    LAN_IPV4="$(ip route show scope link | grep -Ev 'wan|utun|iot|docker|podman|virbr|vnet|ovs|vmbr|veth|vmnic|vboxnet|lxcbr|xenbr|vEthernet|linkdown' | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')"
    [ -z "$LAN_IPV4" ] && LAN_IPV4="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"

    LOCAL_IPV4="$(ip route 2>/dev/null | grep -Ev 'utun|iot|docker|linkdown' | grep -Eo 'src [0-9.]+' | awk '{print $2}' | sort -u | tr '\n' ' ' | sed 's/ $//')"
    [ -z "$LOCAL_IPV4" ] && LOCAL_IPV4="127.0.0.0/8"

    RESERVED_IPV4="0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 100.64.0.0/10 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4"
    DNS_RESERVED_IPV4="10.0.0.0/8 127.0.0.0/8 100.64.0.0/10 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16"
}

csv_from_words(){
    echo "$1" | awk '{for(i=1;i<=NF;i++){printf "%s%s", sep, $i; sep=", "}}'
}

prepare_singbox_route_config(){
    load_route_config
    get_lan_ipv4

    command -v jq >/dev/null 2>&1 || {
        warn "未找到 jq，跳过 sing-box 配置防回环修正"
        return 0
    }

    [ -f "$CONFIG_FILE" ] || {
        warn "未找到配置文件：$CONFIG_FILE"
        return 0
    }

    local tmp
    tmp="/tmp/sbx-config-route-$$.json"

    jq \
        --argjson routing_mark "$ROUTING_MARK" \
        --arg tun_name "$TUN_NAME" \
        --arg lan_ipv4 "$LAN_IPV4" \
        --arg dns_reserved_ipv4 "$DNS_RESERVED_IPV4" \
        '
        def words: split(" ") | map(select(length > 0));

        .route = (.route // {}) |
        .route.default_mark = $routing_mark |
        .route.auto_detect_interface = false |
        .outbounds = (
          (if (.outbounds? | type) == "array" then .outbounds else [] end)
          | map(select(.tag != "sbx-lan-dns-direct" and .tag != "sbx-private-dns-block"))
          + [
            {type: "direct", tag: "sbx-lan-dns-direct"},
            {type: "block", tag: "sbx-private-dns-block"}
          ]
        ) |
        .route.rules = (
          [
            {ip_cidr: ($lan_ipv4 | words), port: 53, outbound: "sbx-lan-dns-direct"},
            {ip_cidr: ($dns_reserved_ipv4 | words), port: 53, outbound: "sbx-private-dns-block"}
          ]
          + (
            if (.route.rules? | type) == "array" then
              .route.rules | map(select(.outbound != "sbx-lan-dns-direct" and .outbound != "sbx-private-dns-block"))
            else []
            end
          )
        ) |
        if (.dns.servers? | type) == "array" then
          .dns.servers |= map(
            if (.type == "fakeip" or .type == "hosts") then .
            else . + {routing_mark: $routing_mark}
            end
          )
        else . end |
        if (.inbounds? | type) == "array" then
          .inbounds |= map(
            if .type == "tun" then
              . + {
                auto_route: false,
                strict_route: false,
                interface_name: (.interface_name // .device // $tun_name)
              }
            else . end
          )
        else . end
        ' "$CONFIG_FILE" > "$tmp" || {
            rm -f "$tmp"
            error "配置修正失败"
            return 1
        }

    if "$SINGBOX_BIN" check -c "$tmp" >/dev/null 2>&1; then
        cp "$CONFIG_FILE" "$CONFIG_BACKUP" 2>/dev/null
        mv "$tmp" "$CONFIG_FILE"
        ok "已应用 sing-box 防回环路由配置"
    else
        rm -f "$tmp"
        warn "修正后的配置未通过 sing-box check，保留原配置"
    fi
}

stop_sbx_route(){
    load_route_config

    if command -v nft >/dev/null 2>&1; then
        nft delete table inet sbx >/dev/null 2>&1
    fi

    if command -v iptables >/dev/null 2>&1; then
        iptables -w -t mangle -D PREROUTING -p tcp -j SBX_MARK >/dev/null 2>&1
        iptables -w -t mangle -D PREROUTING -p udp -j SBX_MARK >/dev/null 2>&1
        iptables -w -t nat -D PREROUTING -p tcp --dport 53 -j SBX_DNS >/dev/null 2>&1
        iptables -w -t nat -D PREROUTING -p udp --dport 53 -j SBX_DNS >/dev/null 2>&1

        iptables -w -t mangle -F SBX_MARK >/dev/null 2>&1
        iptables -w -t mangle -X SBX_MARK >/dev/null 2>&1
        iptables -w -t nat -F SBX_DNS >/dev/null 2>&1
        iptables -w -t nat -X SBX_DNS >/dev/null 2>&1
        iptables -w -D FORWARD -o "$TUN_NAME" -j ACCEPT >/dev/null 2>&1
    fi

    ip rule del fwmark "$FW_MARK" table "$ROUTE_TABLE" >/dev/null 2>&1
    ip route flush table "$ROUTE_TABLE" >/dev/null 2>&1
}

start_sbx_route(){
    load_route_config
    get_lan_ipv4
    ensure_sbx_group
    stop_sbx_route

    case "$ROUTE_MODE" in
        off|OFF|none)
            ok "路由劫持已关闭"
            return 0
            ;;
        tproxy|TProxy|TPROXY)
            ip route add local default dev lo table "$ROUTE_TABLE" 2>/dev/null || true
            ip rule add fwmark "$FW_MARK" table "$ROUTE_TABLE" 2>/dev/null || true
            ;;
        tun|TUN)
            local i
            i=1
            while ! ip link show "$TUN_NAME" >/dev/null 2>&1 && [ "$i" -le 20 ]; do
                sleep 1
                i=$((i + 1))
            done
            if ip link show "$TUN_NAME" >/dev/null 2>&1; then
                ip route add default dev "$TUN_NAME" table "$ROUTE_TABLE" 2>/dev/null || true
                ip rule add fwmark "$FW_MARK" table "$ROUTE_TABLE" 2>/dev/null || true
                iptables -w -I FORWARD -o "$TUN_NAME" -j ACCEPT 2>/dev/null || true
            else
                warn "未找到 TUN 接口 $TUN_NAME，跳过 tun 路由规则"
                return 1
            fi
            ;;
        *)
            error "未知路由模式：$ROUTE_MODE"
            return 1
            ;;
    esac

    if [ "$FIREWALL_BACKEND" = "nftables" ] && command -v nft >/dev/null 2>&1; then
        start_sbx_nft
    else
        start_sbx_iptables
    fi
}

start_sbx_nft(){
    local lan_ips reserved_ips dns_reserved_ips local_ips gid ports jump

    lan_ips="$(csv_from_words "$LAN_IPV4")"
    reserved_ips="$(csv_from_words "$RESERVED_IPV4")"
    dns_reserved_ips="$(csv_from_words "$DNS_RESERVED_IPV4")"
    local_ips="127.0.0.0/8"
    [ -n "$LOCAL_IPV4" ] && local_ips="$local_ips, $(csv_from_words "$LOCAL_IPV4")"
    gid="$(getent group "$SBX_GROUP" | awk -F: '{print $3}')"
    [ -z "$gid" ] && gid="$SBX_GID"
    ports="$(echo "$PROXY_PORTS" | sed 's/,/, /g')"

    modprobe nft_tproxy >/dev/null 2>&1 || true
    nft add table inet sbx

    nft add chain inet sbx prerouting { type filter hook prerouting priority -150 \; }
    nft add rule inet sbx prerouting tcp dport 53 return
    nft add rule inet sbx prerouting udp dport 53 return
    nft add rule inet sbx prerouting meta mark "$ROUTING_MARK" return
    nft add rule inet sbx prerouting meta skgid "$gid" return
    nft add rule inet sbx prerouting ip daddr { "$reserved_ips" } return
    nft add rule inet sbx prerouting ip saddr != { "$lan_ips" } return

    if [ "$COMMON_PORTS" = "ON" ]; then
        nft add rule inet sbx prerouting ip daddr != 28.0.0.0/8 tcp dport != { "$ports" } return
        nft add rule inet sbx prerouting ip daddr != 28.0.0.0/8 udp dport != { "$ports" } return
    fi

    if [ "$CN_IP_ROUTE" = "ON" ] && [ -s "$CN_IP_FILE" ]; then
        nft add set inet sbx cn_ip { type ipv4_addr \; flags interval \; }
        awk '{printf "%s, ", $1}' "$CN_IP_FILE" | sed 's/, $//' | while read -r cn_ip; do
            [ -n "$cn_ip" ] && nft add element inet sbx cn_ip { "$cn_ip" }
        done
        nft add rule inet sbx prerouting ip daddr @cn_ip return
    fi

    case "$ROUTE_MODE" in
        tproxy|TProxy|TPROXY)
            jump="meta l4proto { tcp, udp } mark set $FW_MARK tproxy to :$TPROXY_PORT"
            ;;
        tun|TUN)
            jump="meta l4proto { tcp, udp } mark set $FW_MARK"
            ;;
    esac

    nft add rule inet sbx prerouting $jump

    if [ "$DNS_REDIR_PORT" != "off" ] && [ -n "$DNS_REDIR_PORT" ]; then
        nft add chain inet sbx prerouting_dns { type nat hook prerouting priority -100 \; }
        nft add rule inet sbx prerouting_dns meta mark "$ROUTING_MARK" return
        nft add rule inet sbx prerouting_dns meta skgid "$gid" return
        nft add rule inet sbx prerouting_dns ip saddr != { "$lan_ips" } return
        nft add rule inet sbx prerouting_dns ip daddr { "$dns_reserved_ips" } return
        nft add rule inet sbx prerouting_dns udp dport 53 redirect to "$DNS_REDIR_PORT"
        nft add rule inet sbx prerouting_dns tcp dport 53 redirect to "$DNS_REDIR_PORT"
    fi

    ok "nftables 路由规则已应用：$ROUTE_MODE"
}

start_sbx_iptables(){
    local ip gid

    modprobe xt_TPROXY >/dev/null 2>&1 || true
    gid="$(getent group "$SBX_GROUP" | awk -F: '{print $3}')"
    [ -z "$gid" ] && gid="$SBX_GID"

    iptables -w -t mangle -N SBX_MARK
    iptables -w -t mangle -A SBX_MARK -p tcp --dport 53 -j RETURN
    iptables -w -t mangle -A SBX_MARK -p udp --dport 53 -j RETURN
    iptables -w -t mangle -A SBX_MARK -m mark --mark "$ROUTING_MARK" -j RETURN

    for ip in $LAN_IPV4; do
        iptables -w -t mangle -A SBX_MARK ! -s "$ip" -j RETURN
    done

    for ip in $RESERVED_IPV4; do
        iptables -w -t mangle -A SBX_MARK -d "$ip" -j RETURN
    done

    if [ "$COMMON_PORTS" = "ON" ]; then
        iptables -w -t mangle -A SBX_MARK -p tcp ! -d 28.0.0.0/8 -m multiport ! --dports "$PROXY_PORTS" -j RETURN
        iptables -w -t mangle -A SBX_MARK -p udp ! -d 28.0.0.0/8 -m multiport ! --dports "$PROXY_PORTS" -j RETURN
    fi

    case "$ROUTE_MODE" in
        tproxy|TProxy|TPROXY)
            iptables -w -t mangle -A SBX_MARK -p tcp -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$FW_MARK"
            iptables -w -t mangle -A SBX_MARK -p udp -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$FW_MARK"
            ;;
        tun|TUN)
            iptables -w -t mangle -A SBX_MARK -p tcp -j MARK --set-mark "$FW_MARK"
            iptables -w -t mangle -A SBX_MARK -p udp -j MARK --set-mark "$FW_MARK"
            ;;
    esac

    iptables -w -t mangle -I PREROUTING -p tcp -j SBX_MARK
    iptables -w -t mangle -I PREROUTING -p udp -j SBX_MARK

    if [ "$DNS_REDIR_PORT" != "off" ] && [ -n "$DNS_REDIR_PORT" ]; then
        iptables -w -t nat -N SBX_DNS
        iptables -w -t nat -A SBX_DNS -m mark --mark "$ROUTING_MARK" -j RETURN
        for ip in $DNS_RESERVED_IPV4; do
            iptables -w -t nat -A SBX_DNS -d "$ip" -j RETURN
        done
        for ip in $LAN_IPV4; do
            iptables -w -t nat -A SBX_DNS -s "$ip" -p tcp -j REDIRECT --to-ports "$DNS_REDIR_PORT"
            iptables -w -t nat -A SBX_DNS -s "$ip" -p udp -j REDIRECT --to-ports "$DNS_REDIR_PORT"
        done
        iptables -w -t nat -I PREROUTING -p tcp --dport 53 -j SBX_DNS
        iptables -w -t nat -I PREROUTING -p udp --dport 53 -j SBX_DNS
    fi

    ok "iptables 路由规则已应用：$ROUTE_MODE"
}

show_route_status(){
    load_route_config

    echo
    echo "========== SBX route config =========="
    echo "ROUTE_MODE=$ROUTE_MODE"
    echo "FIREWALL_BACKEND=$FIREWALL_BACKEND"
    echo "ROUTE_SCOPE=$ROUTE_SCOPE"
    echo "FW_MARK=$FW_MARK"
    echo "ROUTE_TABLE=$ROUTE_TABLE"
    echo "ROUTING_MARK=$ROUTING_MARK"
    echo "TPROXY_PORT=$TPROXY_PORT"
    echo "DNS_REDIR_PORT=$DNS_REDIR_PORT"
    echo "TUN_NAME=$TUN_NAME"

    echo
    echo "========== ip rule =========="
    ip rule show | grep -E "fwmark.*$ROUTE_TABLE|$ROUTE_TABLE" || true

    echo
    echo "========== route table $ROUTE_TABLE =========="
    ip route show table "$ROUTE_TABLE" || true

    echo
    echo "========== nft table inet sbx =========="
    nft list table inet sbx 2>/dev/null || true

    echo
    echo "========== iptables SBX =========="
    iptables -w -t mangle -S SBX_MARK 2>/dev/null || true
    iptables -w -t nat -S SBX_DNS 2>/dev/null || true
}

save_route_mode(){
    local mode
    mode="$1"

    if grep -q '^ROUTE_MODE=' "$route_config_file" 2>/dev/null; then
        sed -i "s/^ROUTE_MODE=.*/ROUTE_MODE=\"$mode\"/" "$route_config_file"
    else
        printf '\nROUTE_MODE="%s"\n' "$mode" >> "$route_config_file"
    fi

    ROUTE_MODE="$mode"
}

choose_route_mode(){
    local allow_return mode

    allow_return="$1"
    load_route_config

    while true
    do
    clear
    cat <<EOF

================================
        切换路由模式
================================

当前模式：$ROUTE_MODE

1. off

2. tproxy

3. tun

EOF

    if [ "$allow_return" = "yes" ]; then
        echo "0. 返回"
        echo
    fi

    cat <<EOF

================================

EOF

    read -p "请选择：" NUM

    case "$NUM" in
        1)
            mode="off"
            ;;
        2)
            mode="tproxy"
            ;;
        3)
            mode="tun"
            ;;
        0)
            if [ "$allow_return" = "yes" ]; then
                return 1
            fi
            warn "请选择安装后使用的路由模式"
            pause
            continue
            ;;
        *)
            warn "输入错误"
            pause
            continue
            ;;
    esac

    save_route_mode "$mode"
    ok "路由模式已设置为：$ROUTE_MODE"
    return 0
    done
}

set_route_mode(){
    if choose_route_mode "yes"; then
        if command -v select_config_url_for_mode >/dev/null 2>&1; then
            select_config_url_for_mode
            update_config
        fi
        sync_resolved_for_route_mode "$ROUTE_MODE"
        info "正在重启 Sing-box，并重新应用路由规则..."
        if systemctl restart sing-box; then
            ok "路由模式、DNS 和 Sing-box 已同步生效：$ROUTE_MODE"
        else
            error "Sing-box 重启失败，请执行：journalctl -u sing-box -n 50 --no-pager"
        fi
    fi
    pause
}

configure_route_mode_after_install(){
    choose_route_mode "no" || return

    if command -v prepare_singbox_route_config >/dev/null 2>&1; then
        prepare_singbox_route_config
    fi

    if command -v select_config_url_for_mode >/dev/null 2>&1; then
        select_config_url_for_mode
        update_config
    fi

    sync_resolved_for_route_mode "$ROUTE_MODE"

    info "Sing-box 服务启动时会按 $ROUTE_MODE 应用对应路由和防火墙规则"
    pause
}

route_menu(){
while true
do
load_route_config
clear
cat <<EOF

================================
        路由设置
================================

当前模式：$ROUTE_MODE

1. 应用路由规则

2. 清理路由规则

3. 修正 sing-box 防回环配置

4. 查看路由状态

5. 切换路由模式

0. 返回

================================

EOF

read -p "请选择：" NUM

case "$NUM" in
1)
start_sbx_route
pause
;;
2)
stop_sbx_route
ok "路由规则已清理"
pause
;;
3)
prepare_singbox_route_config
pause
;;
4)
show_route_status
pause
;;
5)
set_route_mode
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

route_cli(){
    case "$1" in
        start)
            start_sbx_route
            ;;
        stop)
            stop_sbx_route
            ;;
        restart)
            stop_sbx_route
            start_sbx_route
            ;;
        prepare-config)
            prepare_singbox_route_config
            ;;
        sync-dns)
            sync_resolved_for_route_mode "$ROUTE_MODE"
            ;;
        status)
            show_route_status
            ;;
        *)
            echo "Usage: sbx-route [start|stop|restart|prepare-config|sync-dns|status]"
            return 1
            ;;
    esac
}
