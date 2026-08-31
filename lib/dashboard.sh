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
LATEST_VERSION="未知"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
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

cat <<EOF

======================================================================
                         SBX ${SBX_VERSION}
                 Sing-box Manager for Linux Server
======================================================================

【系统信息】

 主机名称      : ${HOSTNAME}
 操作系统      : ${OS}
 内核版本      : ${KERNEL}
 虚拟化        : ${VIRT}
 CPU           : ${CPU_MODEL}
 CPU核心       : ${CPU_CORE}
 内存          : ${MEM_USED} / ${MEM_TOTAL}
 IP地址        : ${IP}
 系统运行      : ${UPTIME}

----------------------------------------------------------------------

【Sing-box】

 服务状态      : ${STATUS}
 当前版本    : ${VERSION}
 最新正式版  : ${LATEST_VERSION}
 开机启动      : ${ENABLE}
 配置状态      : ${CONFIG}
 配置文件      : ${CONFIG_FILE}
 路由模式      : ${ROUTE_MODE}

 CPU占用       : ${CPU_DISPLAY} %
 内存占用      : ${MEM_DISPLAY} MB

 网络状态      : ${NETWORK}
 TUN           : ${TUN_STATUS}
 IP Forward    : ${FORWARD_STATUS}
 Clash API     : ${CLASH_API}
 Zashboard     : ${ZASHBOARD}
 配置链接      : ${CONFIG_URL_STATUS}

 启动时间      : ${START_TIME}


======================================================================

 1. 安装/升级 Sing-box

 2. 配置管理

 3. 运行管理

 4. 路由设置

 5. 工具箱

 6. Web 面板

 0. 退出

======================================================================

EOF

DASHBOARD_DRAWN=1

}

# Update only the two numeric fields in the already rendered dashboard.
# Rows are zero-based and match the fixed dashboard layout above.
refresh_dashboard_metrics(){
    local cpu_use mem_use pid proc_ticks total_ticks delta_proc delta_total cores
    pid=$(pidof sing-box 2>/dev/null | awk '{print $1}')

    cpu_use=0
    if [ -n "$pid" ] && [ -r "/proc/$pid/stat" ]; then
        proc_ticks=$(awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null)
        total_ticks=$(awk '/^cpu / {sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum; exit}' /proc/stat)
        if [ -n "${DASHBOARD_PREV_PROC_TICKS:-}" ] && \
           [ -n "${DASHBOARD_PREV_TOTAL_TICKS:-}" ]; then
            delta_proc=$((proc_ticks - DASHBOARD_PREV_PROC_TICKS))
            delta_total=$((total_ticks - DASHBOARD_PREV_TOTAL_TICKS))
            cores=$(nproc)
            if [ "$delta_total" -gt 0 ]; then
                cpu_use=$(awk -v p="$delta_proc" -v t="$delta_total" -v c="$cores" \
                    'BEGIN {printf "%.1f", p * c * 100 / t}')
            fi
        fi
        DASHBOARD_PREV_PROC_TICKS="$proc_ticks"
        DASHBOARD_PREV_TOTAL_TICKS="$total_ticks"
    fi

    mem_use=$(ps -C sing-box -o rss= | awk '{sum+=$1} END{printf "%.1f",sum/1024}')
    [ -n "$cpu_use" ] || cpu_use=0
    [ -n "$mem_use" ] || mem_use=0

    # Save the input cursor, update fixed-width fields, then restore it.
    printf '\0337\033[29;18H%10.1f\033[30;18H%10.1f\0338' \
        "$cpu_use" "$mem_use"
}
