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
        systemctl daemon-reload
        restart_service
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            ok "Sing-box 已覆盖更新并重启"
        else
            error "Sing-box 覆盖更新后启动失败"
            journalctl -u "$SERVICE_NAME" -n 50 --no-pager
        fi
        pause
    fi
}

update_sbx() {
    local current_version="${SBX_VERSION:-未知}" latest_version="${SBX_LATEST_VERSION:-未知}" installer

    if [ "$latest_version" = "未知" ]; then
        warn "无法获取 SBX 最新版本，请检查网络连接"
        pause
        return
    fi
    if [ "$current_version" != "未知" ] && [ "$(printf '%s\n' "${current_version#v}" "${latest_version#v}" | sort -V | tail -1)" = "${current_version#v}" ]; then
        ok "SBX 已是最新版本：$current_version"
        pause
        return
    fi

    echo
    echo "当前 SBX 版本：$current_version"
    echo "最新 SBX 版本：$latest_version"
    read -r -p "确认更新 SBX 管理器？[y/N]：" answer
    case "${answer,,}" in
        y|yes) ;;
        *) info "已取消更新"; return ;;
    esac

    info "正在下载并安装 SBX $latest_version..."
    installer=$(mktemp /tmp/sbx-update.XXXXXX)
    if sbx_curl -fsSL https://raw.githubusercontent.com/driftbottle61/sbx/main/install.sh \
        -o "$installer" && bash "$installer" --skip-deps --ref "$latest_version"; then
        ok "SBX 更新完成，请重新进入管理器"
    else
        error "SBX 更新失败，原安装和配置应保持不变"
    fi
    rm -f "$installer"
    pause
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
        systemctl daemon-reload
        restart_service
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            ok "Sing-box 已覆盖更新并重启"
        else
            error "Sing-box 覆盖更新后启动失败"
            journalctl -u "$SERVICE_NAME" -n 50 --no-pager
        fi
        pause
    fi
}

# Complete the interactive first-install flow. Upgrades do not enter this
# function, so existing subscriptions and service settings remain untouched.
first_install_setup(){
    local enable_boot="" tproxy_url tun_url

    echo
    echo "首次安装向导"
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

    read -r -p "是否设置 sing-box 开机自动启动？[Y/n]：" enable_boot
    case "${enable_boot,,}" in
        n|no) info "稍后可在服务管理中启用开机启动" ;;
        *) enable_boot="yes" ;;
    esac

    # Route preparation must happen before the unit is generated.
    create_service

    update_config

    if [ "$enable_boot" = "yes" ]; then
        enable_service
    else
        disable_service
    fi

    systemctl daemon-reload
    restart_service
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        ok "Sing-box systemd 服务已启动"
    else
        error "Sing-box systemd 服务启动失败"
        journalctl -u "$SERVICE_NAME" -n 50 --no-pager
        return 1
    fi
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
