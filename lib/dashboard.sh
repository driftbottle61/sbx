#!/bin/bash

dashboard() {

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

else

    VERSION="未安装"

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

# Avoid full-screen clear on periodic refreshes. Repositioning the cursor
# keeps the dashboard stable and prevents the visible blink caused by `clear`.
if [ "${DASHBOARD_DRAWN:-0}" = "1" ]; then
    # Clear from the cursor to the end, including a timed-out menu prompt,
    # without the terminal-wide flash caused by the clear command.
    printf '\033[H\033[J'
else
    clear
    DASHBOARD_DRAWN=1
fi

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
 当前版本      : ${VERSION}
 开机启动      : ${ENABLE}
 配置状态      : ${CONFIG}
 配置文件      : ${CONFIG_FILE}
 路由模式      : ${ROUTE_MODE}

 CPU占用       : ${CPU_USE} %
 内存占用      : ${MEM_USE} MB

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

}
