#!/bin/bash

dashboard() {

[ "${DASHBOARD_DRAWN:-0}" = "1" ] && return 0

if command -v load_config >/dev/null 2>&1; then
    load_config
fi

[ -z "$ROUTE_MODE" ] && ROUTE_MODE="tproxy"

#########################
# 主机信息
#########################

HOSTNAME=$(hostname)

OS=$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f2)

KERNEL=$(uname -r)

IP=$(hostname -I | awk '{print $1}')

CPU_MODEL=$(lscpu | awk '
/Model name:/{
    sub(/Model name:[[:space:]]*/, "")
    printf "%s", $0
    getline
    if ($0 ~ /^[[:space:]]+/)
        printf " %s", $0
}' | sed 's/pc-q35.*//')

CPU_CORE=$(nproc)

MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')

MEM_USED=$(free -h | awk '/Mem:/ {print $3}')

UPTIME=$(uptime -p | sed 's/up //')

#########################
# 虚拟化
#########################

if command -v systemd-detect-virt >/dev/null 2>&1; then

    VIRT=$(systemd-detect-virt)

    [ "$VIRT" = "none" ] && VIRT="物理机"

else

    VIRT="未知"

fi

#########################
# Sing-box 状态
#########################

if systemctl is-active --quiet sing-box; then
    STATUS="🟢 Running"
else
    STATUS="🔴 Stopped"
fi

#########################
# 开机启动
#########################

if systemctl is-enabled sing-box >/dev/null 2>&1; then
    ENABLE="√ 已启用"
else
    ENABLE="× 未启用"
fi

#########################
# 版本
#########################

if [ -x "$SINGBOX_BIN" ]; then

    VERSION=$($SINGBOX_BIN version | head -1 | awk '{print $3}')
    VERSION="v${VERSION#v}"

else

    VERSION="未安装"

fi

# Fetch the latest stable upstream release for comparison.  A dashboard
# refresh must remain usable when GitHub is unavailable, so this is best effort.
LATEST_VERSION="${SINGBOX_LATEST_VERSION_CACHE:-未知}"
now_epoch=$(date +%s)
cache_epoch=${SINGBOX_LATEST_VERSION_CACHE_EPOCH:-0}
if [ "$LATEST_VERSION" = "未知" ] || [ $((now_epoch - cache_epoch)) -ge 21600 ]; then
  LATEST_VERSION="未知"
fi

SBX_CURRENT_VERSION="${SBX_VERSION:-未知}"
[ "$SBX_CURRENT_VERSION" = "未知" ] || SBX_CURRENT_VERSION="v${SBX_CURRENT_VERSION#v}"
SBX_LATEST_VERSION="${SBX_LATEST_VERSION_CACHE:-未知}"
sbx_latest_cache_epoch=${SBX_LATEST_VERSION_CACHE_EPOCH:-0}
if [ "$SBX_LATEST_VERSION" = "未知" ] || [ $((now_epoch - sbx_latest_cache_epoch)) -ge 21600 ]; then
  SBX_LATEST_VERSION="未知"
fi
if [ "$SBX_LATEST_VERSION" = "未知" ] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    if command -v setup_download_proxy >/dev/null 2>&1; then
        setup_download_proxy >/dev/null 2>&1 || true
    fi
    SBX_LATEST_VERSION=$(curl -fsSL --connect-timeout 2 --max-time 4 \
        'https://api.github.com/repos/driftbottle61/sbx/releases?per_page=100' 2>/dev/null \
        | jq -r '.[] | select(.draft == false and .prerelease == false) | .tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))' 2>/dev/null \
        | sort -V | tail -n1)
    [ -n "$SBX_LATEST_VERSION" ] || SBX_LATEST_VERSION="未知"
    [ "$SBX_LATEST_VERSION" = "未知" ] || SBX_LATEST_VERSION="v${SBX_LATEST_VERSION#v}"
    if [ "$SBX_LATEST_VERSION" != "未知" ]; then
        SBX_LATEST_VERSION_CACHE="$SBX_LATEST_VERSION"
        SBX_LATEST_VERSION_CACHE_EPOCH="$now_epoch"
    fi
fi

SBX_UPDATE_AVAILABLE=0
if [ "$SBX_CURRENT_VERSION" != "未知" ] && [ "$SBX_LATEST_VERSION" != "未知" ] \
    && [ "$(printf '%s\n' "${SBX_CURRENT_VERSION#v}" "${SBX_LATEST_VERSION#v}" | sort -V | tail -1)" != "${SBX_CURRENT_VERSION#v}" ]; then
    SBX_UPDATE_AVAILABLE=1
fi
if [ "$LATEST_VERSION" = "未知" ] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    # Initialize the configured download proxy silently for the GitHub query.
    if command -v setup_download_proxy >/dev/null 2>&1; then
        setup_download_proxy >/dev/null 2>&1 || true
    fi
    LATEST_VERSION=$(curl -fsSL --connect-timeout 2 --max-time 4 \
        https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null \
        | jq -r '.tag_name // empty' 2>/dev/null)
    # sing-box may still be bringing up the local proxy during startup. Retry
    # proxy discovery once when the first GitHub request fails.
    if [ -z "$LATEST_VERSION" ] && command -v setup_download_proxy >/dev/null 2>&1; then
        unset SBX_DOWNLOAD_PROXY_READY
        setup_download_proxy >/dev/null 2>&1 || true
        LATEST_VERSION=$(curl -fsSL --connect-timeout 3 --max-time 6 \
            https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null \
            | jq -r '.tag_name // empty' 2>/dev/null)
    fi
    [ -n "$LATEST_VERSION" ] || LATEST_VERSION="未知"
    [ "$LATEST_VERSION" = "未知" ] || LATEST_VERSION="v${LATEST_VERSION#v}"
    if [ "$LATEST_VERSION" != "未知" ]; then
        SINGBOX_LATEST_VERSION_CACHE="$LATEST_VERSION"
        SINGBOX_LATEST_VERSION_CACHE_EPOCH="$now_epoch"
    fi
fi

#########################
# 配置
#########################

if [ -f "$CONFIG_FILE" ]; then
    CONFIG="√ 已加载"
else
    CONFIG="× 未找到"
fi

#########################
# CPU
#########################

CPU_USE=$(ps -C sing-box -o %cpu= | awk '{sum+=$1} END{printf "%.1f",sum}')

[ -z "$CPU_USE" ] && CPU_USE="0"

#########################
# 内存
#########################

MEM_USE=$(ps -C sing-box -o rss= | awk '{sum+=$1} END{printf "%.1f",sum/1024}')

[ -z "$MEM_USE" ] && MEM_USE="0"

#########################
# 启动时间
#########################

START_TIME=$(systemctl show sing-box \
-p ActiveEnterTimestamp \
--value)

#########################
# 网络环境检测
#########################

# TUN检测

if [ -c /dev/net/tun ]; then
    TUN_STATUS="√ Enabled"
else
    TUN_STATUS="× Disabled"
fi


# IP Forward

IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)

if [ "$IP_FORWARD" = "1" ]; then
    FORWARD_STATUS="√ Enabled"
else
    FORWARD_STATUS="× Disabled"
fi


# Clash API

if ss -lnt | grep -q ":9095"; then
    CLASH_API="√ 9095"
else
    CLASH_API="× 未监听"
fi


# Zashboard

if [ -f /etc/singbox/ui/index.html ]; then
    ZASHBOARD="√ Installed"
else
    ZASHBOARD="× 未安装"
fi


# 配置链接

if [ -n "$CONFIG_URL" ]; then
    CONFIG_URL_STATUS="√ 已设置"
else
    CONFIG_URL_STATUS="× 未设置"
fi


# 网络检测

if ping -c 1 -W 1 223.5.5.5 >/dev/null 2>&1; then
    NETWORK="√ Online"
else
    NETWORK="× Offline"
fi


#########################

clear

CPU_DISPLAY=$(printf '%10.1f' "$CPU_USE")
MEM_DISPLAY=$(printf '%10.1f' "$MEM_USE")

CPU_MODEL_SHORT=$(printf '%s' "$CPU_MODEL" | grep -oE 'i[0-9]-[0-9]+[A-Za-z]*' | head -1)
[ -z "$CPU_MODEL_SHORT" ] && CPU_MODEL_SHORT=$(printf '%s' "$CPU_MODEL" | cut -c1-28)
OS_SHORT=$(printf '%s' "$OS" | cut -c1-20)
UPTIME_SHORT=$(printf '%s' "$UPTIME" | cut -d',' -f1)
cat <<EOF

======================================================================
 SBX ${SBX_CURRENT_VERSION}  |  Sing-box ${VERSION}  |  最新 ${LATEST_VERSION}
======================================================================
 主机 : ${HOSTNAME}  |  ${OS_SHORT}  |  内核 ${KERNEL}  |  ${VIRT}
 CPU  : ${CPU_MODEL_SHORT}  |  ${CPU_CORE} 核  |  内存 ${MEM_USED}/${MEM_TOTAL}
 IP   : ${IP}  |  运行 ${UPTIME_SHORT}
----------------------------------------------------------------------
 服务 : ${STATUS}  |  开机 ${ENABLE}  |  配置 ${CONFIG}  |  ${ROUTE_MODE}
 负载 : CPU ${CPU_DISPLAY}%  |  内存 ${MEM_DISPLAY} MB  |  网络 ${NETWORK}
 功能 : TUN ${TUN_STATUS}  |  转发 ${FORWARD_STATUS}  |  Clash ${CLASH_API}
 面板 : Zashboard ${ZASHBOARD}  |  配置链接 ${CONFIG_URL_STATUS}
 版本 : SBX ${SBX_CURRENT_VERSION}  |  最新 ${SBX_LATEST_VERSION}
----------------------------------------------------------------------
 1. 安装/升级 Sing-box    2. 配置管理    3. 运行管理
 4. 路由设置              5. 工具箱      6. Web 面板
 7. 更新 SBX 管理器       0. 退出
======================================================================

EOF

DASHBOARD_DRAWN=1

}

# Refresh the dashboard using the current metrics.
refresh_dashboard_metrics(){
    DASHBOARD_DRAWN=0
    DASHBOARD_PROMPT_DRAWN=0
    dashboard
}
