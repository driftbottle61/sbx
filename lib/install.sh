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

    create_service

    if command -v configure_route_mode_after_install >/dev/null 2>&1; then
        configure_route_mode_after_install
    fi

    pause
}

install_custom() {
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
    create_service

    if command -v configure_route_mode_after_install >/dev/null 2>&1; then
        configure_route_mode_after_install
    fi

    enable_service

    restart_service

    pause
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
