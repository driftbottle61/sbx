#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
END="\033[0m"

info() {
    echo -e "${BLUE}[INFO]${END} $1"
}

ok() {
    echo -e "${GREEN}[ OK ]${END} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${END} $1"
}

error() {
    echo -e "${RED}[FAIL]${END} $1"
}

setup_download_proxy() {
    [ "${SBX_DOWNLOAD_PROXY_READY:-0}" = "1" ] && return 0

    local proxy="${SBX_DOWNLOAD_PROXY:-}"
    local probe_url="${SBX_PROXY_PROBE_URL:-https://www.gstatic.com/generate_204}"

    if [ "$proxy" = "off" ] || [ "$proxy" = "direct" ]; then
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
        export SBX_DOWNLOAD_PROXY_READY=1
        info "下载使用直连"
        return 0
    fi

    if [ -z "$proxy" ] && curl -fsS --proxy "http://127.0.0.1:8080" \
        --connect-timeout 3 --max-time 6 "$probe_url" >/dev/null 2>&1; then
        proxy="http://127.0.0.1:8080"
    fi

    if [ -n "$proxy" ]; then
        export http_proxy="$proxy"
        export https_proxy="$proxy"
        export HTTP_PROXY="$proxy"
        export HTTPS_PROXY="$proxy"
        export no_proxy="${no_proxy:-127.0.0.1,localhost,::1}"
        export NO_PROXY="$no_proxy"
        info "下载代理：$proxy"
    else
        info "未检测到下载代理，使用直连"
    fi

    export SBX_DOWNLOAD_PROXY_READY=1
}

sbx_curl() {
    setup_download_proxy
    curl --fail --location --retry 2 --retry-delay 1 \
        --connect-timeout 15 --max-time "${SBX_DOWNLOAD_TIMEOUT:-300}" "$@"
}

sbx_wget() {
    setup_download_proxy
    wget --timeout=15 --read-timeout=30 --tries=2 "$@"
}

pause() {
    echo
    read -p "按回车继续..."
}

root_check() {

    if [ "$EUID" != 0 ]; then

        error "请使用 root 运行"

        exit 1

    fi

}
