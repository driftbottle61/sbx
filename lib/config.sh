#!/bin/bash

config_file="/opt/sbx/data/sbx.conf"

load_config(){

    if [ -f "$config_file" ];then

        source "$config_file"

    fi

}
set_config_url(){

load_config

clear

echo
echo "==============="
echo "设置配置地址"
echo "==============="
echo

read -p "请输入配置URL：" URL

if [ -z "$URL" ];then

    warn "不能为空"

    pause

    return

fi

[ -z "$ROUTE_MODE" ] && ROUTE_MODE="tproxy"


cat > "$config_file" <<EOF
SBX_VERSION="${SBX_VERSION}"
CONFIG_DIR="${CONFIG_DIR}"
CONFIG_FILE="${CONFIG_FILE}"
CONFIG_BACKUP="${CONFIG_BACKUP}"
CONFIG_URL="${URL}"
SINGBOX_BIN="${SINGBOX_BIN}"
SERVICE_NAME="${SERVICE_NAME}"
SERVICE_FILE="${SERVICE_FILE}"
ROUTE_MODE="${ROUTE_MODE}"
EOF

ok "配置保存成功"

pause

}
show_config_url(){

clear

echo
echo "==============="
echo "当前配置地址"
echo "==============="
echo

load_config

echo "$CONFIG_URL"

echo

pause

}
update_config(){

load_config

if [ -z "$CONFIG_URL" ];then

    warn "请先设置配置地址"

    pause

    return

fi


info "开始下载配置..."

mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ];then

    cp "$CONFIG_FILE" "$CONFIG_BACKUP"

fi


sbx_curl "$CONFIG_URL" -o /tmp/config.json


if [ $? -ne 0 ];then

    error "下载失败"

    pause

    return

fi


info "检查配置..."

"$SINGBOX_BIN" check \
-c /tmp/config.json


if [ $? -ne 0 ];then

    error "配置检查失败"

    if [ -f "$CONFIG_BACKUP" ];then

        cp "$CONFIG_BACKUP" "$CONFIG_FILE"

    fi

    pause

    return

fi


mv /tmp/config.json "$CONFIG_FILE"

ok "配置更新成功"

if command -v prepare_singbox_route_config >/dev/null 2>&1; then

    prepare_singbox_route_config

fi

systemctl restart sing-box

ok "Sing-box 已重启"

pause

}
check_config(){

if [ ! -f "$CONFIG_FILE" ];then

    warn "配置不存在"

    pause

    return

fi


"$SINGBOX_BIN" check \
-c "$CONFIG_FILE"

pause

}
config_menu(){

while true
do

clear

cat <<EOF

==============================
        配置管理
==============================

1. 设置配置地址

2. 查看配置地址

3. 更新配置

4. 检查配置

0. 返回

==============================

EOF

read -p "请选择：" NUM

case "$NUM" in

1)

set_config_url

;;

2)

show_config_url

;;

3)

update_config

;;

4)

check_config

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
