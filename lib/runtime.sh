#!/bin/bash

start_singbox(){

info "启动 Sing-box..."

systemctl start sing-box

if systemctl is-active --quiet sing-box; then
    ok "Sing-box 已启动"
else
    error "启动失败"
fi

pause

}
stop_singbox(){

info "停止 Sing-box..."

systemctl stop sing-box

ok "Sing-box 已停止"

pause

}
restart_singbox(){

info "重启 Sing-box..."

systemctl restart sing-box

if systemctl is-active --quiet sing-box; then
    ok "Sing-box 已重启"
else
    error "重启失败"
fi

pause

}
status_singbox(){

systemctl status sing-box --no-pager

pause

}
log_singbox(){

clear

echo
echo "Ctrl+C 返回菜单"
echo

journalctl -fu sing-box

}
version_singbox(){

echo

$SINGBOX_BIN version

pause

}
cpu_singbox(){

clear

echo
echo "==========================="
echo " Sing-box CPU"
echo "==========================="
echo

top -bn1 | grep sing-box

echo

pause

}
memory_singbox(){

echo

ps -o pid,%cpu,%mem,rss,vsz,cmd -C sing-box

echo

pause

}
uptime_singbox(){

echo

systemctl show sing-box \
-p ActiveEnterTimestamp \
-p ActiveState

pause

}

runtime_menu(){

while true
do

clear

cat <<EOF

======================================
          运行管理
======================================

1. 启动 Sing-box

2. 停止 Sing-box

3. 重启 Sing-box

4. 查看运行状态

5. 查看日志

6. 查看版本

7. 查看CPU占用

8. 查看内存占用

9. 查看运行时间

0. 返回

======================================

EOF

read -p "请选择：" NUM

case "$NUM" in

1)

start_singbox

;;

2)

stop_singbox

;;

3)

restart_singbox

;;

4)

status_singbox

;;

5)

log_singbox

;;

6)

version_singbox

;;

7)

cpu_singbox

;;

8)

memory_singbox

;;

9)

uptime_singbox

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

