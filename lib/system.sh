#!/bin/bash

########################################
# 系统检测
########################################

check_system() {

    info "检测系统..."

    if [ ! -f /etc/os-release ]; then
        error "无法识别系统"
        return 1
    fi

    . /etc/os-release

    case "$ID" in
        ubuntu|debian)
            ok "系统：$PRETTY_NAME"
            ;;
        *)
            error "目前仅支持 Ubuntu / Debian"
            return 1
            ;;
    esac

    return 0
}

########################################
# 安装依赖
########################################

install_dependencies(){

    info "更新软件源..."

    apt update

    info "安装依赖..."

    apt install -y \
        curl \
        wget \
        jq \
        unzip \
        tar \
        iproute2 \
        iptables \
        nftables \
        ca-certificates \
        systemd \
        lsb-release \
        net-tools \
        dnsutils \
        iputils-ping

    ok "依赖安装完成"

}

########################################
# 创建目录
########################################

create_directory(){

    mkdir -p /etc/sing-box
    mkdir -p /etc/singbox/ui

    mkdir -p /var/lib/sing-box

    mkdir -p /opt/sbx

    mkdir -p /opt/sbx/backup

    mkdir -p /opt/sbx/log

    ok "目录创建完成"

}

########################################
# 开启转发
########################################

enable_forward(){

    info "开启 IP Forward..."

    cat >/etc/sysctl.d/99-sbx.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1

net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0

net.ipv4.conf.all.accept_local=1
net.ipv4.conf.default.accept_local=1
EOF

    sysctl --system >/dev/null

    ok "IP Forward 已开启"

}

########################################
# 检测TUN
########################################

check_tun(){

    info "检测 TUN..."

    if [ ! -c /dev/net/tun ]; then
        error "/dev/net/tun 不存在"
        return
    fi

    ok "TUN 可用"

}

########################################
# Ubuntu DNS优化
########################################

optimize_dns(){

    info "优化 Ubuntu DNS..."

    mkdir -p /opt/sbx/backup

    if [ ! -f /opt/sbx/backup/resolv.conf.bak ]; then

        cp /etc/resolv.conf \
        /opt/sbx/backup/resolv.conf.bak 2>/dev/null

    fi

    systemctl disable systemd-resolved --now

    rm -f /etc/resolv.conf

cat >/etc/resolv.conf <<EOF
nameserver 223.5.5.5
nameserver 1.1.1.1
EOF

    ok "DNS 优化完成"

}

########################################
# 恢复Ubuntu默认DNS
########################################

restore_dns(){

    info "恢复 Ubuntu 默认 DNS..."

    rm -f /etc/resolv.conf

    ln -s \
    /run/systemd/resolve/stub-resolv.conf \
    /etc/resolv.conf

    systemctl enable systemd-resolved

    systemctl restart systemd-resolved

    ok "DNS 已恢复"

}

########################################
# 查看DNS
########################################

show_dns(){

    echo

    echo "========== resolv.conf =========="

    cat /etc/resolv.conf

    echo

    echo "========== resolvectl =========="

    resolvectl status

}

# Keep systemd-resolved aligned with the selected sing-box route mode.
# TUN publishes a DNS link on utun; TProxy must never leave that link as the
# default DNS route, otherwise local applications keep querying the old TUN
# endpoint after a mode switch.
sync_resolved_for_route_mode(){
    local mode="${1:-$ROUTE_MODE}" lan_if lan_dns

    command -v resolvectl >/dev/null 2>&1 || return 0
    lan_if="$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')"
    [ -z "$lan_if" ] && lan_if="$(ip -o -4 addr show scope global 2>/dev/null | awk '$2 !~ /utun|docker|veth/ {print $2; exit}')"

    # Capture the configured LAN DNS before reverting the link. If none is
    # available, use the LAN gateway as a conservative local resolver.
    lan_dns="$(resolvectl dns "$lan_if" 2>/dev/null | sed -n 's/.*: //p' | awk '{print $1}')"
    if [ -z "$lan_dns" ]; then
        lan_dns="$(ip route show default 2>/dev/null | awk 'NR==1 {print $3}')"
    fi

    case "$mode" in
        tun|TUN)
            # Do not force the system resolver through 172.19.0.2. In an
            # unprivileged LXC the TUN DNS endpoint may be unavailable; keep
            # DNS on the LAN resolver while sing-box handles proxied traffic.
            resolvectl revert utun >/dev/null 2>&1 || true
            if [ -n "$lan_if" ] && [ -n "$lan_dns" ]; then
                resolvectl dns "$lan_if" $lan_dns >/dev/null 2>&1 || true
                resolvectl domain "$lan_if" '~.' >/dev/null 2>&1 || true
            fi
            ;;
        tproxy|TProxy|TPROXY|off|OFF|none)
            resolvectl revert utun >/dev/null 2>&1 || true
            if [ -n "$lan_if" ] && [ -n "$lan_dns" ]; then
                resolvectl dns "$lan_if" $lan_dns >/dev/null 2>&1 || true
                resolvectl domain "$lan_if" '~.' >/dev/null 2>&1 || true
            fi
            ;;
    esac
    systemctl restart systemd-resolved >/dev/null 2>&1 || true
}

########################################
# 查看路由
########################################

show_route(){

    echo

    ip route

    echo

    ip rule

}

########################################
# 查看TUN
########################################

show_tun(){

    echo

    ip addr show utun 2>/dev/null

}

########################################
# 环境初始化
########################################

system_init(){

    check_system || return

    install_dependencies

    create_directory

    enable_forward

    optimize_dns

    check_tun

    ok "系统初始化完成"

}

########################################
# 系统菜单
########################################

system_menu(){

while true
do

clear

cat <<EOF

=========================================
            系统设置
=========================================

1. 环境初始化（推荐）

2. 安装系统依赖

3. 开启 IP Forward

4. Ubuntu DNS 优化

5. 恢复 Ubuntu 默认 DNS

6. 查看 DNS 状态

7. 查看路由状态

8. 查看 TUN 状态

0. 返回

=========================================

EOF

read -p "请选择：" NUM

case "$NUM" in

1)

system_init
pause
;;

2)

install_dependencies
pause
;;

3)

enable_forward
pause
;;

4)

optimize_dns
pause
;;

5)

restore_dns
pause
;;

6)

show_dns
pause
;;

7)

show_route
pause
;;

8)

show_tun
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
