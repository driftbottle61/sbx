#!/bin/bash

# 安装模块

get_arch() {

    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            error "暂不支持架构：$(uname -m)"
            return 1
            ;;
    esac
}

show_current_version() {

    echo

    if [ -x "$SINGBOX_BIN" ]; then

        info "当前已安装版本："

        "$SINGBOX_BIN" version

    else

        warn "未安装 sing-box"

    fi

    pause
}

install_dependencies() {

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
        ca-certificates

    ok "依赖安装完成"
}

download_release() {

    VERSION="$1"

    get_arch || return 1

    URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION#v}-linux-${ARCH}.tar.gz"

    info "下载："

    echo "$URL"

    sbx_wget -O /tmp/sing-box.tar.gz "$URL"

    if [ $? -ne 0 ]; then
        error "下载失败"
        return 1
    fi

    return 0
}

install_binary() {

    rm -rf /tmp/sbx-install

    mkdir -p /tmp/sbx-install

    tar -xf /tmp/sing-box.tar.gz \
        -C /tmp/sbx-install

    install -m 755 \
        /tmp/sbx-install/*/sing-box \
        "$SINGBOX_BIN"

    ok "安装完成"

}

install_latest() {
    local fresh_install=0
    [ -x "$SINGBOX_BIN" ] || fresh_install=1
    check_system || return
    install_dependencies
    create_directory
    enable_forward
    check_tun

    info "获取最新版本..."

    VERSION=$(sbx_curl -s \
        https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | jq -r '.tag_name')

    if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
        error "获取版本失败"
        pause
        return
    fi

    echo
    echo "最新版本：$VERSION"

    download_release "$VERSION" || {
        pause
        return
    }

    install_binary
    if [ "$fresh_install" -eq 1 ]; then
        first_install_setup
    else
        create_service
        prepare_singbox_route_config
        restart_service
        ok "Sing-box 已覆盖更新并重启"
        pause
    fi
}

install_custom() {
    local fresh_install=0
    [ -x "$SINGBOX_BIN" ] || fresh_install=1
    check_system || return
    install_dependencies
    create_directory
    enable_forward
    check_tun

    echo

    read -p "请输入版本号(例如1.13.14)： " VERSION

    [ -z "$VERSION" ] && return

    [[ "$VERSION" != v* ]] && VERSION="v$VERSION"

    download_release "$VERSION" || {
        pause
        return
    }

    install_binary
    if [ "$fresh_install" -eq 1 ]; then
        first_install_setup
    else
        create_service
        prepare_singbox_route_config
        restart_service
        ok "Sing-box 已覆盖更新并重启"
        pause
    fi
}

# Complete the interactive first-install flow. Upgrades do not enter this
# function, so existing subscriptions and service settings remain untouched.
first_install_setup(){
    local enable_boot="" tproxy_url tun_url

    echo
    echo "首次安装向导"
    read -r -p "是否设置 sing-box 开机自动启动？[Y/n]：" enable_boot
    case "${enable_boot,,}" in
        n|no)
            info "稍后可在服务管理中启用开机启动"
            ;;
        *)
            enable_boot="yes"
            ;;
    esac

    echo
    read -r -p "请输入 TProxy 配置 URL：" tproxy_url
    read -r -p "请输入 TUN 配置 URL：" tun_url
    if [ -z "$tproxy_url" ] || [ -z "$tun_url" ]; then
        warn "两条配置 URL 都不能为空"
        return 1
    fi
    set_config_urls "$tproxy_url" "$tun_url"

    if command -v configure_route_mode_after_install >/dev/null 2>&1; then
        configure_route_mode_after_install
    fi

    # Route preparation must happen before the unit is generated.
    create_service

    update_config

    if [ "$enable_boot" = "yes" ]; then
        enable_service
    fi
    restart_service
    ok "首次安装配置完成，正在进入 SBX 状态面板"
}

show_release_list() {

    echo

    info "最近20个版本"

    sbx_curl -s \
    https://api.github.com/repos/SagerNet/sing-box/releases \
    | jq -r '.[].tag_name' \
    | head -20

    pause
}

install_menu() {

while true
do

clear

cat <<EOF

=============================
      Sing-box 安装管理
=============================

1. 安装最新版

2. 安装指定版本

3. 查看最近20个版本

4. 查看当前版本

0. 返回

=============================

EOF

read -p "请选择：" NUM

case "$NUM" in

1)

install_latest

;;

2)

install_custom

;;

3)

show_release_list

;;

4)

show_current_version

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
