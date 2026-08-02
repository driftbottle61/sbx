#!/bin/bash


create_service(){

mkdir -p /etc/systemd/system

if command -v ensure_sbx_group >/dev/null 2>&1; then

ensure_sbx_group

fi


cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org
After=network-online.target
Wants=network-online.target


[Service]

Type=simple

User=root

Group=${SBX_GROUP:-sbx}

ExecStartPre=-/opt/sbx/sbx-route stop

ExecStartPre=/opt/sbx/sbx-route prepare-config

ExecStart=$SINGBOX_BIN run -c $CONFIG_FILE

ExecStartPost=-/opt/sbx/sbx-route start

ExecStopPost=-/opt/sbx/sbx-route stop

Restart=on-failure

RestartSec=5

LimitNOFILE=1048576


[Install]

WantedBy=multi-user.target

EOF


systemctl daemon-reload


ok "systemd 服务创建完成"

}


start_service(){

systemctl start "$SERVICE_NAME"

}


stop_service(){

systemctl stop "$SERVICE_NAME"

}


restart_service(){

systemctl restart "$SERVICE_NAME"

}


status_service(){

systemctl status "$SERVICE_NAME" --no-pager

}


enable_service(){

systemctl enable "$SERVICE_NAME"

ok "已设置开机启动"

}


disable_service(){

systemctl disable "$SERVICE_NAME"

ok "已取消开机启动"

}


service_menu(){


while true
do


clear


cat <<EOF

================================

       Sing-box 服务管理

================================


1. 创建 systemd 服务

2. 启动 Sing-box

3. 停止 Sing-box

4. 重启 Sing-box

5. 查看状态

6. 开机启动

7. 禁止开机启动


0. 返回


================================

EOF


read -p "请选择：" NUM


case "$NUM" in


1)
create_service
pause
;;


2)
start_service
pause
;;


3)
stop_service
pause
;;


4)
restart_service
pause
;;


5)
status_service
pause
;;


6)
enable_service
pause
;;


7)
disable_service
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
