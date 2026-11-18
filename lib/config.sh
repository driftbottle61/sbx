#!/bin/bash

config_file="/opt/sbx/data/sbx.conf"

load_config(){

    if [ -f "$config_file" ];then

        source "$config_file"

    fi

}

config_set(){
    local key="$1" value="$2" file="${3:-$config_file}" tmp

    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
        error "非法配置项名称：$key"
        return 1
    }
    [ -f "$file" ] || : > "$file" || return 1

    tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
    if ! CONFIG_SET_KEY="$key" CONFIG_SET_VALUE="$value" awk '
        BEGIN {
            key = ENVIRON["CONFIG_SET_KEY"]
            val = ENVIRON["CONFIG_SET_VALUE"]
            gsub(/\r/, "", val)
            gsub(/\n/, " ", val)
            gsub(/\\/, "\\\\", val)
            gsub(/"/, "\\\"", val)
            gsub(/\$/, "\\$", val)
            gsub(/`/, "\\`", val)
            replacement = key "=\"" val "\""
        }
        index($0, key "=") == 1 { print replacement; found = 1; next }
        { print }
        END { if (!found) print replacement }
    ' "$file" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    cat "$tmp" > "$file" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    return 0
}

save_config_urls(){
    local rc=0
    config_set SBX_VERSION "$SBX_VERSION" || rc=1
    config_set CONFIG_DIR "$CONFIG_DIR" || rc=1
    config_set CONFIG_FILE "$CONFIG_FILE" || rc=1
    config_set CONFIG_BACKUP "$CONFIG_BACKUP" || rc=1
    config_set CONFIG_URL "$CONFIG_URL" || rc=1
    config_set CONFIG_URL_TPROXY "${CONFIG_URL_TPROXY:-}" || rc=1
    config_set CONFIG_URL_TUN "${CONFIG_URL_TUN:-}" || rc=1
    config_set SINGBOX_BIN "$SINGBOX_BIN" || rc=1
    config_set SERVICE_NAME "$SERVICE_NAME" || rc=1
    config_set SERVICE_FILE "$SERVICE_FILE" || rc=1
    config_set ROUTE_MODE "${ROUTE_MODE:-tproxy}" || rc=1
    return "$rc"
}

set_config_url_value(){
local URL="$1"
load_config

[ -n "$URL" ] || return 1

clear

echo
echo "==============="
echo "设置配置地址"
echo "==============="
echo

[ -z "$ROUTE_MODE" ] && ROUTE_MODE="tproxy"

CONFIG_URL="$URL"
if ! save_config_urls; then
    error "配置保存失败"
    return 1
fi

ok "配置保存成功"

}

set_config_urls(){
    local tproxy_url="$1" tun_url="$2"
    load_config
    CONFIG_URL_TPROXY="$tproxy_url"
    CONFIG_URL_TUN="$tun_url"
    if [ "$ROUTE_MODE" = "tun" ]; then CONFIG_URL="$tun_url"; else CONFIG_URL="$tproxy_url"; fi
    if ! save_config_urls; then
        error "配置保存失败"
        return 1
    fi
    ok "配置保存成功"
}

select_config_url_for_mode(){
    load_config
    if [ "$ROUTE_MODE" = "tun" ] && [ -n "${CONFIG_URL_TUN:-}" ]; then
        CONFIG_URL="$CONFIG_URL_TUN"
    elif [ "$ROUTE_MODE" != "tun" ] && [ -n "${CONFIG_URL_TPROXY:-}" ]; then
        CONFIG_URL="$CONFIG_URL_TPROXY"
    fi
    set_config_url_value "$CONFIG_URL"
}

set_config_url(){

load_config

clear

echo
echo "==============="
echo "设置配置地址"
echo "==============="
echo

read -r -p "请输入配置URL：" URL

if [ -z "$URL" ];then
warn "不能为空"
pause
return
fi

if [ "$ROUTE_MODE" = "tun" ]; then
    CONFIG_URL_TUN="$URL"
else
    CONFIG_URL_TPROXY="$URL"
fi
CONFIG_URL="$URL"
if ! save_config_urls; then
    error "配置保存失败"
    pause
    return 1
fi
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

echo "TProxy 配置 URL：${CONFIG_URL_TPROXY:-未设置}"
echo "TUN 配置 URL    ：${CONFIG_URL_TUN:-未设置}"
echo "当前路由模式    ：${ROUTE_MODE:-未设置}"
echo "当前使用 URL    ：${CONFIG_URL:-未设置}"

echo

pause

}

show_active_config_context(){
    load_config
    if [ "$ROUTE_MODE" = "tun" ]; then
        mode_label="TUN"
    else
        mode_label="TProxy"
    fi
    if [ -n "${CONFIG_URL_TPROXY:-}" ] || [ -n "${CONFIG_URL_TUN:-}" ]; then
        select_config_url_for_mode
        load_config
    fi
    echo
    echo "当前配置模式：$mode_label"
    echo "当前配置地址：${CONFIG_URL:-未设置}"
    echo "配置文件路径：${CONFIG_FILE:-/etc/sing-box/config.json}"
    echo
}
update_config(){

load_config

if [ -n "${CONFIG_URL_TPROXY:-}" ] || [ -n "${CONFIG_URL_TUN:-}" ]; then
    select_config_url_for_mode
    load_config
fi
show_active_config_context

if [ -z "$CONFIG_URL" ];then

    warn "请先设置配置地址"

    pause

    return

fi


info "开始下载配置..."

warn "订阅模板会整份覆盖当前 config.json；自定义节点/规则请放到 Sub-Store 模板中"

mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ];then

    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    mkdir -p "${SBX_CONFIG_BACKUP_DIR:-/opt/sbx/backup/config}"
    cp "$CONFIG_FILE" "${SBX_CONFIG_BACKUP_DIR:-/opt/sbx/backup/config}/config.json.$(date +%Y%m%d%H%M%S).bak" 2>/dev/null || true

fi


config_tmp="$(mktemp /tmp/sbx-config.XXXXXX)" || {
    error "无法创建配置临时文件"
    pause
    return 1
}


url_escaped="$(printf '%s' "$CONFIG_URL" | sed 's/[\\"]/\\\\&/g')"

if ! printf 'url = "%s"\n' "$url_escaped" | sbx_curl -K - -o "$config_tmp"; then

    rm -f "$config_tmp"
    error "下载失败"

    pause

    return

fi


info "检查配置..."

if ! "$SINGBOX_BIN" check \
-c "$config_tmp"; then

    rm -f "$config_tmp"
    error "配置检查失败"

    if [ -f "$CONFIG_BACKUP" ];then

        cp "$CONFIG_BACKUP" "$CONFIG_FILE"

    fi

    pause

    return

fi


if ! mv "$config_tmp" "$CONFIG_FILE"; then
    rm -f "$config_tmp"
    error "写入配置文件失败"
    pause
    return 1
fi

ok "配置更新成功"

if command -v prepare_singbox_route_config >/dev/null 2>&1; then

    prepare_singbox_route_config

fi

if ! systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
    warn "未找到 $SERVICE_NAME，正在创建 systemd 服务..."
    if ! command -v create_service >/dev/null 2>&1 || ! create_service; then
        error "systemd 服务创建失败，配置已保存但尚未启动"
        pause
        return 1
    fi
fi

systemctl daemon-reload
if systemctl restart "$SERVICE_NAME" && systemctl is-active --quiet "$SERVICE_NAME"; then
    ok "Sing-box 已重启"
else
    error "Sing-box 重启失败，配置已保存但服务未正常运行"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    pause
    return 1
fi

pause

}
check_config(){

load_config
if [ -n "${CONFIG_URL_TPROXY:-}" ] || [ -n "${CONFIG_URL_TUN:-}" ]; then
    select_config_url_for_mode
    load_config
fi
show_active_config_context

if [ ! -f "$CONFIG_FILE" ];then

    warn "配置不存在"

    pause

    return

fi


"$SINGBOX_BIN" check \
-c "$CONFIG_FILE"

pause

}

set_dual_config_urls(){
    load_config
    echo
    echo "设置 TProxy/TUN 双配置地址"
    read -r -p "TProxy 配置 URL [${CONFIG_URL_TPROXY:-未设置}]：" tproxy_url
    read -r -p "TUN 配置 URL [${CONFIG_URL_TUN:-未设置}]：" tun_url
    [ -n "$tproxy_url" ] || tproxy_url="${CONFIG_URL_TPROXY:-}"
    [ -n "$tun_url" ] || tun_url="${CONFIG_URL_TUN:-}"
    if [ -z "$tproxy_url" ] || [ -z "$tun_url" ]; then
        warn "两条配置 URL 都不能为空"
        pause
        return
    fi
    set_config_urls "$tproxy_url" "$tun_url"
    select_config_url_for_mode
    update_config
}
config_menu(){

while true
do

clear

cat <<EOF

==============================
        配置管理
==============================

1. 设置 TProxy/TUN 双配置地址

2. 查看配置地址

3. 更新配置

4. 检查配置

0. 返回

==============================

EOF

read -p "请选择：" NUM

case "$NUM" in

1)

set_dual_config_urls

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
